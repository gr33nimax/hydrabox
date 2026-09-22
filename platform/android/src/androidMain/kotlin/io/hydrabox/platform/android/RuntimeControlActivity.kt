package io.hydrabox.platform.android

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.content.ServiceConnection
import android.net.VpnService
import android.os.Bundle
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.SystemClock
import androidx.activity.ComponentActivity
import androidx.activity.OnBackPressedCallback
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import io.hydrabox.core.contract.CommandGeneration
import io.hydrabox.core.contract.EventSequence
import io.hydrabox.core.contract.NetworkGeneration
import io.hydrabox.core.contract.OutboundLatency
import io.hydrabox.core.contract.ProcessEpoch
import io.hydrabox.core.contract.RuntimeCommand
import io.hydrabox.core.contract.RuntimeEvent
import io.hydrabox.core.contract.RuntimeGeneration
import io.hydrabox.core.contract.RuntimeMode
import io.hydrabox.core.contract.RuntimeSnapshot
import io.hydrabox.core.contract.RuntimeState
import io.hydrabox.core.model.OperationError
import io.hydrabox.core.model.OperationState
import io.hydrabox.core.projection.AppReadModel
import io.hydrabox.core.projection.Appearance
import io.hydrabox.core.projection.AppsMode
import io.hydrabox.core.projection.DiagnosticsSummary
import io.hydrabox.core.projection.DnsMode
import io.hydrabox.core.projection.ExitAddress
import io.hydrabox.core.projection.JournalEntry
import io.hydrabox.core.projection.JournalLevel
import io.hydrabox.core.projection.Language
import io.hydrabox.core.projection.LogDetail
import io.hydrabox.core.projection.Notice
import io.hydrabox.core.projection.NotificationDetail
import io.hydrabox.core.projection.RuleSetsSummary
import io.hydrabox.core.projection.ScreenProjection
import io.hydrabox.core.projection.TlsFragmentation
import io.hydrabox.core.projection.TunnelStack
import io.hydrabox.core.projection.UpdateChannel
import io.hydrabox.core.projection.UpdateSummary
import io.hydrabox.core.projection.nextLatencyStaleAtMillis
import io.hydrabox.core.projection.runningOutboundTag
import io.hydrabox.core.settings.AppLanguage
// The chosen channel and the shown one are the same product concept seen from either side of the
// projection, so they share a name and only one of them can be imported plainly.
import io.hydrabox.core.settings.UpdateChannel as SettingsUpdateChannel
import io.hydrabox.core.update.InstallFault
import io.hydrabox.core.update.UpdateDecision
import io.hydrabox.core.update.UpdateManifest
import io.hydrabox.core.settings.DnsStrategy
import io.hydrabox.core.settings.LogLevel
import io.hydrabox.core.settings.NotificationTrafficDisplayMode
import io.hydrabox.core.settings.PerformanceMode
import io.hydrabox.core.settings.SplitRoutingMode
import io.hydrabox.core.settings.ThemeMode
import io.hydrabox.core.settings.TlsFragmentationMode
import io.hydrabox.core.settings.TunStack
import io.hydrabox.core.subscription.SourceFailure
import io.hydrabox.core.subscription.SubscriptionException
import io.hydrabox.ui.app.AppActions
import io.hydrabox.ui.app.AppNavigation
import io.hydrabox.ui.app.HydraApp
import io.hydrabox.ui.app.Route
import kotlinx.coroutines.delay
import java.util.concurrent.Executors

/**
 * Composition root. It binds the runtime, combines the read models and hands them to the
 * projection. It holds no phase of its own and no branch on runtime state; what it does own
 * is what only the platform can know: the system consent and which thread a store call runs on.
 */
class RuntimeControlActivity : ComponentActivity() {
    private lateinit var store: AppStore
    private val io = Executors.newSingleThreadExecutor()

    /**
     * Reading the stored model has its own thread. Sharing [io] with imports and backups meant
     * a refresh queued behind a network fetch, and the screens showed the previous world for as
     * long as the fetch took — including the first run's welcome screen over a device that
     * already had a subscription.
     */
    private val reader = Executors.newSingleThreadExecutor()
    private val exitReader = Executors.newSingleThreadExecutor()
    private var cancelExit: (() -> Unit)? = null
    private var exitWatchdog: Runnable? = null
    private var exitRequest = 0L
    private var destroyed = false
    private var refreshPending = false
    private var refreshAgain = false
    private var journalPending = false
    private var journalRevision = -1L
    private var lastLocalLog: HydraLog.Entry? = null
    private var bindingGeneration = 0L
    private val main = Handler(Looper.getMainLooper())
    private val navigation = AppNavigation()
    private var transport: BinderRuntimeTransport? = null
    private var subscription: AutoCloseable? = null

    private var snapshot by mutableStateOf(stoppedSnapshot())

    /** The stored half of the read model. Replaced wholesale by [refresh]. */
    private var stored by mutableStateOf(AppReadModel(runtime = stoppedSnapshot()))
    private var notice by mutableStateOf<Notice?>(null)
    private var busy by mutableStateOf<OperationState<Unit>>(OperationState.Idle)
    private var showApps by mutableStateOf(false)
    private var updatingRules by mutableStateOf(false)
    private var updatingRussiaRules by mutableStateOf(false)
    private var permissionMissing by mutableStateOf(false)

    /**
     * What the updater last found. Held here rather than in the store because it is a fact about
     * this visit: nothing is remembered between runs, and a check nobody asked for leaves no trace.
     */
    private var updateState by mutableStateOf(UpdateSummary())

    /**
     * The verified document a check produced. Installing needs its digests, so the manifest is kept
     * rather than only the version a person sees.
     */
    private var pendingUpdate by mutableStateOf<UpdateManifest?>(null)

    /**
     * Where the tunnel comes out. Probed once per connection and on demand, never on the main
     * thread, and cleared the moment the tunnel goes down so a stale address cannot outlive it.
     */
    private var exit by mutableStateOf(ExitAddress())

    /**
     * Whether an exit question was interrupted by the screens going away rather than
     * answered. Only that case resumes on return: "unknown" from the watchdog is an
     * answer, and re-asking it every visit is a loop nobody asked for.
     */
    private var exitProbeHidden = false

    /**
     * Android 13 shows nothing without this, and the tunnel's notification is the only place
     * a person can see it is up — or press disconnect — without opening the app. The alpha
     * declared the permission and never asked for it.
     */
    private val notifications =
        registerForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
            HydraLog.info(AREA, "notification permission ${if (granted) "granted" else "refused"}")
        }

    private val permission =
        registerForActivityResult(ActivityResultContracts.StartActivityForResult()) { result ->
            if (result.resultCode == RESULT_OK) {
                permissionMissing = false
                launch()
            } else {
                permissionMissing = true
                notice = Notice.VPN_PERMISSION_DENIED
            }
        }

    /** Held between the passphrase question and the file picker, and wiped straight after. */
    private var pendingPassphrase: CharArray? = null

    private val exportFile =
        registerForActivityResult(
            ActivityResultContracts.CreateDocument("application/octet-stream"),
        ) { uri -> writeBackup(uri) }

    private val importFile =
        registerForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
            readBackup(uri)
        }

    /** Whether the screens are on screen. The snapshot stream is worth paying for only then. */
    private var started by mutableStateOf(false)

    /** Whether this activity currently holds a binding to the tunnel service. */
    private var bound = false

    private val connection =
        object : ServiceConnection {
            override fun onServiceConnected(
                name: ComponentName?,
                binder: IBinder?,
            ) {
                binder ?: return
                BinderRuntimeTransport(binder).let { bound ->
                    transport = bound
                    observe(runCatching { bound.snapshot() }.getOrElse { stoppedSnapshot() })
                    if (started) attach()
                }
            }

            override fun onServiceDisconnected(name: ComponentName?) {
                subscription = null
                transport = null
                observe(stoppedSnapshot())
            }
        }

    /**
     * Starts the snapshot stream, which ticks once a second for as long as a tunnel is up.
     *
     * It is bound to visibility rather than to the process: an invisible activity kept
     * receiving every tick, waking the interface process sixty times a minute to write a state
     * nobody was drawing. Measured with the screen off, that made the interface process burn
     * more CPU than the core it was watching. The binding itself stays — it costs nothing idle,
     * and commands still need it — and the tunnel does not depend on either, because the
     * service is started with `startForegroundService`, not merely bound.
     */
    private fun attach() {
        val bound = transport ?: return
        if (subscription != null) return
        val binding = ++bindingGeneration
        subscription =
            runCatching {
                bound.subscribe { event ->
                    (event as? RuntimeEvent.Snapshot)?.let { update ->
                        main.post {
                            if (binding == bindingGeneration && started && !destroyed) observe(update.snapshot)
                        }
                    }
                }
            }.getOrNull()
    }

    private fun detach() {
        bindingGeneration++
        runCatching { subscription?.close() }
        subscription = null
    }

    override fun onStart() {
        super.onStart()
        started = true
        bind()
        // What happened while nobody was looking arrives in one read, before the stream resumes.
        transport?.let { bound -> runCatching { bound.snapshot() }.getOrNull()?.let(::observe) }
        attach()
        // A question cut short by leaving the screens is asked again, once, on return: the
        // snapshot that comes back with the same route does not re-trigger it, so without
        // this the address stays unknown until something else changes. A question that
        // ran out of its own deadline answered "unknown" and stays answered.
        if (exitProbeHidden) {
            exitProbeHidden = false
            if (snapshot.state == RuntimeState.RUNNING && !exit.checking && exit.address == null) probeExit()
        }
    }

    override fun onStop() {
        started = false
        if (exit.checking) exitProbeHidden = true
        stopExitProbe()
        detach()
        unbind()
        super.onStop()
    }

    /**
     * Connects to the tunnel service, without bringing it up.
     *
     * This used to happen once in `onCreate`, with `BIND_AUTO_CREATE`, and stay for the life of
     * the activity. The flag did two things nobody asked for. Opening the application created the
     * service — and with it the `:core` process, its database and its network monitor — before
     * anything had been asked of it; and a bound client keeps a service alive, so after a
     * disconnect the service had called `stopSelf`, was no longer started, and still could not be
     * destroyed. A dump taken at that moment says it exactly: `startRequested=false`, one binding,
     * `CREATE`, owned by the interface process — an idle core holding ~210 MB of PSS with no tunnel
     * to show for it, held there by the screens alone.
     *
     * Without the flag the bind reaches the service only while something else is keeping it — the
     * tunnel itself, the tile, or the system's always-on — and [unbind] lets go when the screens
     * do. The Quick Settings tile already binds this way, for the same reason.
     */
    private fun bind(createIfMissing: Boolean = false) {
        if (bound) return
        val flags = if (createIfMissing) Context.BIND_AUTO_CREATE else 0
        bound =
            runCatching { bindService(Intent(this, HydraVpnService::class.java), connection, flags) }
                .getOrDefault(false)
        if (!bound) runCatching { unbindService(connection) }
    }

    private fun unbind() {
        if (!bound) return
        bound = false
        runCatching { unbindService(connection) }
        transport = null
    }

    /** The only state derived from a transition rather than from the snapshot itself. */
    private fun exitRoute(value: RuntimeSnapshot) =
        listOf(
            value.processEpoch,
            value.runtimeGeneration,
            value.networkGeneration,
            value.mode,
            value.observedOutbounds,
        )

    private fun observe(next: RuntimeSnapshot) {
        if (next.processEpoch == snapshot.processEpoch && next.lastEventSequence.value < snapshot.lastEventSequence.value) return
        // A standalone sweep owns a short-lived service. Its last empty STOPPED snapshot must not
        // erase answers it just delivered; retain each tag until this or a later service provides
        // that tag's next answer. The projection still marks old answers stale by their own TTL.
        val retained =
            next.copy(
                latencies = mergeLatencies(snapshot.latencies, next.latencies),
                edgeLatencies = mergeLatencies(snapshot.edgeLatencies, next.edgeLatencies),
            )
        val previous = snapshot
        snapshot = retained
        if (retained.state != previous.state) refresh()
        // The first frame runs before the binder answers, so the visibility report sent at
        // resume found a stopped runtime and was dropped. The moment the screens learn there is
        // a tunnel, they say again that they are in front of the person — otherwise a captcha
        // arriving in the first seconds would be announced by a notification on top of the very
        // screen that is already drawing it.
        if (visible && retained.state != previous.state && retained.state != RuntimeState.STOPPED) reportUiVisibility(true)
        val changedRoute = exitRoute(retained) != exitRoute(previous)
        if (changedRoute) {
            HydraLog.info(AREA, "the route changed: ${exitRoute(previous)} -> ${exitRoute(retained)}")
        }
        if (retained.state != RuntimeState.RUNNING) {
            stopExitProbe()
            exit = ExitAddress()
        } else if (started && (previous.state != RuntimeState.RUNNING || changedRoute)) {
            probeExit()
        } else if (changedRoute && !started) {
            HydraLog.info(AREA, "a route change arrived while the screens were off; the exit will be asked when they come back")
        }
    }

    private fun mergeLatencies(
        previous: List<OutboundLatency>,
        incoming: List<OutboundLatency>,
    ): List<OutboundLatency> = (previous + incoming).associateBy { it.tag }.values.toList()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        store = AppStore(this)
        // Once, before the first frame: a read model that does not yet know whether the terms
        // were accepted would draw the first run at somebody who finished it months ago.
        runCatching { store.settings() }
            .onSuccess { settings ->
                // Whether a subscription exists is the same kind of fact and has the same deadline.
                // A failed probe is deliberately not read as "no subscription": that conclusion is the
                // one that draws the first-run flow at the wrong person, and the read below corrects
                // it a moment later.
                val primed = runCatching { store.records().isNotEmpty() }.getOrDefault(true)
                stored =
                    stored.copy(
                        legalAccepted = settings.acceptedLegalAtMillis != null,
                        settings = store.settingsSummary(settings),
                        hasStoredSources = primed,
                    )
            }.onFailure { notice = Notice.OPERATION_FAILED }
        onBackPressedDispatcher.addCallback(
            this,
            object : OnBackPressedCallback(true) {
                override fun handleOnBackPressed() {
                    // The question is modal, and its "close" is the only way to tell the core to
                    // stop waiting: without this, Back hid the screen and left the core waiting
                    // out its window for an answer that could no longer be given.
                    val challenge = snapshot.challenge
                    if (challenge != null) {
                        send(RuntimeCommand.CancelChallenge(challenge.id))
                        return
                    }
                    if (!navigation.back()) {
                        isEnabled = false
                        onBackPressedDispatcher.onBackPressed()
                        isEnabled = true
                    }
                }
            },
        )
        setContent {
            val latencyExpiryRenderedAt = remember { mutableStateOf(0L) }
            LaunchedEffect(navigation.route, started) {
                if (started && navigation.route == Route.Journal) {
                    while (true) {
                        refreshJournal()
                        delay(1_000)
                    }
                }
            }
            LaunchedEffect(started, snapshot.latencies) {
                if (!started) return@LaunchedEffect
                // Every boundary, not only the first: after one probe turns old the next
                // still-fresh one needs its own redraw, or a quiet screen keeps calling it
                // fresh until some other event happens along.
                while (true) {
                    val now = System.currentTimeMillis()
                    val staleAt = nextLatencyStaleAtMillis(snapshot.latencies + snapshot.edgeLatencies, now) ?: break
                    delay((staleAt - now).coerceAtLeast(1))
                    latencyExpiryRenderedAt.value = staleAt
                }
            }
            Box(modifier = Modifier.fillMaxSize()) {
                HydraApp(
                    state =
                        ScreenProjection.project(
                            readModel(),
                            nowMillis = System.currentTimeMillis().also { latencyExpiryRenderedAt.value },
                        ),
                    actions = actions(),
                    navigation = navigation,
                    versionName = BuildConfig.VERSION_NAME,
                    coreVersion = BuildConfig.HYDRACORE_VERSION,
                )
                // The core's own question, when it has one, over everything else: the captcha
                // page answers only on this device's loopback, so there is nowhere else to
                // send a person.
                snapshot.challenge?.let { challenge ->
                    ChallengeOverlay(
                        challenge = challenge,
                        onDismiss = { send(RuntimeCommand.CancelChallenge(challenge.id)) },
                    )
                }
            }
        }
        askForNotifications()
        io.execute { runCatching { SubscriptionRefreshJob.schedule(applicationContext) } }
        refresh()
        handle(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handle(intent)
    }

    override fun onResume() {
        super.onResume()
        visible = true
        reportUiVisibility(true)
    }

    override fun onPause() {
        visible = false
        reportUiVisibility(false)
        super.onPause()
    }

    /**
     * Tells the core process whether the screens are in front of the person.
     *
     * The service cannot see this activity's lifecycle — it is another process — and it is the
     * one that must decide between drawing the core's question here and posting a notification
     * about it. Nothing is sent while the tunnel is stopped: there is no question to raise then,
     * and starting the core service to hear about a screen would open its database and network
     * monitor for nothing.
     */
    private fun reportUiVisibility(visibleNow: Boolean) {
        if (snapshot.state == RuntimeState.STOPPED) return
        runCatching {
            startService(
                Intent(this, HydraVpnService::class.java)
                    .setAction(HydraVpnService.ACTION_UI_VISIBILITY)
                    .putExtra(HydraVpnService.EXTRA_UI_VISIBLE, visibleNow),
            )
        }
    }

    private fun askForNotifications() {
        if (android.os.Build.VERSION.SDK_INT < android.os.Build.VERSION_CODES.TIRAMISU) return
        val granted =
            checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS) ==
                android.content.pm.PackageManager.PERMISSION_GRANTED
        if (!granted) runCatching { notifications.launch(android.Manifest.permission.POST_NOTIFICATIONS) }
    }

    /**
     * What the app was opened with. A subscription is shared as a link far more often than it
     * is typed, so `hydrabox://import`, sing-box's own import scheme and a plain shared text
     * all end in the same place: the import that the sources screen runs.
     */
    private fun handle(intent: Intent?) {
        intent ?: return
        if (intent.action == ACTION_REQUEST_START) return prepareAndStart()
        val candidate =
            when (intent.action) {
                Intent.ACTION_VIEW -> intent.data?.let(::sourceOf)
                Intent.ACTION_SEND -> intent.getStringExtra(Intent.EXTRA_TEXT)?.trim()
                else -> null
            }?.takeIf(String::isNotEmpty) ?: return
        HydraLog.info(AREA, "opened with a link to import")
        navigation.open(Route.Sources)
        background(Notice.SOURCE_ADDED) { store.addSubscription("", candidate) }
    }

    /**
     * The link inside the link. Both import schemes wrap the real address in a `url`
     * parameter; anything else is passed through as it stands, because a share link is a
     * subscription too.
     */
    private fun sourceOf(uri: android.net.Uri): String? {
        val wrapped = runCatching { uri.getQueryParameter("url") }.getOrNull()?.trim()
        if (!wrapped.isNullOrEmpty()) return wrapped
        return uri.toString().takeUnless { it.startsWith("hydrabox://") || it.startsWith("sing-box://") }
    }

    override fun onDestroy() {
        destroyed = true
        stopExitProbe()
        exitReader.shutdownNow()
        detach()
        // The screens let go of the service through the same flag the release is tracked by, so
        // `onDestroy` after `onStop` is a no-op rather than a second unbind of a connection that
        // is no longer registered.
        unbind()
        io.execute {
            reader.execute { store.close() }
            reader.shutdown()
        }
        io.shutdown()
        super.onDestroy()
    }

    /**
     * What the screens read: the stored half, refreshed when something changes it, plus the
     * live half, which is free to change every second.
     *
     * The split is not tidiness. This was assembled inside the composition, so every
     * recomposition — one per traffic counter, once a second — opened the database, read the
     * settings and parsed every stored subscription document on the main thread.
     */
    private fun readModel(): AppReadModel =
        stored.copy(
            runtime = snapshot,
            // The exit answer arrives on its own schedule — between the refreshes that reload
            // the stored half — and it used to travel only through them: the probe wrote the
            // field, nothing in the composition read it, and the row kept drawing whatever the
            // last refresh had captured, which was usually "checking". The live field renders
            // the moment it changes, exactly as the live snapshot does.
            exit = exit,
            apps = if (showApps) stored.apps else emptyList(),
            ruleSets = stored.ruleSets.copy(downloading = updatingRules, russiaDownloading = updatingRussiaRules),
            sourceOperation = busy,
            vpnPermissionMissing = permissionMissing,
            notice = notice,
        )

    /**
     * Reloads the stored half off the main thread. Cheap to call; never called in a draw.
     *
     * Whether the app list is wanted is decided here, on the main thread, and carried into the
     * read: `load` used to enumerate every launchable package and resolve its label on every
     * refresh, and [readModel] threw the result away unless the picker happened to be open. That
     * is a full pass over `PackageManager` for each change of runtime state, for a list nobody
     * asked to see.
     */
    private fun refresh() {
        if (destroyed) return
        if (refreshPending) {
            refreshAgain = true
            return
        }
        refreshPending = true
        val withApps = showApps
        reader.execute {
            val result = runCatching { load(withApps) }
            main.post {
                refreshPending = false
                if (destroyed) return@post
                result
                    .onSuccess { loaded ->
                        // Every completed read ends with the same two facts, whatever else it filled
                        // in: what storage holds, and that storage has now been read at all.
                        val next = loaded.copy(hasStoredSources = loaded.sources.isNotEmpty(), storageRead = true)
                        val scheduleChanged =
                            stored.sources.map { listOf(it.id, it.enabled, it.updatedAtMillis, it.updateIntervalHours) } !=
                                next.sources.map { listOf(it.id, it.enabled, it.updatedAtMillis, it.updateIntervalHours) }
                        stored = next
                        if (scheduleChanged) io.execute { runCatching { SubscriptionRefreshJob.schedule(applicationContext) } }
                    }.onFailure {
                        HydraLog.error(AREA, "the read model could not be assembled", it)
                        notice = Notice.OPERATION_FAILED
                    }
                if (refreshAgain) {
                    refreshAgain = false
                    refresh()
                }
            }
        }
    }

    private fun refreshJournal() {
        if (destroyed || journalPending) return
        journalPending = true
        reader.execute {
            val result =
                runCatching {
                    val revision = store.journalRevision()
                    val local = HydraLog.entries().lastOrNull()
                    if (revision == journalRevision && local == lastLocalLog) {
                        null
                    } else {
                        Triple(revision, local, journal())
                    }
                }
            main.post {
                journalPending = false
                if (destroyed || !started || navigation.route != Route.Journal) return@post
                result
                    .onSuccess { changed ->
                        changed?.let { (revision, local, entries) ->
                            journalRevision = revision
                            lastLocalLog = local
                            stored = stored.copy(diagnostics = stored.diagnostics?.copy(journal = entries))
                        }
                    }.onFailure { notice = Notice.OPERATION_FAILED }
            }
        }
    }

    private fun stopExitProbe() {
        exitRequest++
        cancelExit?.invoke()
        cancelExit = null
        exitWatchdog?.let(main::removeCallbacks)
        exitWatchdog = null
        exit = exit.copy(checking = false)
    }

    private fun probeExit() {
        stopExitProbe()
        exitProbeHidden = false
        if (!started || destroyed || snapshot.state != RuntimeState.RUNNING) return
        val request = exitRequest
        val route = exitRoute(snapshot)
        // The tag of the outbound that actually carries traffic, from the core's own answer —
        // not from the settings, which describe the next tunnel rather than this one.
        val outbound = runningOutboundTag(snapshot) ?: return
        exit = ExitAddress(checking = true)
        val startedAt = System.currentTimeMillis()
        HydraLog.info(AREA, "asking the core for the exit of $outbound (request $request, route $route)")
        val future =
            exitReader.submit {
                val answer =
                    runCatching {
                        val settings = store.settings()
                        if (settings.locationLookupLimit <= 0) {
                            null
                        } // The core dials the endpoint through the named outbound, so the answer is
                        // evidence about the route in every mode: proxy-only, an app split out of the
                        // tunnel, a settings change still waiting for its reconnect.
                        else {
                            transport?.exitAddress(outbound)
                        }
                    }.getOrNull()
                main.post {
                    val dropped =
                        when {
                            destroyed -> "the activity is gone"
                            request != exitRequest -> "a newer probe superseded this one"
                            snapshot.state != RuntimeState.RUNNING -> "the tunnel is no longer running"
                            route != exitRoute(snapshot) -> "the route changed under the question"
                            else -> null
                        }
                    if (dropped != null) {
                        HydraLog.info(AREA, "the exit answer for $outbound was dropped: $dropped")
                        return@post
                    }
                    cancelExit = null
                    exitWatchdog?.let(main::removeCallbacks)
                    exitWatchdog = null
                    HydraLog.info(
                        AREA,
                        "the exit of $outbound is " + (answer?.first ?: "unknown") + " after ${System.currentTimeMillis() - startedAt}ms",
                    )
                    exit =
                        answer?.let { ExitAddress(address = it.first, countryCode = it.second, flag = ExitAddressProbe.flagOf(it.second)) }
                            ?: ExitAddress()
                }
            }
        cancelExit = { future.cancel(true) }
        // The checking state must be possible to leave even if no answer ever crosses: a
        // lost reply used to hold "Проверяю адрес" on the screen forever, indistinguishable
        // from a slow one. Past this deadline the row says it does not know; an answer that
        // arrives after it is still taken.
        val watchdog =
            Runnable {
                if (request == exitRequest && exit.checking && exit.address == null) {
                    HydraLog.warn(AREA, "the exit of $outbound did not answer within $EXIT_PROBE_DEADLINE_MILLIS ms; leaving the check")
                    exit = ExitAddress()
                }
            }
        main.postDelayed(watchdog, EXIT_PROBE_DEADLINE_MILLIS)
        exitWatchdog = watchdog
    }

    private fun load(withApps: Boolean = false): AppReadModel {
        val settings = store.settings()
        return AppReadModel(
            runtime = snapshot,
            sources = store.summaries(),
            servers = store.serverGroups(),
            autoServer = store.autoServer(),
            selectedServerId = store.selectedTag(),
            settings = store.settingsSummary(settings),
            diagnostics = diagnostics(),
            update = updateState,
            apps = if (withApps) store.installedApps() else emptyList(),
            ruleSets =
                store.ruleSetStatus().let { status ->
                    val russia = store.russiaRuleSetStatus()
                    RuleSetsSummary(
                        available = status.available,
                        blockedDomains = status.blockedDomains,
                        updatedAt = status.updatedAtMillis?.let(::readableDate),
                        russiaAvailable = russia.available,
                        russiaNetworks = russia.networks,
                        russiaUpdatedAt = russia.updatedAtMillis?.let(::readableDate),
                    )
                },
            exit = exit,
            legalAccepted = settings.acceptedLegalAtMillis != null,
        )
    }

    /**
     * Support facts and the journal. The generated configuration is deliberately not shown: it
     * carries server addresses and credentials, and this is the screen a person is most likely
     * to screenshot. Runtime phase, transport health, lanes and generations are gone — nobody
     * outside this codebase could act on them, and the journal says the same thing in words.
     */
    private fun diagnostics(): DiagnosticsSummary {
        val settings = store.settings()
        return DiagnosticsSummary(
            level = settings.logLevel.name.lowercase(),
            appVersion = BuildConfig.VERSION_NAME,
            coreVersion = BuildConfig.HYDRACORE_VERSION,
            activeServer = store.selectedTag(),
            dnsResolver = settings.dnsProxyResolver,
            journal = journal(),
        )
    }

    /**
     * The journal as one list: what this process logged, and what the core process wrote into
     * the shared database. Both are kept in arrival order, oldest first, the way 1.x's log page
     * read; consecutive identical lines are folded into one with a count.
     */
    private fun journal(): List<JournalEntry> {
        val local =
            HydraLog.entries().map { entry ->
                entry.atMillis to
                    JournalEntry(
                        id = 0,
                        time = clock(entry.atMillis),
                        level = journalLevel(entry.level.name),
                        source = entry.area,
                        message = entry.message,
                    )
            }
        val remote =
            store.coreEvents().map { event ->
                event.atMillis to
                    JournalEntry(
                        id = 0,
                        time = clock(event.atMillis),
                        level = journalLevel(event.level),
                        source = event.area,
                        message = event.message,
                    )
            }
        val folded = mutableListOf<JournalEntry>()
        (local + remote).sortedBy { it.first }.map { it.second }.forEach { entry ->
            val last = folded.lastOrNull()
            if (last != null && last.level == entry.level && last.source == entry.source && last.message == entry.message) {
                folded[folded.lastIndex] = last.copy(repeats = last.repeats + 1, time = entry.time)
            } else {
                folded += entry
            }
        }
        return folded
            .takeLast(JOURNAL_SHOWN)
            .mapIndexed { index, entry -> entry.copy(id = index.toLong()) }
    }

    private fun clock(atMillis: Long): String =
        if (atMillis <= 0) {
            "--:--:--"
        } else {
            java.time.Instant
                .ofEpochMilli(atMillis)
                .atZone(java.time.ZoneId.systemDefault())
                .format(CLOCK)
        }

    private fun journalLevel(name: String) =
        when (name.lowercase()) {
            "error" -> JournalLevel.ERROR
            "warn" -> JournalLevel.WARN
            "debug" -> JournalLevel.DEBUG
            else -> JournalLevel.INFO
        }

    /** The structural facts, which are true whether or not anything went wrong. */
    private fun facts() =
        listOfNotNull(
            "core ${BuildConfig.HYDRACORE_VERSION}",
            "selected ${store.selectedTag() ?: "auto"}",
            snapshot.lastFailure?.let { "failure ${it.domain.name.lowercase()} / ${it.code.code}" },
            store.startFailure()?.let { "start rejected: $it" },
            store.importFailure()?.let { "import failed: $it" },
            store
                .summaries()
                .mapNotNull { source -> store.parseError(source.id)?.let { "source rejected: $it" } }
                .firstOrNull(),
        )

    private fun actions() =
        AppActions(
            onConnect = ::prepareAndStart,
            onDisconnect = { send(RuntimeCommand.Stop) },
            onOpenLink = ::openLink,
            onRetry = ::prepareAndStart,
            onGrantPermission = ::prepareAndStart,
            onAddSource = { name, source ->
                background(Notice.SOURCE_ADDED) { store.addSubscription(name, source) }
            },
            onRefreshSource = { id -> background(Notice.SOURCE_UPDATED) { store.refreshSubscription(id) } },
            onEditSource = { id, name, link ->
                // The move fetches the new address before it writes anything, so the busy state
                // and the notice are the only feedback a person needs: a link that fails leaves
                // the stored subscription exactly as it was.
                background(Notice.SOURCE_UPDATED) { store.editSubscription(id, name, link) }
            },
            onRemoveSource = { id -> background(Notice.SOURCE_REMOVED) { store.removeSubscription(id) } },
            onRefreshUsage = { id ->
                background(Notice.SOURCE_UPDATED) { store.refreshUsage(id) }
            },
            onSetSourceEnabled = { id, enabled ->
                reconnectAware { store.setSourceEnabled(id, enabled) }
            },
            onSelectServer = { id ->
                background {
                    // Choosing a server while the tunnel is up switches it in place: nobody should
                    // have to disconnect and reconnect to change where they are going. The one
                    // exception is the VK boundary — the service restarts the core there, because
                    // the configuration itself is different on each side of it — and that switch
                    // says so instead of pretending it cost nothing.
                    val crossing = store.selectedIsCallTransport() != store.isCallTransport(id)
                    store.select(id)
                    if (snapshot.state == RuntimeState.RUNNING) {
                        main.post { send(RuntimeCommand.SelectOutbound(SELECT_GROUP, id)) }
                        if (crossing) Notice.SERVER_SWITCH_RESTARTED else Notice.SERVER_SWITCHED
                    } else if (snapshot.state == RuntimeState.FAILED) {
                        // A failed tunnel offers one action on the home screen — choose another
                        // server — and nothing left to press afterwards: the choice was stored and
                        // the screen stayed in that dead end until the application was restarted.
                        // Choosing is the instruction to use this server, so it also starts.
                        main.post { prepareAndStart() }
                        null
                    } else {
                        null
                    }
                }
            },
            onMeasure = { startService(measureIntent()) },
            onAcceptLegal = {
                background(null) {
                    store.saveSettings(
                        store.settings().copy(
                            acceptedLegalVersion = LEGAL_VERSION,
                            acceptedLegalAtMillis = System.currentTimeMillis(),
                        ),
                    )
                }
            },
            onSetEconomy = { economy ->
                reconnectAware {
                    store.saveSettings(
                        store.settings().copy(
                            performanceMode = if (economy) PerformanceMode.ECONOMY else PerformanceMode.STANDARD,
                        ),
                    )
                }
            },
            onSetNotificationDetail = { detail ->
                background(null) {
                    store.saveSettings(
                        store.settings().copy(
                            statusNotificationEnabled = detail != NotificationDetail.OFF,
                            notificationTrafficDisplayMode =
                                when (detail) {
                                    NotificationDetail.TOTAL -> NotificationTrafficDisplayMode.TOTAL

                                    NotificationDetail.BOTH -> NotificationTrafficDisplayMode.BOTH

                                    // Off keeps whatever was chosen, so turning the line back on does
                                    // not silently pick a different one.
                                    NotificationDetail.OFF -> store.settings().notificationTrafficDisplayMode

                                    NotificationDetail.SPEED -> NotificationTrafficDisplayMode.SPEED
                                },
                        ),
                    )
                    main.post {
                        if (!destroyed && snapshot.state == RuntimeState.RUNNING) {
                            runCatching {
                                startService(
                                    Intent(this@RuntimeControlActivity, HydraVpnService::class.java)
                                        .setAction(HydraVpnService.ACTION_REFRESH_SETTINGS),
                                )
                            }.onFailure { notice = Notice.OPERATION_FAILED }
                        }
                    }
                }
            },
            onSetBlockLeaks = { enabled -> reconnectAware { store.saveSettings(store.settings().copy(blockLeaks = enabled)) } },
            onSetBypassLocalNetwork = { enabled ->
                reconnectAware { store.saveSettings(store.settings().copy(bypassLocalNetwork = enabled)) }
            },
            onSetAppsMode = { mode ->
                reconnectAware {
                    store.saveSettings(
                        store.settings().copy(
                            splitRoutingMode =
                                when (mode) {
                                    AppsMode.OFF -> SplitRoutingMode.OFF
                                    AppsMode.BYPASS_SELECTED -> SplitRoutingMode.BYPASS_SELECTED
                                    AppsMode.ONLY_SELECTED -> SplitRoutingMode.ONLY_SELECTED
                                },
                        ),
                    )
                }
            },
            onSetAdBlock = { enabled ->
                reconnectAware { store.saveSettings(store.settings().copy(adBlockEnabled = enabled)) }
            },
            onUpdateRuleSets = {
                // The list is a few megabytes and is compiled on the device, so it runs on the io
                // thread with its own busy state rather than the shared one.
                updatingRules = true
                io.execute {
                    val failure = runCatching { store.updateRuleSets() }.exceptionOrNull()
                    main.post {
                        updatingRules = false
                        notice = if (failure == null) Notice.RULES_UPDATED else Notice.RULES_FAILED
                        refresh()
                    }
                }
            },
            onSetRouteRussiaDirect = { enabled ->
                reconnectAware { store.saveSettings(store.settings().copy(routeRussiaDirectEnabled = enabled)) }
            },
            onUpdateRussiaRuleSets = {
                // Same contract as the ad-block list: a few MB fetched and compiled on the io
                // thread, with its own busy row rather than the shared one.
                updatingRussiaRules = true
                io.execute {
                    val failure = runCatching { store.updateRussiaRuleSets() }.exceptionOrNull()
                    main.post {
                        updatingRussiaRules = false
                        notice = if (failure == null) Notice.RULES_UPDATED else Notice.RULES_FAILED
                        refresh()
                    }
                }
            },
            onSetTcpFastOpen = { enabled ->
                reconnectAware { store.saveSettings(store.settings().copy(tcpFastOpen = enabled)) }
            },
            onSetTcpMultiPath = { enabled ->
                reconnectAware { store.saveSettings(store.settings().copy(tcpMultiPath = enabled)) }
            },
            onSetProxyOnly = { proxyOnly ->
                reconnectAware {
                    store.saveSettings(
                        store.settings().copy(
                            proxyInboundEnabled = proxyOnly,
                            vpnInboundEnabled = !proxyOnly,
                        ),
                    )
                }
            },
            onSetProxyPort = { port -> applyProxyPort(port) },
            onSetProxyAllowLan = { allow ->
                reconnectAware { store.saveSettings(store.settings().copy(proxyAllowLan = allow)) }
            },
            onSetStrictRoute = { enabled -> reconnectAware { store.saveSettings(store.settings().copy(vpnStrictRoute = enabled)) } },
            onSetStack = { stack ->
                reconnectAware {
                    store.saveSettings(
                        store.settings().copy(
                            vpnTunStack =
                                when (stack) {
                                    TunnelStack.SYSTEM -> TunStack.SYSTEM
                                    TunnelStack.GVISOR -> TunStack.GVISOR
                                    TunnelStack.MIXED -> TunStack.MIXED
                                },
                        ),
                    )
                }
            },
            onSetFragmentation = { mode ->
                reconnectAware {
                    store.saveSettings(
                        store.settings().copy(
                            tlsFragmentationMode =
                                when (mode) {
                                    TlsFragmentation.OFF -> TlsFragmentationMode.DISABLED
                                    TlsFragmentation.RECORD -> TlsFragmentationMode.RECORD
                                    TlsFragmentation.FRAGMENT -> TlsFragmentationMode.FRAGMENT
                                },
                        ),
                    )
                }
            },
            // Not `reconnectAware` any more: the core takes a new level on the running instance, so
            // the promise of a reconnect would be a lie and the reconnect would end the fault someone
            // turned the detail up to look at.
            onSetLogDetail = { detail ->
                background(null) {
                    store.saveSettings(
                        store.settings().copy(
                            logLevel =
                                when (detail) {
                                    LogDetail.OFF -> LogLevel.OFF
                                    LogDetail.TRACE -> LogLevel.TRACE
                                    LogDetail.DEBUG -> LogLevel.DEBUG
                                    LogDetail.INFO -> LogLevel.INFO
                                    LogDetail.WARN -> LogLevel.WARN
                                    LogDetail.ERROR -> LogLevel.ERROR
                                },
                        ),
                    )
                    if (snapshot.state != RuntimeState.STOPPED) {
                        main.post {
                            runCatching {
                                startService(
                                    Intent(this@RuntimeControlActivity, HydraVpnService::class.java)
                                        .setAction(HydraVpnService.ACTION_LOG_LEVEL),
                                )
                            }
                        }
                    }
                }
            },
            // A new listener is a new configuration rather than a running-instance knob: the core
            // reads `debug.listen` when it starts, so this one really does need the tunnel rebuilt.
            onSetPprof = { enabled ->
                reconnectAware { store.saveSettings(store.settings().copy(pprofEnabled = enabled)) }
            },
            onSetUpdateChannel = { channel ->
                background(null) {
                    store.saveSettings(
                        store.settings().copy(
                            updateChannel =
                                when (channel) {
                                    UpdateChannel.STABLE -> SettingsUpdateChannel.STABLE
                                    UpdateChannel.CANARY -> SettingsUpdateChannel.CANARY
                                },
                        ),
                    )
                }
                // A channel change makes the last answer meaningless: it was about the other line.
                updateState = UpdateSummary()
                pendingUpdate = null
            },
            onCheckUpdate = {
                val channel =
                    store
                        .settings()
                        .updateChannel.name
                        .lowercase()
                updateState = UpdateSummary(checking = true)
                pendingUpdate = null
                // The screen reads the update state out of the read model, so the model has to be
                // rebuilt for anything to appear at all. Assigning the field alone left the row
                // unchanged, which made a running check look like a button that does nothing.
                refresh()
                io.execute {
                    val result = runCatching { UpdateClient.check(channel) }.getOrElse { UpdateCheck.Unreachable }
                    // A check is not a fetch. The verified release is reported, and what is asked
                    // here is only what is already on the device: a file fetched in an earlier
                    // visit can be installed at once, and one that is not here waits for its own
                    // press. Downloading on the check's own initiative took the choice away.
                    val offered = (result as? UpdateCheck.Decided)?.decision as? UpdateDecision.Available
                    val state =
                        offered?.let { decision ->
                            UpdateClient.apkState(this@RuntimeControlActivity, decision.manifest)
                        }
                    main.post {
                        when (result) {
                            UpdateCheck.Unreachable -> {
                                updateState = UpdateSummary(reachable = false)
                            }

                            is UpdateCheck.Decided -> {
                                when (val decision = result.decision) {
                                    is UpdateDecision.Available -> {
                                        pendingUpdate = decision.manifest
                                        updateState =
                                            UpdateSummary(
                                                availableVersion = decision.manifest.versionName,
                                                checked = true,
                                                downloading = state is ApkState.Downloading,
                                                ready = state is ApkState.Ready,
                                            )
                                    }

                                    UpdateDecision.NoUpdate -> {
                                        updateState = UpdateSummary(checked = true)
                                    }

                                    is UpdateDecision.Refused -> {
                                        updateState = UpdateSummary(fault = decision.fault)
                                    }
                                }
                            }
                        }
                        refresh()
                    }
                }
            },
            onDownloadUpdate = {
                val manifest = pendingUpdate ?: return@AppActions
                updateState = updateState.copy(downloading = true, installFault = null)
                // The same read model as the check: nothing reaches the screen until it is rebuilt.
                refresh()
                io.execute {
                    val started = UpdateClient.startDownload(this@RuntimeControlActivity, manifest) != null
                    main.post {
                        // The shade carries the progress from here; the row says so and waits.
                        // A download that could not start leaves the offer standing, so it can
                        // be asked for again instead of disappearing.
                        updateState =
                            updateState.copy(
                                downloading = started,
                                availableVersion = manifest.versionName,
                            )
                        refresh()
                    }
                }
            },
            onInstallUpdate = {
                val manifest = pendingUpdate ?: return@AppActions
                updateState = updateState.copy(installing = true, installFault = null)
                // The same read model as the check: nothing reaches the screen until it is rebuilt.
                refresh()
                io.execute {
                    // The two steps the shade takes, in the same order: read the downloaded file
                    // back and check it against the signed document, then let the installer see it.
                    // Android enforces the signature when it installs the APK; the digest is what
                    // says these are the bytes this channel promised.
                    val id = (UpdateClient.apkState(this@RuntimeControlActivity, manifest) as? ApkState.Ready)?.downloadId
                    val fault =
                        when (id) {
                            null -> InstallFault.UNREACHABLE
                            else -> UpdateClient.verify(this@RuntimeControlActivity, manifest, id)
                        }
                    val intent =
                        if (fault == null && id != null) {
                            UpdateClient.installIntent(this@RuntimeControlActivity, id)
                        } else {
                            null
                        }
                    main.post {
                        if (intent == null) {
                            updateState =
                                UpdateSummary(
                                    availableVersion = manifest.versionName,
                                    installFault = fault ?: InstallFault.NO_INSTALLER,
                                )
                        } else {
                            updateState = UpdateSummary(availableVersion = manifest.versionName, installing = true)
                            runCatching { startActivity(intent) }
                                .onFailure { HydraLog.warn("update", "the installer could not be opened", it) }
                        }
                        refresh()
                    }
                }
            },
            onSetAppearance = { appearance ->
                background(null) {
                    store.saveSettings(
                        store.settings().copy(
                            themeMode =
                                when (appearance) {
                                    Appearance.SYSTEM -> ThemeMode.SYSTEM
                                    Appearance.LIGHT -> ThemeMode.LIGHT
                                    Appearance.DARK -> ThemeMode.DARK
                                },
                        ),
                    )
                }
            },
            onSetLanguage = ::applyLanguage,
            onSetProxyDns = { value -> reconnectAware { store.saveSettings(store.settings().copy(dnsProxyResolver = value)) } },
            onSetDirectDns = { value -> reconnectAware { store.saveSettings(store.settings().copy(dnsDirectResolver = value)) } },
            onSetBootstrapDns = { value ->
                reconnectAware { store.saveSettings(store.settings().copy(bootstrapDnsResolver = value)) }
            },
            onSetDnsMode = { mode ->
                reconnectAware {
                    store.saveSettings(
                        store.settings().copy(
                            dnsStrategy =
                                when (mode) {
                                    DnsMode.AUTO -> DnsStrategy.AUTO
                                    DnsMode.IPV4 -> DnsStrategy.IPV4_ONLY
                                    DnsMode.IPV6 -> DnsStrategy.IPV6_ONLY
                                },
                        ),
                    )
                }
            },
            onSetFakeIp = { enabled ->
                reconnectAware { store.saveSettings(store.settings().copy(fakeIpEnabled = enabled)) }
            },
            onSetInterruptConnections = { enabled ->
                reconnectAware { store.saveSettings(store.settings().copy(interruptExistingConnections = enabled)) }
            },
            onSetMtu = { mtu -> reconnectAware { store.saveSettings(store.settings().copy(vpnMtu = mtu)) } },
            onClearJournal = {
                HydraLog.clear()
                background(null) { store.clearCoreEvents() }
            },
            onToggleApp = { packageName -> reconnectAware { store.toggleExcludedApp(packageName) } },
            onLoadApps = {
                showApps = true
                refresh()
            },
            onRefreshExit = ::probeExit,
            onExportDiagnostics = ::shareDiagnostics,
            onExportBackup = { passphrase ->
                pendingPassphrase = passphrase.toCharArray()
                runCatching { exportFile.launch(BACKUP_FILE_NAME) }.onFailure { failBackup() }
            },
            onImportBackup = { passphrase ->
                pendingPassphrase = passphrase.toCharArray()
                runCatching { importFile.launch(arrayOf("*/*")) }.onFailure { failBackup() }
            },
            onResetSettings = { background(Notice.SETTINGS_RESET) { store.resetSettings() } },
            onNoticeShown = { notice = null },
        )

    /**
     * The language is the system's business: Android 13 keeps a per-app locale, shows it in
     * its own settings and survives reinstalls of the app's preferences. Storing our own
     * copy as well keeps the chosen value visible in the interface.
     */
    private fun applyLanguage(language: Language) {
        val stored =
            when (language) {
                Language.SYSTEM -> AppLanguage.SYSTEM
                Language.RUSSIAN -> AppLanguage.RUSSIAN
                Language.ENGLISH -> AppLanguage.ENGLISH
            }
        background(null) { store.saveSettings(store.settings().copy(language = stored)) }
        if (android.os.Build.VERSION.SDK_INT < android.os.Build.VERSION_CODES.TIRAMISU) return
        val tags =
            when (language) {
                Language.SYSTEM -> ""
                Language.RUSSIAN -> "ru"
                Language.ENGLISH -> "en"
            }
        runCatching {
            getSystemService(android.app.LocaleManager::class.java)
                ?.applicationLocales = android.os.LocaleList.forLanguageTags(tags)
        }
    }

    private fun readableDate(millis: Long): String =
        java.time.Instant
            .ofEpochMilli(millis)
            .toString()
            .substringBefore('T')

    /** A setting that only the next tunnel will read says so instead of pretending to apply. */
    private fun reconnectAware(block: () -> Unit) =
        background(
            if (snapshot.state == RuntimeState.RUNNING) Notice.SETTINGS_NEED_RECONNECT else null,
            block,
        )

    /**
     * The local proxy port, applied where it is actually bound.
     *
     * A listener is created once, while the core is being started, so storing another number
     * left the proxy answering on the old port — still open, still reachable — while the screens
     * showed the new one. It is the one setting whose stale value is a surface rather than a
     * behaviour, and a transient "applies next time you connect" is not what someone reading a
     * port number is looking for.
     *
     * The port is tried before it is stored. A port already taken is the failure that matters
     * here, and on that one both the stored value and the running proxy stay as they were, which
     * is what the screen then keeps showing. When it is free and the proxy is running, the core
     * is started again — the old listener closes with it — through the reducer's own restart
     * idiom, and the start reads the port from the value just stored.
     */
    private fun applyProxyPort(port: Int) {
        background {
            val settings = store.settings()
            val running = snapshot.state == RuntimeState.RUNNING && store.proxyOnly()
            when {
                // The running listener owns its current port, so a no-op must not test it as an
                // external conflict or restart a healthy proxy.
                running && port == settings.proxyMixedPort -> {
                    null
                }

                running && !proxyPortIsFree(port) -> {
                    Notice.PROXY_PORT_TAKEN
                }

                running -> {
                    store.saveSettings(settings.copy(proxyMixedPort = port))
                    restartCore()
                    Notice.SETTINGS_APPLIED
                }

                else -> {
                    store.saveSettings(settings.copy(proxyMixedPort = port))
                    null
                }
            }
        }
    }

    /**
     * Whether this process can bind where the proxy would listen. The core binds it in its own
     * process, so this is the same question asked one step early rather than a guarantee — but
     * the conflict it catches is exactly the one a person creates by typing a number that
     * something else is already using.
     */
    private fun proxyPortIsFree(port: Int): Boolean {
        val address = if (store.settings().proxyAllowLan) "0.0.0.0" else "127.0.0.1"
        return runCatching {
            java.net.ServerSocket().use { socket ->
                socket.reuseAddress = false
                socket.bind(java.net.InetSocketAddress(address, port))
            }
        }.isSuccess
    }

    /**
     * Starts the core again under the settings that are stored now.
     *
     * A stop followed by a start is the reducer's own restart idiom: a start received while the
     * runtime is stopping is deferred and applied once the core has confirmed its release. The
     * core cannot reload in place — it closes the old instance before the new one exists — so a
     * restart is the honest way to change what the configuration contains.
     */
    private fun restartCore() {
        send(RuntimeCommand.Stop)
        send(RuntimeCommand.Start(if (store.proxyOnly()) RuntimeMode.PROXY else RuntimeMode.VPN))
    }

    private fun background(
        success: Notice?,
        block: () -> Unit,
    ) = background {
        block()
        success
    }

    /**
     * The block decides its own notice, because what to say can depend on what it found — the
     * switch that restarts the core has to say so, and only the store knows which one that is.
     */
    private fun background(block: () -> Notice?) {
        busy = OperationState.Running
        notice = null
        io.execute {
            val result = runCatching(block)
            val failure = result.exceptionOrNull()
            runCatching { store.rememberImportFailure(failure) }
            main.post {
                busy = failure?.let { OperationState.Failed(OperationError(it.message ?: "failed")) }
                    ?: OperationState.Idle
                notice = if (failure != null) noticeOf(failure) else result.getOrNull()
                refresh()
            }
        }
    }

    /**
     * A typed failure becomes the sentence that matches it. 1.x distinguished seventeen
     * reasons a source could not be read, and told the person which one it was; a single
     * "something went wrong" for all of them is what this avoids.
     */
    private fun noticeOf(failure: Throwable): Notice =
        when ((failure as? SubscriptionException)?.failure) {
            SourceFailure.TIMEOUT, SourceFailure.NO_NETWORK, SourceFailure.TLS -> Notice.SOURCE_UNREACHABLE
            SourceFailure.HTTP_STATUS, SourceFailure.TOO_MANY_REDIRECTS -> Notice.SOURCE_REJECTED
            SourceFailure.HTML_RESPONSE -> Notice.SOURCE_NOT_A_SUBSCRIPTION
            SourceFailure.CREDENTIALS_REQUIRE_HTTPS -> Notice.SOURCE_INSECURE_LINK
            SourceFailure.UNSAFE_REDIRECT -> Notice.SOURCE_UNSAFE_REDIRECT
            SourceFailure.ENCRYPTED_WITHOUT_KEY -> Notice.SOURCE_NEEDS_KEY
            SourceFailure.CORE_TOO_OLD -> Notice.SOURCE_NEEDS_NEWER_APP
            SourceFailure.TOO_LARGE -> Notice.SOURCE_TOO_LARGE
            SourceFailure.EMPTY_RESPONSE, SourceFailure.NO_USABLE_SERVERS -> Notice.SOURCE_EMPTY
            SourceFailure.EXPIRED -> Notice.SOURCE_FAILED
            SourceFailure.INVALID_URL, SourceFailure.INVALID_CONTENT, SourceFailure.UNKNOWN -> Notice.SOURCE_FAILED
            null -> Notice.OPERATION_FAILED
        }

    private fun prepareAndStart() {
        busy = OperationState.Running
        io.execute {
            val ready = runCatching { store.generateConfig() != null }.getOrDefault(false)
            main.post {
                busy = OperationState.Idle
                if (!ready) {
                    notice = Notice.SOURCE_EMPTY
                    return@post
                }
                notice = null
                // The system consent is about a tunnel. A local proxy port does not need
                // one, so proxy-only starts without asking for it.
                if (store.proxyOnly()) launch() else VpnService.prepare(this)?.let(permission::launch) ?: launch()
            }
        }
    }

    private fun launch() {
        notice = null
        permissionMissing = false
        startForegroundService(Intent(this, HydraVpnService::class.java).setAction(HydraVpnService.ACTION_START))
        // The bind at resume may have found no service to connect to, or it may still belong to
        // the service that just stopped. A dead binding without BIND_AUTO_CREATE is not reconnected
        // when this start creates a new service, so replace it before waiting for the new snapshot.
        if (transport == null) unbind()
        // Starting is asynchronous; this is the one bind that may create a service, because its
        // matching foreground start has already established started-service ownership.
        bind(createIfMissing = true)
    }

    private fun measureIntent() = Intent(this, HydraVpnService::class.java).setAction(HydraVpnService.ACTION_MEASURE)

    /**
     * The log leaves the app as text through the system share sheet: no file provider, no
     * storage permission, and the person sees exactly what is being sent before sending it.
     */
    private fun shareDiagnostics() {
        // The same lines the journal shows, in the same order, so a report and a screenshot
        // never disagree about what happened.
        val body =
            (facts() + journal().map { entry -> "${entry.time} ${entry.level.name.lowercase()} ${entry.source}: ${entry.message}" })
                .joinToString(separator = System.lineSeparator())
        val send =
            Intent(Intent.ACTION_SEND)
                .setType("text/plain")
                .putExtra(Intent.EXTRA_SUBJECT, "HydraBox diagnostics")
                .putExtra(Intent.EXTRA_TEXT, body)
        runCatching { startActivity(Intent.createChooser(send, null)) }
            .onFailure { notice = Notice.OPERATION_FAILED }
    }

    /**
     * The document is built and encrypted on the io thread: deriving the key from the
     * passphrase is deliberately slow, and doing it on the main thread would freeze the
     * screen for as long as it takes.
     */
    private fun writeBackup(uri: android.net.Uri?) {
        val passphrase = pendingPassphrase
        pendingPassphrase = null
        if (uri == null || passphrase == null) return failBackup(silent = uri == null)
        busy = OperationState.Running
        io.execute {
            val failure =
                runCatching {
                    val bytes = BackupFile.encrypt(store.exportDocument(), passphrase)
                    contentResolver.openOutputStream(uri)?.use { it.write(bytes) } ?: error("no_output_stream")
                }.exceptionOrNull()
            passphrase.fill(BLANK)
            main.post {
                busy = OperationState.Idle
                notice = if (failure == null) Notice.BACKUP_EXPORTED else Notice.BACKUP_FAILED
            }
        }
    }

    private fun readBackup(uri: android.net.Uri?) {
        val passphrase = pendingPassphrase
        pendingPassphrase = null
        if (uri == null || passphrase == null) return failBackup(silent = uri == null)
        busy = OperationState.Running
        io.execute {
            val failure =
                runCatching {
                    val bytes = readLimited(uri, MAX_BACKUP_BYTES)
                    store.importDocument(BackupFile.decrypt(bytes, passphrase))
                }.exceptionOrNull()
            passphrase.fill(BLANK)
            main.post {
                busy = OperationState.Idle
                notice = if (failure == null) Notice.BACKUP_IMPORTED else Notice.BACKUP_FAILED
                refresh()
            }
        }
    }

    /**
     * A chosen file, up to a limit, read without asking for the whole of it first.
     *
     * `readBytes` on a document picker's stream allocates whatever the other side hands over, and
     * the other side is any application on the device: a several-gigabyte file chosen by accident
     * was an out-of-memory kill rather than a refusal a person could read.
     */
    private fun readLimited(
        uri: android.net.Uri,
        limit: Int,
    ): ByteArray {
        val stream = contentResolver.openInputStream(uri) ?: error("no_input_stream")
        return stream.use { input ->
            val buffer = java.io.ByteArrayOutputStream()
            val chunk = ByteArray(64 * 1024)
            while (true) {
                val read = input.read(chunk)
                if (read <= 0) break
                check(buffer.size() + read <= limit) { "file_too_large" }
                buffer.write(chunk, 0, read)
            }
            check(buffer.size() > 0) { "file_empty" }
            buffer.toByteArray()
        }
    }

    /** A cancelled picker is not a failure; a missing passphrase is. */
    private fun failBackup(silent: Boolean = false) {
        pendingPassphrase = null
        if (!silent) notice = Notice.BACKUP_FAILED
    }

    /**
     * An address that leaves the app — the projects this build comes from. A phone with nothing
     * to open it says so, rather than looking like the press did nothing at all.
     */
    private fun openLink(url: String) {
        val intent =
            Intent(Intent.ACTION_VIEW, Uri.parse(url))
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        runCatching { startActivity(intent) }.onFailure { notice = Notice.OPERATION_FAILED }
    }

    private fun send(command: RuntimeCommand) {
        val bound = transport
        if (bound == null) {
            notice = Notice.OPERATION_FAILED
            return
        }
        runCatching { bound.submit(command) }.exceptionOrNull()?.let { notice = Notice.OPERATION_FAILED }
    }

    private fun stoppedSnapshot() =
        RuntimeSnapshot(
            processEpoch = ProcessEpoch("ui"),
            commandGeneration = CommandGeneration(0),
            runtimeGeneration = RuntimeGeneration(0),
            networkGeneration = NetworkGeneration(0),
            lastEventSequence = EventSequence(0),
            state = RuntimeState.STOPPED,
            mode = RuntimeMode.VPN,
        )

    companion object {
        private const val AREA = "ui"

        /**
         * Whether the screens are in front of the person. The core process cannot see the
         * activity's lifecycle, and it needs it to decide between drawing a question and
         * posting a notification about it.
         */
        @Volatile var visible = false

        /**
         * Past this the checking state is left, whatever became of the answer: the service
         * side bounds its own reply at eight seconds, and this is the client's own guarantee
         * that a lost reply cannot hold the row in "Проверяю адрес" forever.
         */
        private const val EXIT_PROBE_DEADLINE_MILLIS = 12_000L

        /** How much of each journal the screen shows before it stops being readable. */

        /** As many lines as a person will actually scroll, newest last. */
        private const val JOURNAL_SHOWN = 300
        private val CLOCK =
            java.time.format.DateTimeFormatter
                .ofPattern("HH:mm:ss")

        /** Sent by the Quick Settings tile, which cannot show the VPN consent dialog. */
        const val ACTION_REQUEST_START = "io.hydrabox.platform.android.REQUEST_START"

        /** The selector group in the generated configuration. */
        private const val SELECT_GROUP = "select"
        private const val LEGAL_VERSION = "1"
        private const val BACKUP_FILE_NAME = "hydrabox-backup.hbk"

        /** Wiping a passphrase array means overwriting it, not dropping the reference. */
        private const val BLANK = '\u0000'

        /**
         * How large a chosen file may be: a backup carries the documents and the settings,
         * which is not measured in gigabytes, and the picker's stream belongs to whichever
         * application answered it.
         */
        private const val MAX_BACKUP_BYTES = 32 * 1024 * 1024
    }
}
