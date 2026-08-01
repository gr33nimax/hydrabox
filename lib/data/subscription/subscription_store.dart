import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:hive_ce/hive.dart';
import 'package:meow_client/core/lowest_proxy_groups.dart';
import 'package:meow_client/data/local/hive_storage_diagnostics.dart';
import 'package:meow_client/data/local/secure_hive_storage.dart';
import 'package:meow_client/logging/app_log_store.dart';
import 'package:meow_client/models/subscription.dart';

import 'location_aliases.dart';
import 'hydrabox_subscription_crypto.dart';
import 'hydrabox_subscription_time.dart';
import 'outbound_schema.dart';
import 'parsers/hydrabox_subscription_parser.dart';
import 'subscription_failure.dart';
import 'subscription_fetcher.dart';
import 'subscription_parser.dart';
import 'subscription_storage_id.dart';

class SubscriptionImportResult {
  const SubscriptionImportResult({required this.subscription, this.warning});

  final Subscription subscription;
  final Object? warning;

  bool get hasWarning => warning != null;
}

/// Hive-based persistent store for subscriptions.
///
/// Subscription metadata and heavy payload are stored separately so list UIs
/// can load fast without decoding large outbound collections.
class SubscriptionStore {
  static const _lagomWhitelistDetourTag = 'whitelist';
  static const _lagomWhitelistProxySourceTag = 'proxy-whitelist';
  static const _defaultRemoteOperationTimeout = Duration(seconds: 30);

  SubscriptionStore._();

  static const _metaBoxName = 'subscriptions_secure_v1';
  static const _payloadBoxName = 'subscription_payloads_secure_v1';
  static const _legacyMetaBoxName = 'subscriptions';
  static const _legacyPayloadBoxName = 'subscription_payloads';
  static const _legacySummaryBoxName = 'subscription_summaries';
  static const _storageSchemaVersionKey = subscriptionStorageSchemaVersionKey;
  static const _storageSchemaVersion = 2;
  static const _localFileImportScheme = 'meow-file';
  static const _payloadGenerationSeparator =
      subscriptionPayloadGenerationSeparator;
  static Box? _metaBox;
  static Box? _payloadBox;
  static bool _initialized = false;
  static Future<void>? _initialization;
  static final Map<String, Future<void>> _subscriptionWriteLocks =
      <String, Future<void>>{};
  static final Queue<_StoreMutationWaiter> _storeMutationWaiters =
      Queue<_StoreMutationWaiter>();
  static int _activeStoreMutations = 0;
  static bool _exclusiveStoreMutationActive = false;
  static Future<void> _hydraTrustWriteLock = Future<void>.value();
  static final Map<String, Future<Subscription>> _refreshesInFlight =
      <String, Future<Subscription>>{};

  // ─────────────────── Lifecycle ───────────────────

  /// Opens the Hive box. Must be called before any other method.
  static Future<void> init() {
    if (_initialized) {
      return Future<void>.value();
    }
    final inFlight = _initialization;
    if (inFlight != null) {
      return inFlight;
    }
    late final Future<void> tracked;
    tracked = _initialize().whenComplete(() {
      if (identical(_initialization, tracked)) {
        _initialization = null;
      }
    });
    _initialization = tracked;
    return tracked;
  }

  static Future<void> _initialize() async {
    final totalStopwatch = Stopwatch()..start();
    Box? metaBox;
    Box? payloadBox;
    var openedMetaBox = false;
    var openedPayloadBox = false;
    try {
      await SecureHiveStorage.init();
      final metaStopwatch = Stopwatch()..start();
      if (Hive.isBoxOpen(_metaBoxName)) {
        metaBox = Hive.box(_metaBoxName);
      } else {
        metaBox = await Hive.openBox(
          _metaBoxName,
          encryptionCipher: SecureHiveStorage.cipher,
        );
        openedMetaBox = true;
      }
      metaStopwatch.stop();
      final payloadStopwatch = Stopwatch()..start();
      if (Hive.isBoxOpen(_payloadBoxName)) {
        payloadBox = Hive.box(_payloadBoxName);
      } else {
        payloadBox = await Hive.openBox(
          _payloadBoxName,
          encryptionCipher: SecureHiveStorage.cipher,
        );
        openedPayloadBox = true;
      }
      payloadStopwatch.stop();
      // Publish both handles together. Concurrent callers cannot observe this
      // intermediate state because they await the same initialization future.
      _metaBox = metaBox;
      _payloadBox = payloadBox;
      await _runStorageMigrations();
      _assertStoredSourcePolicies();
      await _reconcileStoredHydraBoxTrustTuples();
      await Future.wait<void>([
        HiveStorageDiagnostics.logBoxOnce(
          label: _metaBoxName,
          box: _metaBox!,
          openElapsed: metaStopwatch.elapsed,
        ),
        HiveStorageDiagnostics.logBoxOnce(
          label: _payloadBoxName,
          box: _payloadBox!,
          openElapsed: payloadStopwatch.elapsed,
        ),
      ]);
      totalStopwatch.stop();
      AppLogStore.info(
        'storage metrics',
        'subscriptionStorageReadyMs=${totalStopwatch.elapsedMilliseconds}',
      );
      _initialized = true;
    } catch (error, stackTrace) {
      // Never leave a half-initialized store looking ready. Close only boxes
      // opened by this attempt; an already-open Hive box may be owned by a
      // caller or test fixture and must remain untouched.
      _initialized = false;
      _metaBox = null;
      _payloadBox = null;
      if (openedPayloadBox && payloadBox?.isOpen == true) {
        try {
          await payloadBox!.close();
        } catch (_) {
          // Preserve the original initialization failure.
        }
      }
      if (openedMetaBox && metaBox?.isOpen == true) {
        try {
          await metaBox!.close();
        } catch (_) {
          // Preserve the original initialization failure.
        }
      }
      AppLogStore.error(
        'subscription storage',
        'Failed to initialize Hive subscription boxes: '
            '$error\n$stackTrace',
      );
      rethrow;
    }
  }

  static Future<void> _runStorageMigrations() async {
    final storedVersion =
        (_metaStore.get(_storageSchemaVersionKey) as num?)?.toInt() ?? 0;
    if (storedVersion > _storageSchemaVersion) {
      throw UnsupportedError(
        'Subscription storage schema $storedVersion is newer than supported '
        'schema $_storageSchemaVersion',
      );
    }
    if (storedVersion == _storageSchemaVersion) {
      return;
    }
    await _migratePlaintextBox(_legacyMetaBoxName, _metaStore);
    await _migratePlaintextBox(_legacyPayloadBoxName, _payloadStore);
    await _migrateLegacyData();
    // Do not rewrite or compact every legacy payload during app startup.
    // Readers accept both formats and each payload is compressed the next time
    // that subscription is saved or refreshed. A bulk rewrite here can keep
    // the bootstrap screen visible for close to a minute on large profiles.
    await _cleanupLegacySummaryBox();
    await _metaStore.put(_storageSchemaVersionKey, _storageSchemaVersion);
    await _metaStore.flush();
  }

  static Future<void> _migratePlaintextBox(
    String legacyName,
    Box secureBox,
  ) async {
    if (!await Hive.boxExists(legacyName)) return;

    final legacyBox = Hive.isBoxOpen(legacyName)
        ? Hive.box(legacyName)
        : await Hive.openBox(legacyName);
    try {
      if (legacyBox.isNotEmpty) {
        final legacyValues = Map<dynamic, dynamic>.from(legacyBox.toMap());
        if (legacyName == _legacyMetaBoxName) {
          for (final value in legacyValues.values) {
            if (value is! String) continue;
            try {
              final map = jsonDecode(value) as Map<String, dynamic>;
              final url = map['url']?.toString() ?? '';
              if (_subscriptionUrlHasHydraBoxKeyQuery(url)) {
                throw UnsupportedError(
                  'Stored HydraBox hbx-key must not appear in a URL query',
                );
              }
              if (!Platform.isAndroid && _subscriptionUrlHasHydraBoxKey(url)) {
                throw UnsupportedError(
                  'Persistent hbx-key subscriptions require Android '
                  'Keystore-backed storage',
                );
              }
            } on UnsupportedError {
              rethrow;
            } catch (_) {
              // Existing corrupt metadata is handled by the normal reader.
            }
          }
        }
        final missingValues = <dynamic, dynamic>{
          for (final entry in legacyValues.entries)
            if (!secureBox.containsKey(entry.key)) entry.key: entry.value,
        };
        if (missingValues.isNotEmpty) {
          await secureBox.putAll(missingValues);
          await secureBox.flush();
        }
        if (legacyValues.keys.any((key) => !secureBox.containsKey(key))) {
          throw StateError('Encrypted subscription migration was incomplete.');
        }
      }
    } finally {
      await legacyBox.close();
    }

    // Keep plaintext until the authenticated encrypted copy is durable.
    await Hive.deleteBoxFromDisk(legacyName);
  }

  static Box get _metaStore {
    assert(_metaBox != null, 'SubscriptionStore.init() must be called first');
    return _metaBox!;
  }

  static Box get _payloadStore {
    assert(
      _payloadBox != null,
      'SubscriptionStore.init() must be called first',
    );
    return _payloadBox!;
  }

  static Future<T> _withSubscriptionWriteLock<T>(
    String id,
    Future<T> Function() action,
  ) async {
    validateSubscriptionStorageId(id);
    final previous = _subscriptionWriteLocks[id] ?? Future<void>.value();
    late final Future<T> next;
    late final Future<void> queued;
    next = previous
        .catchError((_) {
          // Keep the per-subscription queue alive even if the previous write
          // failed. The next writer must still see the latest committed payload.
        })
        .then((_) => action());
    queued = next.then<void>((_) {}, onError: (_) {});
    _subscriptionWriteLocks[id] = queued;
    try {
      return await next;
    } finally {
      if (identical(_subscriptionWriteLocks[id], queued)) {
        _subscriptionWriteLocks.remove(id);
      }
    }
  }

  static Future<T> _withStoreMutationPermit<T>(
    Future<T> Function() action,
  ) async {
    final waiter = _StoreMutationWaiter(exclusive: false);
    _storeMutationWaiters.add(waiter);
    _drainStoreMutationWaiters();
    await waiter.ready.future;
    try {
      return await action();
    } finally {
      _activeStoreMutations--;
      _drainStoreMutationWaiters();
    }
  }

  static Future<T> _withExclusiveStoreMutation<T>(
    Future<T> Function() action,
  ) async {
    final waiter = _StoreMutationWaiter(exclusive: true);
    _storeMutationWaiters.add(waiter);
    _drainStoreMutationWaiters();
    await waiter.ready.future;
    try {
      return await action();
    } finally {
      _exclusiveStoreMutationActive = false;
      _drainStoreMutationWaiters();
    }
  }

  static void _drainStoreMutationWaiters() {
    if (_exclusiveStoreMutationActive || _storeMutationWaiters.isEmpty) {
      return;
    }
    if (_activeStoreMutations == 0 && _storeMutationWaiters.first.exclusive) {
      final waiter = _storeMutationWaiters.removeFirst();
      _exclusiveStoreMutationActive = true;
      waiter.ready.complete();
      return;
    }
    if (_storeMutationWaiters.first.exclusive) {
      return;
    }
    while (_storeMutationWaiters.isNotEmpty &&
        !_storeMutationWaiters.first.exclusive) {
      final waiter = _storeMutationWaiters.removeFirst();
      _activeStoreMutations++;
      waiter.ready.complete();
    }
  }

  static Future<T> _withSubscriptionMutationLock<T>(
    String id,
    Future<T> Function() action,
  ) {
    return _withStoreMutationPermit(
      () => _withSubscriptionWriteLock(id, action),
    );
  }

  static Future<T> _withSubscriptionWriteLocks<T>(
    List<String> sortedIds,
    Future<T> Function() action, [
    int index = 0,
  ]) {
    if (index >= sortedIds.length) {
      return action();
    }
    return _withSubscriptionWriteLock(
      sortedIds[index],
      () => _withSubscriptionWriteLocks(sortedIds, action, index + 1),
    );
  }

  static Future<T> _withHydraTrustWriteLock<T>(
    Future<T> Function() action,
  ) async {
    final previous = _hydraTrustWriteLock;
    late final Future<T> next;
    late final Future<void> queued;
    next = previous
        .catchError((_) {
          // A failed trust write must not poison the global tuple queue.
        })
        .then((_) => action());
    queued = next.then<void>((_) {}, onError: (_) {});
    _hydraTrustWriteLock = queued;
    return next;
  }

  static DateTime _operationDeadline(Duration? timeout) {
    return DateTime.now().add(timeout ?? _defaultRemoteOperationTimeout);
  }

  static Future<T> _withDeadline<T>(
    Future<T> future,
    DateTime deadline,
    String operationName,
  ) {
    final remaining = deadline.difference(DateTime.now());
    if (remaining <= Duration.zero) {
      throw TimeoutException('$operationName timed out');
    }
    return future.timeout(
      remaining,
      onTimeout: () =>
          throw TimeoutException('$operationName timed out', remaining),
    );
  }

  static Duration _remainingUntil(DateTime deadline) {
    final remaining = deadline.difference(DateTime.now());
    return remaining <= Duration.zero ? Duration.zero : remaining;
  }

  // ─────────────────── CRUD ───────────────────

  /// Returns all stored subscriptions.
  static List<Subscription> getAll() {
    final indexedResults = <({int index, Subscription subscription})>[];
    var index = 0;
    for (final subscription in getAllMetadata()) {
      indexedResults.add((
        index: index,
        subscription: _withPayload(subscription),
      ));
      index++;
    }
    indexedResults.sort((a, b) {
      final left = a.subscription.sortOrder ?? (1 << 30) + a.index;
      final right = b.subscription.sortOrder ?? (1 << 30) + b.index;
      return left.compareTo(right);
    });
    return indexedResults
        .map((entry) => entry.subscription)
        .toList(growable: false);
  }

  /// Loads all complete subscriptions while decoding large payload JSON away
  /// from the UI isolate. Hive values are copied before the worker starts.
  static Future<List<Subscription>> getAllInBackground() async {
    final metadataSnapshot = _metadataJsonSnapshot();
    if (metadataSnapshot.isEmpty) {
      return const <Subscription>[];
    }
    final payloadSnapshot = <String, String>{};
    for (final key in _payloadStore.keys) {
      final raw = _payloadStore.get(key);
      if (raw is String) {
        payloadSnapshot[key.toString()] = raw;
      }
    }
    return Isolate.run(() {
      return _decodeMetadataSnapshot(metadataSnapshot)
          .map((metadata) {
            final raw = payloadSnapshot[_payloadKeyForMetadata(metadata)];
            return raw == null ? metadata : _withPayloadFromRaw(metadata, raw);
          })
          .toList(growable: false);
    }, debugName: 'meow-subscriptions-full');
  }

  /// Returns metadata-only subscriptions without loading raw content/outbounds.
  static List<Subscription> getAllMetadata() {
    return _decodeMetadataSnapshot(_metadataJsonSnapshot());
  }

  /// Copies compact metadata strings from Hive and performs JSON/model decoding
  /// outside the UI isolate.
  static Future<List<Subscription>> getAllMetadataInBackground() async {
    final snapshot = _metadataJsonSnapshot();
    if (snapshot.isEmpty) {
      return const <Subscription>[];
    }
    return Isolate.run(
      () => _decodeMetadataSnapshot(snapshot),
      debugName: 'meow-subscription-metadata',
    );
  }

  static List<String> _metadataJsonSnapshot() {
    final values = <String>[];
    for (final key in _metaStore.keys) {
      if (key == _storageSchemaVersionKey) {
        continue;
      }
      final raw = _metaStore.get(key);
      if (raw is String) {
        values.add(raw);
      }
    }
    return values;
  }

  static List<Subscription> _decodeMetadataSnapshot(List<String> snapshot) {
    final indexedResults = <({int index, Subscription subscription})>[];
    for (var index = 0; index < snapshot.length; index++) {
      try {
        final map = jsonDecode(snapshot[index]) as Map<String, dynamic>;
        indexedResults.add((
          index: index,
          subscription: Subscription.fromMetadataMap(map),
        ));
      } catch (_) {
        // Skip corrupt entries.
      }
    }
    indexedResults.sort((a, b) {
      final left = a.subscription.sortOrder ?? (1 << 30) + a.index;
      final right = b.subscription.sortOrder ?? (1 << 30) + b.index;
      return left.compareTo(right);
    });
    return indexedResults
        .map((entry) => entry.subscription)
        .toList(growable: false);
  }

  /// Gets a single subscription by ID, or null.
  static Subscription? get(String id) {
    final metadata = _readMetadata(id);
    return metadata == null ? null : _withPayload(metadata);
  }

  /// Loads one complete subscription without decoding its payload on the UI
  /// isolate. Hive values are copied before the worker starts.
  static Future<Subscription?> getInBackground(String id) async {
    if (!isSafeSubscriptionStorageId(id)) {
      return null;
    }
    final metadataRaw = _metaStore.get(id);
    if (metadataRaw is! String) {
      return null;
    }
    late final Subscription metadata;
    try {
      metadata = Subscription.fromMetadataMap(
        jsonDecode(metadataRaw) as Map<String, dynamic>,
      );
      if (metadata.id != id || !isSafeSubscriptionStorageId(metadata.id)) {
        return null;
      }
    } catch (_) {
      return null;
    }
    final payloadRaw = _payloadStore.get(_payloadKeyForMetadata(metadata));
    final metadataMap = metadata.toMetadataMap();
    return Isolate.run(() {
      try {
        final metadata = Subscription.fromMetadataMap(metadataMap);
        return payloadRaw is String
            ? _withPayloadFromRaw(metadata, payloadRaw)
            : metadata;
      } catch (_) {
        return null;
      }
    }, debugName: 'meow-subscription-single');
  }

  /// Hydrates raw content/outbounds for a metadata-only subscription.
  static Subscription withPayload(Subscription metadata) {
    return _withPayload(metadata);
  }

  static String? payloadJsonFor(String id) {
    final snapshot = payloadSnapshotFor(id);
    if (snapshot == null) {
      return null;
    }
    try {
      return _decodeStoredPayload(snapshot);
    } catch (_) {
      return null;
    }
  }

  /// Returns the stored payload representation without decompression.
  ///
  /// Pass this snapshot to a worker isolate and hydrate it there. Calling
  /// [payloadJsonFor] for a multi-megabyte profile on the UI isolate would
  /// undo the startup benefit of compressed storage.
  static String? payloadSnapshotFor(String id) {
    final metadata = _readMetadata(id);
    final raw = _payloadStore.get(
      metadata == null ? id : _payloadKeyForMetadata(metadata),
    );
    return raw is String ? raw : null;
  }

  static Subscription hydratePayloadJson(Subscription metadata, String raw) {
    return _withPayloadFromRaw(metadata, raw);
  }

  /// Hydrates raw content/outbounds away from the UI isolate.
  static Future<Subscription> withPayloadInBackground(
    Subscription metadata,
  ) async {
    final raw = _payloadStore.get(_payloadKeyForMetadata(metadata));
    if (raw is! String) {
      return metadata;
    }
    final metadataMap = metadata.toMetadataMap();
    return Isolate.run(
      () => hydratePayloadJson(Subscription.fromMetadataMap(metadataMap), raw),
      debugName: 'meow-subscription-payload',
    );
  }

  /// Saves (creates or updates) a subscription.
  static Future<void> save(Subscription sub, {bool allowCreate = false}) async {
    await _withSubscriptionMutationLock(sub.id, () async {
      final currentMetadata = _readMetadata(sub.id);
      if (!allowCreate && currentMetadata == null) {
        throw StateError('Subscription ${sub.id} not found');
      }
      final currentIsHydraBox =
          currentMetadata?.sourceMetadata['format'] ==
          'hydrabox.io/subscription/v1';
      final proposedIsHydraBox =
          sub.sourceMetadata['format'] == 'hydrabox.io/subscription/v1';
      if (currentIsHydraBox || proposedIsHydraBox) {
        if (currentMetadata == null ||
            !currentIsHydraBox ||
            !proposedIsHydraBox) {
          throw const FormatException(
            'HydraBox subscriptions must be created or converted only by the '
            'strict import parser',
          );
        }
        _validateHydraBoxMetadataTransition(
          currentMetadata.sourceMetadata,
          sub.sourceMetadata,
        );
        for (final key in const {
          'format',
          'issuer',
          'subscription_id',
          'channel',
          'sequence',
          'encrypted',
          'key_id',
          'payload_sha256',
        }) {
          if (currentMetadata.sourceMetadata[key] != sub.sourceMetadata[key]) {
            throw const FormatException(
              'A local metadata edit cannot replace HydraBox trusted payload '
              'state',
            );
          }
        }
        _ensureSubscriptionUnchanged(
          current: currentMetadata,
          expectedPayloadKey: _payloadKeyForMetadata(sub),
          operation: 'saving subscription metadata',
        );
        final current = _withPayload(currentMetadata);
        await _saveUnlocked(
          sub.copyWith(
            rawContent: current.rawContent,
            outbounds: current.outbounds,
            groups: current.groups,
            profiles: current.profiles,
            nativeConfig: current.nativeConfig,
            clearNativeConfig: current.nativeConfig == null,
            sourceMetadata: current.sourceMetadata,
          ),
        );
        return;
      }
      if (currentMetadata != null) {
        _ensureSubscriptionUnchanged(
          current: currentMetadata,
          expectedPayloadKey: _payloadKeyForMetadata(sub),
          operation: 'saving the subscription',
        );
      }
      await _saveUnlocked(sub);
    });
  }

  static Future<void> _saveParsedImport(Subscription subscription) {
    return _withSubscriptionMutationLock(
      subscription.id,
      () => _saveUnlocked(subscription),
    );
  }

  static Future<void> _saveUnlocked(Subscription sub) async {
    _validatePersistentSourcePolicy(sub);
    final payload = await Isolate.run(
      () => _encodeStoredPayload(jsonEncode(sub.toPayloadMap())),
      debugName: 'meow-encode-subscription-payload',
    );
    final isHydraBox =
        sub.sourceMetadata['format'] == 'hydrabox.io/subscription/v1';
    if (!isHydraBox) {
      final current = _readMetadata(sub.id);
      if (current != null) {
        _validateHydraBoxMetadataTransition(
          current.sourceMetadata,
          sub.sourceMetadata,
        );
      }
      await _commitPayloadGenerationUnlocked(sub, payload);
      return;
    }
    await _withHydraTrustWriteLock(() async {
      final current = _readMetadata(sub.id);
      if (current != null) {
        _validateHydraBoxMetadataTransition(
          current.sourceMetadata,
          sub.sourceMetadata,
        );
      }
      _validateHydraBoxTupleAgainstStoredMetadata(
        subscriptionId: sub.id,
        proposed: sub.sourceMetadata,
      );
      await _commitPayloadGenerationUnlocked(sub, payload);
    });
  }

  /// Saves only lightweight subscription metadata.
  static Future<void> saveMetadata(Subscription sub) async {
    await _withSubscriptionMutationLock(
      sub.id,
      () => _saveMetadataUnlocked(sub),
    );
  }

  static Future<void> _saveMetadataUnlocked(Subscription sub) async {
    _validatePersistentSourcePolicy(sub);
    final current = _readMetadata(sub.id);
    if (current == null) {
      throw StateError(
        'Subscription ${sub.id} not found; metadata-only writes cannot create '
        'subscriptions',
      );
    }
    _ensureSubscriptionUnchanged(
      current: current,
      expectedPayloadKey: _payloadKeyForMetadata(sub),
      operation: 'saving subscription metadata',
    );
    final payloadKey = _payloadKeyForMetadata(current);
    final metadata = sub.copyWith(
      payloadStorageKey: payloadKey == sub.id ? '' : payloadKey,
      sourceMetadata: current.sourceMetadata,
    );
    await _metaStore.put(sub.id, jsonEncode(metadata.toMetadataMap()));
    await _metaStore.flush();
  }

  /// Commits a payload by writing a new immutable generation first and only
  /// then atomically switching the metadata pointer. A crash before the
  /// pointer switch leaves the previous complete payload selected. Runtime
  /// validation and last-known-good activation are separate concerns.
  static Future<void> _commitPayloadGenerationUnlocked(
    Subscription sub,
    String encodedPayload,
  ) async {
    validateSubscriptionStorageId(sub.id);
    final previousMetadataRaw = _metaStore.get(sub.id);
    final current = _readMetadata(sub.id);
    final oldKey = current == null ? null : _payloadKeyForMetadata(current);
    final newKey =
        '${sub.id}$_payloadGenerationSeparator${SubscriptionFetcher.generateId()}';

    await _payloadStore.put(newKey, encodedPayload);
    await _payloadStore.flush();
    final committedMetadata = sub.copyWith(payloadStorageKey: newKey);
    try {
      await _metaStore.put(
        sub.id,
        jsonEncode(committedMetadata.toMetadataMap()),
      );
      await _metaStore.flush();
    } catch (error, stackTrace) {
      // Hive updates its in-memory map before flush completes. Restore the
      // previous pointer before deleting the candidate so the live process
      // cannot observe metadata that references a removed generation. If the
      // rollback itself cannot be made durable, retain the candidate payload:
      // either possible metadata pointer will then still resolve after restart.
      var metadataRestored = false;
      try {
        if (previousMetadataRaw == null) {
          await _metaStore.delete(sub.id);
        } else {
          await _metaStore.put(sub.id, previousMetadataRaw);
        }
        await _metaStore.flush();
        metadataRestored = true;
      } catch (rollbackError) {
        AppLogStore.warning(
          'subscription storage',
          'Unable to restore metadata pointer for ${sub.id}: $rollbackError',
        );
      }
      if (metadataRestored) {
        try {
          await _payloadStore.delete(newKey);
          await _payloadStore.flush();
        } catch (cleanupError) {
          AppLogStore.warning(
            'subscription storage',
            'Unable to remove uncommitted payload for ${sub.id}: '
                '$cleanupError',
          );
        }
      }
      Error.throwWithStackTrace(error, stackTrace);
    }

    final staleKeys = <String>{?oldKey, sub.id}
      ..remove(newKey)
      ..removeWhere((key) => key.isEmpty);
    if (staleKeys.isNotEmpty) {
      try {
        await _payloadStore.deleteAll(staleKeys);
        await _payloadStore.flush();
      } catch (error) {
        // The new generation is already committed. Stale encrypted payloads
        // are harmless and can be cleaned on a later successful save/delete.
        AppLogStore.warning(
          'subscription storage',
          'Unable to clean stale payload generation for ${sub.id}: $error',
        );
      }
    }
  }

  static Future<bool> saveLatestPingsInBackground(
    String id,
    Map<String, int> latestPings,
  ) async {
    return saveOutboundRuntimeInfoInBackground(id, latestPings: latestPings);
  }

  static Future<bool> saveOutboundRuntimeInfoInBackground(
    String id, {
    Map<String, int> latestPings = const <String, int>{},
    Map<String, Map<String, String?>> externalInfos =
        const <String, Map<String, String?>>{},
  }) async {
    var saved = false;
    await _withSubscriptionMutationLock(id, () async {
      saved = await _saveOutboundRuntimeInfoInBackgroundUnlocked(
        id,
        latestPings: latestPings,
        externalInfos: externalInfos,
      );
    });
    return saved;
  }

  static Future<bool> _saveOutboundRuntimeInfoInBackgroundUnlocked(
    String id, {
    required Map<String, int> latestPings,
    required Map<String, Map<String, String?>> externalInfos,
  }) async {
    // Latency belongs to the current runtime session. Persisting it makes an
    // old value look fresh after reconnect or process restart.
    final updates = <String, Map<String, Object?>>{};
    for (final entry in externalInfos.entries) {
      final tag = entry.key.trim();
      if (tag.isEmpty) {
        continue;
      }
      final externalIp = entry.value['external_ip']?.trim();
      final sourceCountry = entry.value['source_country']?.trim().toUpperCase();
      final exitCountry =
          (entry.value['exit_country'] ?? entry.value['country'])
              ?.trim()
              .toUpperCase();
      if ((externalIp == null || externalIp.isEmpty) &&
          (sourceCountry == null || sourceCountry.isEmpty) &&
          (exitCountry == null || exitCountry.isEmpty)) {
        continue;
      }
      final update = updates.putIfAbsent(tag, () => <String, Object?>{});
      if (externalIp != null && externalIp.isNotEmpty) {
        update['external_ip'] = externalIp;
      }
      if (sourceCountry != null && sourceCountry.isNotEmpty) {
        update['source_country'] = sourceCountry;
      }
      if (exitCountry != null && exitCountry.isNotEmpty) {
        update['exit_country'] = exitCountry;
      }
    }
    if (updates.isEmpty) {
      return false;
    }
    final metadata = _readMetadata(id);
    if (metadata == null) {
      return false;
    }
    final payloadKey = _payloadKeyForMetadata(metadata);
    final raw = _payloadStore.get(payloadKey);
    if (raw is! String || raw.isEmpty) {
      return false;
    }
    final updatedRaw = await Isolate.run(
      () => _rewriteOutboundRuntimeInfoPayload(raw, updates),
      debugName: 'meow-save-outbound-runtime-info',
    );
    if (updatedRaw == null || updatedRaw == raw) {
      return false;
    }
    await _commitPayloadGenerationUnlocked(metadata, updatedRaw);
    return true;
  }

  /// Deletes a subscription by ID.
  static Future<void> delete(String id) async {
    await _withSubscriptionMutationLock(id, () => _deleteUnlocked(id));
  }

  static Future<void> _deleteUnlocked(String id) async {
    final metadata = _readMetadata(id);
    final payloadKeys = <String>{id};
    if (metadata != null) {
      payloadKeys.add(_payloadKeyForMetadata(metadata));
    }
    final generationPrefix = '$id$_payloadGenerationSeparator';
    for (final key in _payloadStore.keys) {
      if (key is String && key.startsWith(generationPrefix)) {
        payloadKeys.add(key);
      }
    }
    await _metaStore.delete(id);
    await _metaStore.flush();
    await _payloadStore.deleteAll(payloadKeys);
    await _payloadStore.flush();
  }

  static Future<void> deleteMany(Iterable<String> ids) async {
    final normalizedIds = ids.toSet().toList(growable: false)..sort();
    if (normalizedIds.isEmpty) return;
    for (final id in normalizedIds) {
      validateSubscriptionStorageId(id);
    }
    await _withStoreMutationPermit(
      () => _withSubscriptionWriteLocks(normalizedIds, () async {
        final payloadKeys = <String>{...normalizedIds};
        final generationPrefixes = normalizedIds
            .map((id) => '$id$_payloadGenerationSeparator')
            .toList(growable: false);
        for (final id in normalizedIds) {
          final metadata = _readMetadata(id);
          if (metadata != null) {
            payloadKeys.add(_payloadKeyForMetadata(metadata));
          }
        }
        for (final key in _payloadStore.keys) {
          if (key is String &&
              generationPrefixes.any((prefix) => key.startsWith(prefix))) {
            payloadKeys.add(key);
          }
        }
        await _metaStore.deleteAll(normalizedIds);
        await _metaStore.flush();
        await _payloadStore.deleteAll(payloadKeys);
        await _payloadStore.flush();
      }),
    );
  }

  /// Deletes all subscriptions.
  static Future<void> clear() async {
    await _withExclusiveStoreMutation(() async {
      await _metaStore.clear();
      await _metaStore.flush();
      await _payloadStore.clear();
      await _payloadStore.flush();
    });
  }

  // ─────────────────── High-level operations ───────────────────

  /// Adds a new subscription from a URL.
  ///
  /// 1. Fetches the URL
  /// 2. Parses headers + body
  /// 3. Creates Outbound objects from parsed configs
  /// 4. Saves to store
  ///
  /// Returns the created [Subscription].
  static Future<SubscriptionImportResult> addFromUrl(
    String url, {
    String? customName,
    int autoRefreshMinutes = 360,
    SubscriptionInfo? requestInfo,
    Duration? operationTimeout,
    bool Function()? isCancelled,
  }) async {
    final id = SubscriptionFetcher.generateId();
    final deadline = _operationDeadline(operationTimeout);
    var parsedHydraBox = false;
    _throwIfImportCancelled(isCancelled);
    try {
      final result = await _withDeadline(
        SubscriptionFetcher.fetch(
          url,
          requestInfo: requestInfo,
          operationTimeout: _remainingUntil(deadline),
        ),
        deadline,
        'subscription import',
      );
      _throwIfImportCancelled(isCancelled);
      parsedHydraBox =
          result.parseResult.format == SubscriptionFormat.hydraboxV1;
      _validateHydraBoxSource(result.parseResult);

      final payload = await _withDeadline(
        _buildSubscriptionPayloadAsync(
          result.parseResult,
          providerName: _providerNameHint(
            customName: customName,
            headerTitle: result.headerInfo.title,
          ),
        ),
        deadline,
        'subscription import',
      );
      _throwIfImportCancelled(isCancelled);
      final outbounds = payload.outbounds;
      final selectedProfile = _preferredHydraBoxProfile(
        payload.profiles,
        defaultId: result.parseResult.defaultProfileId,
      );
      if (!_hasUsableOutbounds(outbounds) &&
          !_allowsEmptySelectableEntries(result.parseResult)) {
        throw const SubscriptionContentException(
          SubscriptionContentFailureKind.noUsableProxies,
        );
      }

      final sub = Subscription(
        id: id,
        name: _pickSubscriptionName(
          customName: customName,
          headerTitle: result.headerInfo.title,
          outbounds: outbounds,
          url: url,
        ),
        url: url,
        selectedProxyTag:
            selectedProfile?.runtimeTag ??
            _selectedProxyTagForOutbounds(outbounds, groups: payload.groups),
        selectedProfileId: selectedProfile?.id ?? '',
        sortOrder: _nextSortOrder(),
        lastUpdated: DateTime.now().millisecondsSinceEpoch,
        autoRefreshMinutes: result.headerInfo.updateIntervalHours != null
            ? result.headerInfo.updateIntervalHours! * 60
            : autoRefreshMinutes,
        rawContent: result.rawContent,
        outbounds: outbounds,
        groups: payload.groups,
        profiles: payload.profiles,
        nativeConfig: result.parseResult.nativeConfig,
        sourceMetadata: result.parseResult.sourceMetadata,
        urlTestConfig: const UrlTestConfig(),
        info: result.headerInfo.copyWith(
          happCryptoLink:
              requestInfo?.happCryptoLink ?? result.headerInfo.happCryptoLink,
          customUserAgent:
              requestInfo?.customUserAgent ?? result.headerInfo.customUserAgent,
          customRequestHeader:
              requestInfo?.customRequestHeader ??
              result.headerInfo.customRequestHeader,
          requireHwid:
              requestInfo?.requireHwid ?? result.headerInfo.requireHwid,
          customHwid: requestInfo?.customHwid ?? result.headerInfo.customHwid,
        ),
      );

      _logLikelyHwidWarning(sub);
      _throwIfImportCancelled(isCancelled);
      await _saveParsedImport(sub);
      if (isCancelled?.call() ?? false) {
        await delete(id);
        throw const SubscriptionImportCancelledException();
      }
      return SubscriptionImportResult(subscription: get(id) ?? sub);
    } catch (error) {
      if (error is SubscriptionImportCancelledException ||
          (isCancelled?.call() ?? false)) {
        throw const SubscriptionImportCancelledException();
      }
      if (error is TimeoutException) {
        AppLogStore.warning(
          'subscription',
          'Initial subscription import timed out for '
              '"${_safeSubscriptionUrlForLog(url)}": ${error.runtimeType}',
        );
        rethrow;
      }
      if (error is FormatException ||
          error is UnsupportedError ||
          parsedHydraBox ||
          _subscriptionUrlHasHydraBoxKey(url)) {
        // A key-bearing source is an explicit encryption policy. Do not turn
        // authentication, transport, format, or trust failures from an
        // authenticated/recognized HydraBox source into a saved legacy
        // placeholder that could be mistaken for an accepted subscription.
        rethrow;
      }
      final sub = Subscription(
        id: id,
        name: _pickSubscriptionName(
          customName: customName,
          headerTitle: requestInfo?.title,
          outbounds: const [],
          url: url,
        ),
        url: url,
        sortOrder: _nextSortOrder(),
        autoRefreshMinutes: autoRefreshMinutes,
        urlTestConfig: const UrlTestConfig(),
        info: requestInfo,
      );
      _throwIfImportCancelled(isCancelled);
      await save(sub, allowCreate: true);
      if (isCancelled?.call() ?? false) {
        await delete(id);
        throw const SubscriptionImportCancelledException();
      }
      AppLogStore.warning(
        'subscription',
        'Initial subscription import failed for '
            '"${_safeSubscriptionUrlForLog(url)}", '
            'saved placeholder entry instead: ${error.runtimeType}',
      );
      return SubscriptionImportResult(
        subscription: get(id) ?? sub,
        warning: error,
      );
    }
  }

  static Future<SubscriptionImportResult> addFromContent(
    String content, {
    String? customName,
    String? sourceName,
    String? decryptionKey,
    Duration? operationTimeout,
    bool Function()? isCancelled,
  }) async {
    final deadline = _operationDeadline(operationTimeout);
    _throwIfImportCancelled(isCancelled);
    final parseResult = await _withDeadline(
      SubscriptionParser.parseInBackground(
        content,
        decryptionKey: decryptionKey,
      ),
      deadline,
      'subscription file import',
    );
    _throwIfImportCancelled(isCancelled);
    if (parseResult.format == SubscriptionFormat.hydraboxV1 &&
        parseResult.sourceMetadata['encrypted'] == true) {
      // A local file has no durable secret-bearing source URI. Until HydraBox
      // has a Keystore-backed per-file key record and a restore-time key
      // prompt, saving this result would create a subscription that succeeds
      // once but cannot be authenticated again by reparse or backup restore.
      throw UnsupportedError(
        'Persistent encrypted HydraBox file import is not available yet; '
        'use a key-bearing HTTPS subscription URL',
      );
    }
    _validateHydraBoxSource(parseResult);
    final payload = await _withDeadline(
      _buildSubscriptionPayloadAsync(
        parseResult,
        providerName: _providerNameHint(
          customName: customName,
          headerTitle: sourceName,
        ),
      ),
      deadline,
      'subscription file import',
    );
    _throwIfImportCancelled(isCancelled);
    final outbounds = payload.outbounds;
    final selectedProfile = _preferredHydraBoxProfile(
      payload.profiles,
      defaultId: parseResult.defaultProfileId,
    );
    if (!_hasUsableOutbounds(outbounds) &&
        !_allowsEmptySelectableEntries(parseResult)) {
      throw const SubscriptionContentException(
        SubscriptionContentFailureKind.noUsableProxies,
      );
    }

    final normalizedSourceName = _normalizeName(sourceName) ?? 'subscription';
    final localUrl = _localFileImportUrl(normalizedSourceName);
    final sub = Subscription(
      id: SubscriptionFetcher.generateId(),
      name: _pickSubscriptionName(
        customName: customName,
        headerTitle: null,
        outbounds: outbounds,
        url: localUrl,
      ),
      url: localUrl,
      selectedProxyTag:
          selectedProfile?.runtimeTag ??
          _selectedProxyTagForOutbounds(outbounds, groups: payload.groups),
      selectedProfileId: selectedProfile?.id ?? '',
      sortOrder: _nextSortOrder(),
      lastUpdated: DateTime.now().millisecondsSinceEpoch,
      disableAutoUpdate: true,
      rawContent: content,
      outbounds: outbounds,
      groups: payload.groups,
      profiles: payload.profiles,
      nativeConfig: parseResult.nativeConfig,
      sourceMetadata: parseResult.sourceMetadata,
      urlTestConfig: const UrlTestConfig(),
    );

    _throwIfImportCancelled(isCancelled);
    await _saveParsedImport(sub);
    if (isCancelled?.call() ?? false) {
      await delete(sub.id);
      throw const SubscriptionImportCancelledException();
    }
    return SubscriptionImportResult(subscription: get(sub.id) ?? sub);
  }

  /// Imports one decoded backup record. HydraBox payload projections and trust
  /// metadata from the backup are never authoritative: the original wire
  /// payload is parsed again and all executable/runtime fields are rebuilt.
  static Future<void> importFromBackup(Subscription subscription) async {
    await importBackupBatch(<Subscription>[subscription]);
  }

  /// Validates every backup record before the first write, then applies the
  /// prepared batch under the exclusive store barrier. If a storage write
  /// fails, all affected metadata and payload generations are restored.
  static Future<void> importBackupBatch(
    List<Subscription> subscriptions,
  ) async {
    if (subscriptions.isEmpty) return;

    final prepared = <Subscription>[];
    for (final subscription in subscriptions) {
      prepared.add(await _prepareBackupImport(subscription));
    }

    await _withExclusiveStoreMutation(() async {
      final normalized = <Subscription>[];
      final ids = <String>{};
      final proposedHydraTuples = <String, String>{};
      for (final candidate in prepared) {
        validateSubscriptionStorageId(candidate.id);
        if (!ids.add(candidate.id)) {
          throw const FormatException(
            'Backup contains duplicate subscription storage IDs',
          );
        }
        final current = _readMetadata(candidate.id);
        final subscription = _normalizeBackupLocalState(candidate, current);
        _validatePersistentSourcePolicy(subscription);
        final currentIsHydraBox =
            current?.sourceMetadata['format'] == 'hydrabox.io/subscription/v1';
        final proposedIsHydraBox =
            subscription.sourceMetadata['format'] ==
            'hydrabox.io/subscription/v1';
        if (currentIsHydraBox && !proposedIsHydraBox) {
          throw const FormatException(
            'A backup cannot replace a HydraBox record with legacy payload',
          );
        }
        if (proposedIsHydraBox) {
          if (current != null) {
            _validateHydraBoxMetadataTransition(
              current.sourceMetadata,
              subscription.sourceMetadata,
            );
          }
          final tupleKey = _hydraBoxTrustTupleKey(subscription.sourceMetadata);
          if (tupleKey == null) {
            throw const FormatException(
              'Invalid HydraBox durable trust metadata',
            );
          }
          final previousOwner = proposedHydraTuples[tupleKey];
          if (previousOwner != null && previousOwner != subscription.id) {
            throw const FormatException(
              'Backup contains duplicate HydraBox trust tuples',
            );
          }
          proposedHydraTuples[tupleKey] = subscription.id;
          _validateHydraBoxTupleAgainstStoredMetadata(
            subscriptionId: subscription.id,
            proposed: subscription.sourceMetadata,
          );
        }
        normalized.add(subscription);
      }

      final metadataBefore = <String, dynamic>{
        for (final id in ids) id: _metaStore.get(id),
      };
      final metadataKeysBefore = <String>{
        for (final id in ids)
          if (_metaStore.containsKey(id)) id,
      };
      final payloadBefore = <dynamic, dynamic>{};
      for (final key in _payloadStore.keys) {
        if (key is String && _payloadKeyBelongsToAnyId(key, ids)) {
          payloadBefore[key] = _payloadStore.get(key);
        }
      }

      try {
        for (final subscription in normalized) {
          await _saveUnlocked(subscription);
        }
      } catch (error, stackTrace) {
        try {
          await _metaStore.deleteAll(ids);
          await _metaStore.flush();
          final currentPayloadKeys = <dynamic>[
            for (final key in _payloadStore.keys)
              if (key is String && _payloadKeyBelongsToAnyId(key, ids)) key,
          ];
          if (currentPayloadKeys.isNotEmpty) {
            await _payloadStore.deleteAll(currentPayloadKeys);
          }
          if (payloadBefore.isNotEmpty) {
            await _payloadStore.putAll(payloadBefore);
          }
          await _payloadStore.flush();
          final metadataToRestore = <dynamic, dynamic>{
            for (final id in metadataKeysBefore) id: metadataBefore[id],
          };
          if (metadataToRestore.isNotEmpty) {
            await _metaStore.putAll(metadataToRestore);
          }
          await _metaStore.flush();
        } catch (rollbackError, rollbackStackTrace) {
          Error.throwWithStackTrace(
            StateError(
              'Backup import failed and storage rollback was incomplete: '
              '${rollbackError.runtimeType}',
            ),
            rollbackStackTrace,
          );
        }
        Error.throwWithStackTrace(error, stackTrace);
      }
    });
  }

  static bool _payloadKeyBelongsToAnyId(String key, Set<String> ids) {
    for (final id in ids) {
      if (key == id || key.startsWith('$id$_payloadGenerationSeparator')) {
        return true;
      }
    }
    return false;
  }

  static Future<Subscription> _prepareBackupImport(
    Subscription subscription,
  ) async {
    validateSubscriptionStorageId(subscription.id);
    final claimsHydraBox =
        subscription.sourceMetadata['format'] == 'hydrabox.io/subscription/v1';
    final rawContent = subscription.rawContent;
    Uri? sourceUri;
    var hasHydraBoxKeyPolicy = false;
    if (subscription.url.trim().isNotEmpty) {
      try {
        sourceUri = SubscriptionFetcher.parseRequestUri(subscription.url);
        if (HydraBoxJweCodec.hasKeyQueryParameter(sourceUri)) {
          throw const FormatException(
            'HydraBox hbx-key is allowed only in the URI fragment',
          );
        }
        hasHydraBoxKeyPolicy = HydraBoxJweCodec.hasKeyFragment(sourceUri);
      } on FormatException {
        rethrow;
      } catch (_) {
        sourceUri = null;
      }
    }
    final requiresStrictHydraBoxImport =
        claimsHydraBox ||
        HydraBoxSubscriptionParser.looksLike(rawContent) ||
        hasHydraBoxKeyPolicy;
    if (!requiresStrictHydraBoxImport) {
      return subscription.copyWith(payloadStorageKey: '');
    }
    if (rawContent.trim().isEmpty) {
      throw const FormatException(
        'HydraBox backup record is missing its original wire payload',
      );
    }
    String? decryptionKey;
    if (sourceUri != null) {
      try {
        final hasKeyPolicy = HydraBoxJweCodec.hasKeyFragment(sourceUri);
        decryptionKey = HydraBoxJweCodec.keyFromUri(sourceUri);
        if (hasKeyPolicy && decryptionKey == null) {
          throw const FormatException(
            'HydraBox hbx-key fragment must contain one valid key value',
          );
        }
      } on FormatException {
        rethrow;
      } catch (_) {
        // Encrypted HydraBox content fails closed in the strict parser below.
      }
    }

    final parseResult = await SubscriptionParser.parseInBackground(
      rawContent,
      decryptionKey: decryptionKey,
    );
    if (parseResult.format != SubscriptionFormat.hydraboxV1) {
      throw const FormatException(
        'HydraBox backup metadata does not match its wire payload',
      );
    }
    _validateHydraBoxSource(parseResult);
    final parsedNativeConfig = parseResult.nativeConfig;
    if (claimsHydraBox) {
      for (final key in const {
        'format',
        'issuer',
        'subscription_id',
        'channel',
        'sequence',
        'encrypted',
        'key_id',
        'payload_sha256',
      }) {
        if (subscription.sourceMetadata[key] !=
            parseResult.sourceMetadata[key]) {
          throw FormatException(
            'HydraBox backup trust field "$key" does not match the wire payload',
          );
        }
      }
      if (subscription.nativeConfig == null ||
          parsedNativeConfig == null ||
          !_jsonValuesEqual(subscription.nativeConfig, parsedNativeConfig)) {
        throw const FormatException(
          'HydraBox backup native config does not match the wire payload',
        );
      }
    }

    final payload = await _buildSubscriptionPayloadAsync(
      parseResult,
      providerName: _providerNameHint(
        customName: subscription.name,
        headerTitle: subscription.info?.title,
      ),
    );
    final rebuiltOutbounds = _preserveUserState(
      subscription.outbounds,
      payload.outbounds,
    );
    final selectedProfile = _preferredHydraBoxProfile(
      payload.profiles,
      preferredId: subscription.selectedProfileId,
      preferredRuntimeTag: subscription.selectedProxyTag,
      defaultId: parseResult.defaultProfileId,
    );
    final rebuilt = subscription.copyWith(
      selectedProxyTag:
          selectedProfile?.runtimeTag ??
          _selectedProxyTagForOutbounds(
            rebuiltOutbounds,
            preferredTag: subscription.selectedProxyTag,
            groups: payload.groups,
          ),
      selectedProfileId: selectedProfile?.id ?? '',
      rawContent: rawContent,
      outbounds: rebuiltOutbounds,
      groups: payload.groups,
      profiles: payload.profiles,
      nativeConfig: parsedNativeConfig,
      sourceMetadata: parseResult.sourceMetadata,
      payloadStorageKey: '',
    );
    return rebuilt;
  }

  static Subscription _normalizeBackupLocalState(
    Subscription imported,
    Subscription? current,
  ) {
    final sameSource = current != null && current.url == imported.url;
    final importedInfo = imported.info;
    final currentInfo = sameSource ? current.info : null;
    final sanitizedInfo = SubscriptionInfo(
      title: importedInfo?.title,
      upload: importedInfo?.upload,
      download: importedInfo?.download,
      total: importedInfo?.total,
      expire: importedInfo?.expire,
      supportUrl: _safeWebUrl(importedInfo?.supportUrl),
      webPageUrl: _safeWebUrl(importedInfo?.webPageUrl),
      updateIntervalHours: importedInfo?.updateIntervalHours,
      happCryptoLink: currentInfo?.happCryptoLink,
      newUrl: currentInfo?.newUrl,
      ignoreSubscriptionMoved: currentInfo?.ignoreSubscriptionMoved ?? false,
      perAppProxyMode: currentInfo?.perAppProxyMode,
      perAppProxyList: currentInfo?.perAppProxyList,
      customUserAgent: currentInfo?.customUserAgent,
      customRequestHeader: currentInfo?.customRequestHeader,
      requireHwid: currentInfo?.requireHwid ?? false,
      customHwid: currentInfo?.customHwid,
    );
    return imported.copyWith(
      payloadStorageKey: '',
      lastUpdated: sameSource
          ? current.lastUpdated
          : DateTime.now().millisecondsSinceEpoch,
      info: sanitizedInfo,
    );
  }

  static String? _safeWebUrl(String? value) {
    final normalized = value?.trim() ?? '';
    if (normalized.isEmpty) return null;
    final uri = Uri.tryParse(normalized);
    if (uri == null ||
        uri.host.isEmpty ||
        (uri.scheme.toLowerCase() != 'https' &&
            uri.scheme.toLowerCase() != 'http')) {
      return null;
    }
    return uri.toString();
  }

  static bool _jsonValuesEqual(dynamic left, dynamic right) {
    return jsonEncode(_stableOutboundIdentityValue(left)) ==
        jsonEncode(_stableOutboundIdentityValue(right));
  }

  static void _throwIfImportCancelled(bool Function()? isCancelled) {
    if (isCancelled?.call() ?? false) {
      throw const SubscriptionImportCancelledException();
    }
  }

  /// Refreshes an existing subscription (re-fetches from URL).
  ///
  /// Returns the updated [Subscription].
  static Future<Subscription> refresh(String id, {Duration? operationTimeout}) {
    final inFlight = _refreshesInFlight[id];
    if (inFlight != null) {
      return inFlight;
    }
    final operation = _refresh(id, operationTimeout: operationTimeout);
    _refreshesInFlight[id] = operation;
    return operation.whenComplete(() {
      if (identical(_refreshesInFlight[id], operation)) {
        _refreshesInFlight.remove(id);
      }
    });
  }

  static Future<Subscription> _refresh(
    String id, {
    Duration? operationTimeout,
  }) async {
    final existingBeforeFetch = get(id);
    if (existingBeforeFetch == null) {
      throw StateError('Subscription $id not found');
    }
    if (isLocalFileImportUrl(existingBeforeFetch.url)) {
      throw StateError('Manual imports cannot be refreshed');
    }
    final expectedPayloadKey = _payloadKeyForMetadata(existingBeforeFetch);
    final expectedUrl = existingBeforeFetch.url;

    final deadline = _operationDeadline(operationTimeout);
    final result = await _withDeadline(
      SubscriptionFetcher.fetch(
        existingBeforeFetch.url,
        requestInfo: existingBeforeFetch.info,
        operationTimeout: _remainingUntil(deadline),
      ),
      deadline,
      'subscription refresh',
    );
    _validateHydraBoxRefresh(existingBeforeFetch, result.parseResult);
    final payload = await _withDeadline(
      _buildSubscriptionPayloadAsync(
        result.parseResult,
        providerName: _providerNameHint(
          customName: existingBeforeFetch.name,
          headerTitle:
              result.headerInfo.title ?? existingBeforeFetch.info?.title,
        ),
      ),
      deadline,
      'subscription refresh',
    );
    final outbounds = payload.outbounds;
    if (!_hasUsableOutbounds(outbounds) &&
        !_allowsEmptySelectableEntries(result.parseResult)) {
      throw const SubscriptionContentException(
        SubscriptionContentFailureKind.noUsableProxies,
      );
    }

    return _withSubscriptionMutationLock(id, () async {
      final existing = get(id);
      if (existing == null) {
        throw StateError('Subscription $id not found');
      }
      // The fetch and parse happen outside the write lock. Another writer may
      // commit a newer trusted sequence while they are in flight, so validate
      // again against the state read inside the same critical section as the
      // payload commit.
      _validateHydraBoxRefresh(existing, result.parseResult);
      _ensureSubscriptionUnchanged(
        current: existing,
        expectedPayloadKey: expectedPayloadKey,
        expectedUrl: expectedUrl,
        operation: 'refreshing the subscription',
      );
      final existingMovedUrl = existing.info?.newUrl;
      final nextMovedUrl = result.headerInfo.newUrl;
      final preserveMovedIgnore =
          existing.info?.ignoreSubscriptionMoved == true &&
          existingMovedUrl != null &&
          existingMovedUrl.isNotEmpty &&
          existingMovedUrl == nextMovedUrl;

      final preservedOutbounds = _preserveUserState(
        existing.outbounds,
        outbounds,
      );
      final selectedProfile = _preferredHydraBoxProfile(
        payload.profiles,
        preferredId: existing.selectedProfileId,
        preferredRuntimeTag: existing.selectedProxyTag,
        defaultId: result.parseResult.defaultProfileId,
      );

      final updated = existing.copyWith(
        name: existing.name,
        url: existing.url,
        selectedProxyTag:
            selectedProfile?.runtimeTag ??
            _selectedProxyTagForOutbounds(
              preservedOutbounds,
              preferredTag: existing.selectedProxyTag,
              groups: payload.groups,
            ),
        selectedProfileId: selectedProfile?.id ?? '',
        sortOrder: existing.sortOrder,
        lastUpdated: DateTime.now().millisecondsSinceEpoch,
        rawContent: result.rawContent,
        outbounds: preservedOutbounds,
        groups: payload.groups,
        profiles: payload.profiles,
        nativeConfig: result.parseResult.nativeConfig,
        clearNativeConfig: result.parseResult.nativeConfig == null,
        sourceMetadata: result.parseResult.sourceMetadata,
        autoRefreshMinutes: result.headerInfo.updateIntervalHours != null
            ? result.headerInfo.updateIntervalHours! * 60
            : existing.autoRefreshMinutes,
        info: result.headerInfo.copyWith(
          happCryptoLink: existing.info?.happCryptoLink,
          ignoreSubscriptionMoved: preserveMovedIgnore,
          customUserAgent: existing.info?.customUserAgent,
          customRequestHeader: existing.info?.customRequestHeader,
          requireHwid: existing.info?.requireHwid ?? false,
          customHwid: existing.info?.customHwid,
        ),
      );

      _logLikelyHwidWarning(updated);
      await _saveUnlocked(updated);
      return get(id) ?? updated;
    });
  }

  /// Rebuilds outbounds from saved raw content without fetching the network URL.
  ///
  /// This is useful when parsing rules change and we want to re-interpret the
  /// already stored subscription payload.
  static Future<Subscription> reparseFromRaw(String id) async {
    final existingBeforeParse = get(id);
    if (existingBeforeParse == null) {
      throw StateError('Subscription $id not found');
    }
    final rawContent = existingBeforeParse.rawContent.trim();
    if (rawContent.isEmpty) {
      throw const SubscriptionContentException(
        SubscriptionContentFailureKind.emptyResponse,
      );
    }
    final expectedPayloadKey = _payloadKeyForMetadata(existingBeforeParse);
    final expectedUrl = existingBeforeParse.url;

    final sourceUri = SubscriptionFetcher.parseRequestUri(
      existingBeforeParse.url,
    );
    final hasHydraBoxKeyPolicy = HydraBoxJweCodec.hasKeyFragment(sourceUri);
    final decryptionKey = HydraBoxJweCodec.keyFromUri(sourceUri);
    if (hasHydraBoxKeyPolicy && decryptionKey == null) {
      throw const FormatException(
        'HydraBox hbx-key fragment must contain one valid key value',
      );
    }
    final parseResult = await SubscriptionParser.parseInBackground(
      rawContent,
      decryptionKey: decryptionKey,
    );
    _validateHydraBoxRefresh(existingBeforeParse, parseResult);
    if (parseResult.outbounds.isEmpty &&
        !_allowsEmptySelectableEntries(parseResult)) {
      throw const SubscriptionContentException(
        SubscriptionContentFailureKind.noUsableProxies,
      );
    }

    final payload = await _buildSubscriptionPayloadAsync(
      parseResult,
      providerName: _providerNameHint(
        customName: existingBeforeParse.name,
        headerTitle: existingBeforeParse.info?.title,
      ),
    );
    final reparsedOutbounds = payload.outbounds;
    if (!_hasUsableOutbounds(reparsedOutbounds) &&
        !_allowsEmptySelectableEntries(parseResult)) {
      throw const SubscriptionContentException(
        SubscriptionContentFailureKind.noUsableProxies,
      );
    }

    return _withSubscriptionMutationLock(id, () async {
      final existing = get(id);
      if (existing == null) {
        throw StateError('Subscription $id not found');
      }
      // Parsing saved content is also outside the write lock. Re-check the
      // anti-replay state after re-reading the subscription under the lock so
      // a concurrent refresh cannot be overwritten by an older parse result.
      _validateHydraBoxRefresh(existing, parseResult);
      _ensureSubscriptionUnchanged(
        current: existing,
        expectedPayloadKey: expectedPayloadKey,
        expectedUrl: expectedUrl,
        operation: 'reparsing the subscription',
      );
      final preservedOutbounds = _preserveUserState(
        existing.outbounds,
        reparsedOutbounds,
      );
      final selectedProfile = _preferredHydraBoxProfile(
        payload.profiles,
        preferredId: existing.selectedProfileId,
        preferredRuntimeTag: existing.selectedProxyTag,
        defaultId: parseResult.defaultProfileId,
      );

      final updated = existing.copyWith(
        selectedProxyTag:
            selectedProfile?.runtimeTag ??
            _selectedProxyTagForOutbounds(
              preservedOutbounds,
              preferredTag: existing.selectedProxyTag,
              groups: payload.groups,
            ),
        selectedProfileId: selectedProfile?.id ?? '',
        outbounds: preservedOutbounds,
        groups: payload.groups,
        profiles: payload.profiles,
        nativeConfig: parseResult.nativeConfig,
        clearNativeConfig: parseResult.nativeConfig == null,
        sourceMetadata: parseResult.sourceMetadata,
      );
      await _saveUnlocked(updated);
      return get(id) ?? updated;
    });
  }

  static Future<void> moveUp(String id) async {
    final subscriptions = getAllMetadata();
    final index = subscriptions.indexWhere(
      (subscription) => subscription.id == id,
    );
    if (index <= 0) {
      return;
    }
    final reordered = subscriptions.toList(growable: false);
    final previous = reordered[index - 1];
    reordered[index - 1] = reordered[index];
    reordered[index] = previous;
    await _saveOrdered(reordered);
  }

  static Future<void> reorder(List<Subscription> subscriptions) async {
    await _saveOrdered(subscriptions);
  }

  static Future<void> cachePayloadSummaries(
    Map<String, ({int visibleProxyCount, bool hasRawPayload})> summaries,
  ) async {
    if (summaries.isEmpty) {
      return;
    }
    for (final entry in summaries.entries) {
      await _withSubscriptionMutationLock(entry.key, () async {
        final current = _readMetadata(entry.key);
        if (current == null) return;
        final updated = current.copyWith(
          cachedVisibleProxyCount: entry.value.visibleProxyCount,
          hasRawPayload: entry.value.hasRawPayload,
        );
        // Re-read and patch only the current generation while holding the
        // subscription lock. A stale summary must never restore an older
        // anti-replay sequence or payload pointer after a concurrent refresh.
        await _saveMetadataUnlocked(updated);
      });
    }
  }

  // ─────────────────── Helpers ───────────────────

  static String _selectedProxyTagForOutbounds(
    List<Outbound> outbounds, {
    String? preferredTag,
    List<SubscriptionGroup> groups = const [],
  }) {
    final selectableOutbounds = outbounds
        .where(
          (outbound) =>
              !outbound.info.deleted && outbound.config['_group_only'] != true,
        )
        .toList(growable: false);
    if (selectableOutbounds.isEmpty) {
      return '';
    }
    if (selectableOutbounds.length == 1) {
      return selectableOutbounds.first.tag;
    }
    final normalizedPreferred = normalizeProxySelectionTag(preferredTag ?? '');
    if (normalizedPreferred.isEmpty) {
      return lowestProxyTag;
    }
    if (isLowestProxyTag(normalizedPreferred)) {
      return lowestProxyTag;
    }
    final liveOutboundTags = selectableOutbounds
        .map((outbound) => outbound.tag)
        .toSet();
    for (final group in groups) {
      if (group.tag == normalizedPreferred &&
          group.outboundTags.any(liveOutboundTags.contains)) {
        return normalizedPreferred;
      }
    }
    for (final outbound in selectableOutbounds) {
      if (outbound.tag == normalizedPreferred) {
        return normalizedPreferred;
      }
    }
    return lowestProxyTag;
  }

  static bool _hasUsableOutbounds(List<Outbound> outbounds) {
    return outbounds.any(
      (outbound) =>
          !outbound.info.deleted && outbound.config['_group_only'] != true,
    );
  }

  static bool _allowsEmptySelectableEntries(ParseResult parseResult) {
    // A complete sing-box document can be intentionally inbound-, service-,
    // provider- or DNS-only. Its raw payload is still consumed by the runtime
    // builder even though there is no app-selectable outbound to materialize.
    return parseResult.format == SubscriptionFormat.singboxConfig ||
        parseResult.format == SubscriptionFormat.hydraboxV1;
  }

  static void _validateHydraBoxSource(ParseResult parseResult) {
    if (parseResult.format != SubscriptionFormat.hydraboxV1) {
      return;
    }
    HydraBoxSubscriptionTimePolicy.validate(parseResult.sourceMetadata);
  }

  static void _validateHydraBoxRefresh(
    Subscription existing,
    ParseResult incoming,
  ) {
    _validateHydraBoxSource(incoming);
    if (existing.sourceMetadata['format'] == 'hydrabox.io/subscription/v1' &&
        incoming.format != SubscriptionFormat.hydraboxV1) {
      throw const FormatException(
        'Refusing to replace a HydraBox subscription with a legacy format',
      );
    }
    _validateHydraBoxMetadataTransition(
      existing.sourceMetadata,
      incoming.sourceMetadata,
    );
  }

  static void _validateHydraBoxMetadataTransition(
    Map<String, dynamic> oldMetadata,
    Map<String, dynamic> next,
  ) {
    if (oldMetadata['format'] != 'hydrabox.io/subscription/v1') {
      return;
    }
    if (next['format'] != 'hydrabox.io/subscription/v1') {
      throw const FormatException(
        'Refusing to replace a HydraBox subscription with a legacy format',
      );
    }
    for (final key in const ['issuer', 'subscription_id', 'channel']) {
      if (oldMetadata[key]?.toString() != next[key]?.toString()) {
        throw FormatException(
          'HydraBox refresh changed trusted identity field "$key"',
        );
      }
    }
    if (oldMetadata['encrypted'] == true && next['encrypted'] != true) {
      throw const FormatException(
        'Refusing encrypted-to-plaintext HydraBox downgrade',
      );
    }
    final oldSequence = (oldMetadata['sequence'] as num?)?.toInt() ?? -1;
    final nextSequence = (next['sequence'] as num?)?.toInt() ?? -1;
    if (nextSequence < oldSequence) {
      throw FormatException(
        'HydraBox sequence rollback: $nextSequence < $oldSequence',
      );
    }
    if (nextSequence == oldSequence &&
        oldMetadata['payload_sha256']?.toString() !=
            next['payload_sha256']?.toString()) {
      throw const FormatException(
        'HydraBox publisher equivocation: same sequence, different payload',
      );
    }
  }

  static Future<void> _reconcileStoredHydraBoxTrustTuples() async {
    final groups = <String, List<({String id, Subscription subscription})>>{};
    for (final rawKey in _metaStore.keys) {
      if (rawKey == _storageSchemaVersionKey || rawKey is! String) continue;
      final subscription = _readMetadata(rawKey);
      if (subscription == null) continue;
      final tupleKey = _hydraBoxTrustTupleKey(subscription.sourceMetadata);
      if (tupleKey == null) continue;
      groups
          .putIfAbsent(
            tupleKey,
            () => <({String id, Subscription subscription})>[],
          )
          .add((id: rawKey, subscription: subscription));
    }

    var changed = false;
    var blockedCount = 0;
    for (final entries in groups.values) {
      entries.sort((left, right) => left.id.compareTo(right.id));
      String? winnerId;
      var blockReason = 'duplicate_tuple';
      if (entries.length == 1) {
        winnerId = entries.single.id;
      } else {
        final encryptedCandidates = entries
            .where(
              (entry) => entry.subscription.sourceMetadata['encrypted'] == true,
            )
            .toList(growable: false);
        final candidates = encryptedCandidates.isNotEmpty
            ? encryptedCandidates
            : entries;
        final highestSequence = candidates
            .map(
              (entry) =>
                  _storedHydraBoxSequence(entry.subscription.sourceMetadata),
            )
            .reduce((left, right) => left > right ? left : right);
        final highest = candidates
            .where(
              (entry) =>
                  _storedHydraBoxSequence(entry.subscription.sourceMetadata) ==
                  highestSequence,
            )
            .toList(growable: false);
        final highestDigests = highest
            .map(
              (entry) =>
                  _storedHydraBoxDigest(entry.subscription.sourceMetadata),
            )
            .toSet();
        if (highestDigests.length == 1) {
          winnerId = highest.first.id;
        } else {
          blockReason = 'publisher_equivocation';
        }
      }

      for (final entry in entries) {
        final shouldBlock = winnerId == null || entry.id != winnerId;
        final sourceMetadata = Map<String, dynamic>.from(
          entry.subscription.sourceMetadata,
        );
        final wasBlocked = sourceMetadata['trust_blocked'] == true;
        final previousReason = sourceMetadata['trust_block_reason']?.toString();
        if (shouldBlock) {
          sourceMetadata['trust_blocked'] = true;
          sourceMetadata['trust_block_reason'] = blockReason;
          blockedCount++;
        } else {
          sourceMetadata.remove('trust_blocked');
          sourceMetadata.remove('trust_block_reason');
        }
        if (wasBlocked == shouldBlock &&
            (!shouldBlock || previousReason == blockReason)) {
          continue;
        }
        final updated = entry.subscription.copyWith(
          sourceMetadata: sourceMetadata,
        );
        await _metaStore.put(entry.id, jsonEncode(updated.toMetadataMap()));
        changed = true;
      }
    }
    if (changed) {
      await _metaStore.flush();
      AppLogStore.warning(
        'subscription trust',
        'Reconciled stored HydraBox trust tuples; blocked=$blockedCount',
      );
    }
  }

  static void _validateHydraBoxTupleAgainstStoredMetadata({
    required String subscriptionId,
    required Map<String, dynamic> proposed,
  }) {
    final tupleKey = _hydraBoxTrustTupleKey(proposed);
    final proposedSequence = proposed['sequence'];
    final proposedDigest = proposed['payload_sha256'];
    if (tupleKey == null ||
        proposedSequence is! int ||
        proposedSequence < 0 ||
        proposedSequence > 9007199254740991 ||
        proposedDigest is! String ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(proposedDigest) ||
        proposed['encrypted'] is! bool) {
      throw const FormatException('Invalid HydraBox durable trust metadata');
    }

    var highestSequence = -1;
    final highestDigests = <String>{};
    var encryptionWasRequired = false;
    String? activeDuplicateId;
    for (final rawKey in _metaStore.keys) {
      if (rawKey == _storageSchemaVersionKey || rawKey is! String) continue;
      final stored = _readMetadata(rawKey);
      if (stored == null ||
          _hydraBoxTrustTupleKey(stored.sourceMetadata) != tupleKey) {
        continue;
      }
      final storedMetadata = stored.sourceMetadata;
      encryptionWasRequired =
          encryptionWasRequired || storedMetadata['encrypted'] == true;
      final storedSequence = _storedHydraBoxSequence(storedMetadata);
      final storedDigest = _storedHydraBoxDigest(storedMetadata);
      if (storedSequence > highestSequence) {
        highestSequence = storedSequence;
        highestDigests
          ..clear()
          ..add(storedDigest);
      } else if (storedSequence == highestSequence) {
        highestDigests.add(storedDigest);
      }
      if (rawKey != subscriptionId && storedMetadata['trust_blocked'] != true) {
        activeDuplicateId ??= rawKey;
      }
    }

    if (encryptionWasRequired && proposed['encrypted'] != true) {
      throw const FormatException(
        'Refusing encrypted-to-plaintext HydraBox downgrade',
      );
    }
    if (proposedSequence < highestSequence) {
      throw FormatException(
        'HydraBox sequence rollback: $proposedSequence < $highestSequence',
      );
    }
    if (proposedSequence == highestSequence &&
        (highestDigests.length != 1 ||
            !highestDigests.contains(proposedDigest))) {
      throw const FormatException(
        'HydraBox publisher equivocation: same sequence, different payload',
      );
    }
    if (activeDuplicateId != null) {
      throw const FormatException(
        'This HydraBox publisher/subscription/channel tuple is already stored',
      );
    }
  }

  static String? _hydraBoxTrustTupleKey(Map<String, dynamic> metadata) {
    if (metadata['format'] != 'hydrabox.io/subscription/v1') return null;
    final issuer = metadata['issuer'];
    final subscriptionId = metadata['subscription_id'];
    final channel = metadata['channel'];
    if (issuer is! String ||
        issuer.isEmpty ||
        subscriptionId is! String ||
        subscriptionId.isEmpty ||
        channel is! String ||
        channel.isEmpty) {
      return null;
    }
    return jsonEncode(<String>[issuer, subscriptionId, channel]);
  }

  static int _storedHydraBoxSequence(Map<String, dynamic> metadata) {
    final value = metadata['sequence'];
    if (value is int && value >= 0 && value <= 9007199254740991) {
      return value;
    }
    // Corrupt durable trust state must fail closed instead of lowering the
    // remembered high-water mark.
    return 9007199254740991;
  }

  static String _storedHydraBoxDigest(Map<String, dynamic> metadata) {
    final value = metadata['payload_sha256'];
    if (value is String && RegExp(r'^[0-9a-f]{64}$').hasMatch(value)) {
      return value;
    }
    return '<invalid-digest>';
  }

  /// Converts parsed outbound configs into [Outbound] model objects.
  static List<Outbound> _buildOutbounds(
    List<Map<String, dynamic>> parsedConfigs,
  ) {
    final payload = _buildOutboundPayload(parsedConfigs);
    _logBuildWarningEntries(payload.warnings);
    return payload.outbounds
        .map((entry) => Outbound.fromMap(entry))
        .toList(growable: false);
  }

  static Future<
    ({
      List<Outbound> outbounds,
      List<SubscriptionGroup> groups,
      List<SubscriptionProfile> profiles,
    })
  >
  _buildSubscriptionPayloadAsync(
    ParseResult parseResult, {
    String? providerName,
  }) async {
    final normalizedConfigs = parseResult.outbounds
        .map((entry) => Map<String, dynamic>.from(entry))
        .toList(growable: false);
    final normalizedGroups = parseResult.groups
        .map((entry) => entry.toMap())
        .toList(growable: false);
    final payload = Map<String, dynamic>.from(
      await compute(_buildSubscriptionPayloadWorker, {
        'outbounds': normalizedConfigs,
        'groups': normalizedGroups,
        'provider_name': ?providerName,
      }),
    );
    _logBuildWarningEntries(payload['warnings'] as List? ?? const []);
    final outbounds = (payload['outbounds'] as List? ?? const [])
        .map(
          (entry) => Outbound.fromMap(Map<String, dynamic>.from(entry as Map)),
        )
        .toList(growable: false);
    final groups = (payload['groups'] as List? ?? const [])
        .map(
          (entry) => SubscriptionGroup.fromMap(
            Map<String, dynamic>.from(entry as Map),
          ),
        )
        .where((group) => group.outboundTags.isNotEmpty)
        .toList(growable: false);
    _validateHydraBoxRuntimeTagIdentity(parseResult, outbounds);
    final profiles = _resolveHydraBoxProfiles(parseResult.profiles, outbounds);
    return (outbounds: outbounds, groups: groups, profiles: profiles);
  }

  static void _validateHydraBoxRuntimeTagIdentity(
    ParseResult parseResult,
    List<Outbound> outbounds,
  ) {
    if (parseResult.format != SubscriptionFormat.hydraboxV1) {
      return;
    }
    final seen = <String>{};
    for (final outbound in outbounds) {
      final sourceSection =
          outbound.config['_etonify_source_index_section']?.toString() ??
          outbound.config['_etonify_source_section']?.toString() ??
          '';
      if (sourceSection != 'outbounds' && sourceSection != 'endpoints') {
        continue;
      }
      final originalTag =
          outbound.config['_etonify_original_tag']?.toString() ?? '';
      final projectedConfigTag = outbound.config['tag']?.toString() ?? '';
      if (originalTag.isEmpty ||
          originalTag != originalTag.trim() ||
          outbound.tag != originalTag ||
          projectedConfigTag != originalTag ||
          !seen.add('$sourceSection\u0000$originalTag')) {
        throw FormatException(
          'HydraBox native runtime tag identity changed during import; '
          'opaque native references cannot be rewritten safely',
        );
      }
    }
  }

  static List<SubscriptionProfile> _resolveHydraBoxProfiles(
    List<HydraBoxParsedProfile> parsedProfiles,
    List<Outbound> outbounds,
  ) {
    if (parsedProfiles.isEmpty) {
      return const [];
    }
    final resolved = <SubscriptionProfile>[];
    for (final profile in parsedProfiles) {
      final matches = outbounds
          .where((outbound) {
            final sourceSection =
                outbound.config['_etonify_source_index_section']?.toString() ??
                outbound.config['_etonify_source_section']?.toString() ??
                '';
            final sourceTag =
                outbound.config['_etonify_original_tag']?.toString() ?? '';
            return sourceSection == profile.entrypointSection &&
                sourceTag == profile.entrypointTag;
          })
          .toList(growable: false);
      if (matches.length != 1) {
        throw FormatException(
          'HydraBox profile "${profile.id}" entrypoint did not resolve '
          'exactly once after normalization',
        );
      }
      resolved.add(
        SubscriptionProfile(
          id: profile.id,
          name: profile.name,
          entrypointSection: profile.entrypointSection,
          entrypointTag: profile.entrypointTag,
          runtimeTag: matches.single.tag,
          enabled: profile.enabled,
          country: profile.country,
          metadata: profile.metadata,
        ),
      );
    }
    return resolved;
  }

  static SubscriptionProfile? _preferredHydraBoxProfile(
    List<SubscriptionProfile> profiles, {
    String? preferredId,
    String? preferredRuntimeTag,
    String? defaultId,
  }) {
    final enabled = profiles.where((profile) => profile.enabled);
    for (final id in [preferredId, defaultId]) {
      final normalized = id?.trim() ?? '';
      if (normalized.isEmpty) continue;
      for (final profile in enabled) {
        if (profile.id == normalized) return profile;
      }
    }
    final preferredTag = preferredRuntimeTag?.trim() ?? '';
    if (preferredTag.isNotEmpty) {
      for (final profile in enabled) {
        if (profile.runtimeTag == preferredTag) return profile;
      }
    }
    return enabled.firstOrNull;
  }

  static ({
    List<Map<String, dynamic>> outbounds,
    List<Map<String, dynamic>> groups,
    List<String> warnings,
  })
  _buildOutboundPayload(
    List<Map<String, dynamic>> parsedConfigs, [
    List<Map<String, dynamic>> parsedGroups = const [],
    String? providerName,
  ]) {
    final lagomProfile = _looksLikeLagomProviderName(providerName);
    final buildConfigs = lagomProfile
        ? _normalizeLagomConfigs(parsedConfigs)
        : parsedConfigs;
    final buildGroups = lagomProfile
        ? _normalizeLagomGroups(buildConfigs, parsedGroups)
        : parsedGroups;
    final outbounds = <Outbound>[];
    final groups = <SubscriptionGroup>[];
    final warnings = <String>[];
    final usedTags = <String>{};
    final sourceScopeToTagToTags = <String, Map<String, List<String>>>{};

    for (var i = 0; i < buildConfigs.length; i++) {
      final config = Map<String, dynamic>.from(buildConfigs[i]);

      // Extract and remove the _name meta field
      final rawName = (config.remove('_name') ?? 'Proxy ${i + 1}') as String;
      final sourceTag = config.remove('_source_tag')?.toString().trim() ?? '';
      final sourceScope =
          config.remove('_source_scope')?.toString().trim() ?? '';
      final detourSourceTag =
          config.remove('_detour_source_tag')?.toString().trim() ?? '';
      config.remove('_source_profile_name');
      final coreSourceSection =
          config['_etonify_source_section']?.toString().trim() ?? '';
      final originalCoreTag =
          config['_etonify_original_tag']?.toString().trim() ?? '';
      final countryOverride = _normalizeCountryCode(
        config.remove('_country_override')?.toString(),
      );
      final parsedName = _extractCountryFromName(rawName);
      final name = parsedName.name;

      final validationError = ParsedOutboundSchema.validate(config);
      if (validationError != null) {
        warnings.add('Skipping outbound "$name": $validationError');
        continue;
      }

      // Generate a unique tag
      final type = (config['type'] ?? 'proxy') as String;
      var tag = _uniqueGeneratedTag('$type-$i', usedTags);
      final isCoreConfigEntry =
          coreSourceSection == 'outbounds' || coreSourceSection == 'endpoints';
      if (isCoreConfigEntry &&
          originalCoreTag.isNotEmpty &&
          !usedTags.contains(originalCoreTag) &&
          !isReservedProxyTag(originalCoreTag)) {
        // Cross-references in full sing-box configs are tag-based. Keep the
        // exact native tag whenever it does not collide with app-owned tags.
        tag = originalCoreTag;
      } else {
        // Try to use name-based tag for link/Clash/Xray imports and as a safe
        // collision fallback for full core configs.
        final sanitized = _sanitizeTag(name);
        if (sanitized.isNotEmpty &&
            !usedTags.contains(sanitized) &&
            !isReservedProxyTag(sanitized)) {
          tag = sanitized;
        }
      }
      usedTags.add(tag);
      if (sourceTag.isNotEmpty) {
        sourceScopeToTagToTags
            .putIfAbsent(sourceScope, () => <String, List<String>>{})
            .putIfAbsent(sourceTag, () => <String>[])
            .add(tag);
      }
      if (detourSourceTag.isNotEmpty) {
        final resolvedDetourTags =
            sourceScopeToTagToTags[sourceScope]?[detourSourceTag] ??
            const <String>[];
        if (resolvedDetourTags.isNotEmpty) {
          config['detour'] = resolvedDetourTags.last;
        } else {
          warnings.add('Skipping outbound "$name": missing chain detour');
          continue;
        }
      }

      // Set the tag in the config
      config['tag'] = tag;

      outbounds.add(
        Outbound(
          tag: tag,
          name: name,
          config: config,
          info: OutboundInfo(
            country: countryOverride ?? parsedName.countryCode,
          ),
        ),
      );
    }

    for (var i = 0; i < buildGroups.length; i++) {
      final group = ParsedOutboundGroup.fromMap(buildGroups[i]);
      final sourceTagToTags =
          sourceScopeToTagToTags[group.sourceScope] ??
          (group.sourceScope.isEmpty
              ? _mergeSourceTagScopes(sourceScopeToTagToTags.values)
              : const <String, List<String>>{});
      final memberTags = <String>[];
      final seenMembers = <String>{};
      for (final sourceTag in group.sourceOutboundTags) {
        final resolvedTags = sourceTagToTags[sourceTag] ?? const <String>[];
        for (final resolvedTag in resolvedTags) {
          if (seenMembers.add(resolvedTag)) {
            memberTags.add(resolvedTag);
          }
        }
      }
      if (memberTags.length < 2) {
        continue;
      }

      final rawGroupName = group.name.trim().isNotEmpty
          ? group.name.trim()
          : 'Proxy group ${groups.length + 1}';
      final parsedGroupName = _extractCountryFromName(rawGroupName);
      final groupName = parsedGroupName.name.trim().isNotEmpty
          ? parsedGroupName.name.trim()
          : 'Proxy group ${groups.length + 1}';
      final groupCountry =
          _normalizeCountryCode(group.countryCode) ??
          parsedGroupName.countryCode;
      var tag = _uniqueTag(
        lagomProfile &&
                group.sourceTag.trim().toLowerCase() == _lagomWhitelistDetourTag
            ? _lagomWhitelistDetourTag
            : _groupTagSeed(group.sourceTag, groupName, groups.length),
        usedTags,
      );
      if (isReservedProxyTag(tag)) {
        tag = _uniqueTag('group-${groups.length + 1}', usedTags);
      }
      usedTags.add(tag);
      groups.add(
        SubscriptionGroup(
          tag: tag,
          name: groupName,
          type: group.type.trim().isEmpty ? 'urltest' : group.type.trim(),
          country: groupCountry,
          outboundTags: memberTags,
          urlTestConfig: UrlTestConfig(
            url: group.url,
            method: group.method,
            intervalSeconds: group.intervalSeconds,
            timeoutSeconds: group.timeoutSeconds,
            concurrency: group.concurrency,
            unavailableCheckIntervalSeconds:
                group.unavailableCheckIntervalSeconds,
          ),
        ),
      );
    }

    return (
      outbounds: outbounds
          .map((entry) => entry.toMap())
          .toList(growable: false),
      groups: groups.map((entry) => entry.toMap()).toList(growable: false),
      warnings: warnings,
    );
  }

  static String _uniqueGeneratedTag(String candidate, Set<String> usedTags) {
    var tag = candidate;
    var suffix = 2;
    while (usedTags.contains(tag) || isReservedProxyTag(tag)) {
      tag = '$candidate-$suffix';
      suffix++;
    }
    return tag;
  }

  static Map<String, List<String>> _mergeSourceTagScopes(
    Iterable<Map<String, List<String>>> scopes,
  ) {
    final merged = <String, List<String>>{};
    for (final scope in scopes) {
      for (final entry in scope.entries) {
        merged.putIfAbsent(entry.key, () => <String>[]).addAll(entry.value);
      }
    }
    return merged;
  }

  static String _groupTagSeed(String sourceTag, String name, int groupIndex) {
    final source = sourceTag.trim().isNotEmpty ? sourceTag : name;
    final sanitized = _sanitizeTag(source);
    return sanitized.isNotEmpty ? 'group-$sanitized' : 'group-$groupIndex';
  }

  static String _uniqueTag(String seed, Set<String> usedTags) {
    final sanitized = _sanitizeTag(seed);
    var tag = sanitized.isEmpty ? 'proxy' : sanitized;
    if (!usedTags.contains(tag)) {
      return tag;
    }
    var suffix = 2;
    while (usedTags.contains('$tag-$suffix')) {
      suffix++;
    }
    return '$tag-$suffix';
  }

  static String _sanitizeTag(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9-]'), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
  }

  static bool likelyRequiresHwidEnable(Subscription subscription) {
    final info = subscription.info;
    if (info?.requireHwid == true) {
      return false;
    }
    final visibleOutbounds = subscription.outbounds
        .where((outbound) => !outbound.info.deleted)
        .where((outbound) => outbound.config['_group_only'] != true)
        .toList(growable: false);
    if (visibleOutbounds.length != 1) {
      return false;
    }
    final outboundName = visibleOutbounds.first.name.trim().toLowerCase();
    final subscriptionName = subscription.name.trim().toLowerCase();
    final title = info?.title?.trim().toLowerCase() ?? '';
    return _looksLikeHwidMarker(outboundName) ||
        _looksLikeHwidMarker(subscriptionName) ||
        _looksLikeHwidMarker(title);
  }

  static void _logLikelyHwidWarning(Subscription subscription) {
    if (!likelyRequiresHwidEnable(subscription)) {
      return;
    }
    AppLogStore.warning(
      'subscription',
      'Subscription "${subscription.name}" looks like it requires HWID. '
          'Only one outbound was returned and its name/title mentions app or HWID.',
    );
  }

  static bool _looksLikeHwidMarker(String value) {
    if (value.isEmpty) {
      return false;
    }
    if (value.contains('hwid')) {
      return true;
    }
    return RegExp(r'(^|[^a-z])app([^a-z]|$)').hasMatch(value);
  }

  /// Preserves user state only when the provider identity still matches.
  ///
  /// Removed provider keys are dropped from the active payload. Historical
  /// storage should not keep secrets in soft-deleted active outbounds.
  static List<Outbound> _preserveUserState(
    List<Outbound> oldOutbounds,
    List<Outbound> newOutbounds,
  ) {
    final oldByTag = <String, Outbound>{};
    final oldByKey = <String, List<Outbound>>{};
    for (final ob in oldOutbounds) {
      oldByTag[ob.tag] = ob;
      final key = _outboundKey(ob.config);
      oldByKey.putIfAbsent(key, () => <Outbound>[]).add(ob);
    }

    final newKeyCounts = <String, int>{};
    for (final ob in newOutbounds) {
      final key = _outboundKey(ob.config);
      newKeyCounts[key] = (newKeyCounts[key] ?? 0) + 1;
    }

    final merged = newOutbounds
        .map((ob) {
          final key = _outboundKey(ob.config);
          final exactOldOutbound = oldByTag[ob.tag];
          final oldMatches = oldByKey[key] ?? const <Outbound>[];
          final exactOldKeyMatches =
              exactOldOutbound != null &&
              _outboundKey(exactOldOutbound.config) == key;
          final oldOutbound =
              (exactOldKeyMatches ? exactOldOutbound : null) ??
              (oldMatches.length == 1 && newKeyCounts[key] == 1
                  ? oldMatches.single
                  : null);
          final oldInfo = oldOutbound?.info;
          if (oldInfo != null) {
            final canCarryEndpointState =
                oldMatches.length == 1 && newKeyCounts[key] == 1;
            return ob.copyWith(
              info: ob.info.copyWith(
                checked: oldInfo.checked,
                deleted: false,
                externalIp: canCarryEndpointState ? oldInfo.externalIp : null,
                country:
                    ob.info.country ??
                    (canCarryEndpointState ? oldInfo.country : null),
                exitCountry: canCarryEndpointState ? oldInfo.exitCountry : null,
                latestPing: canCarryEndpointState ? oldInfo.latestPing : null,
              ),
            );
          }
          return ob;
        })
        .toList(growable: false);

    return merged;
  }

  @visibleForTesting
  static List<Outbound> preserveUserStateForTest(
    List<Outbound> oldOutbounds,
    List<Outbound> newOutbounds,
  ) => _preserveUserState(oldOutbounds, newOutbounds);

  @visibleForTesting
  static ({String name, String? countryCode}) extractCountryFromNameForTest(
    String rawName,
  ) => _extractCountryFromName(rawName);

  static String? inferCountryCodeFromName(String rawName) =>
      _extractCountryFromName(rawName).countryCode;

  @visibleForTesting
  static List<Outbound> buildOutboundsForTest(
    List<Map<String, dynamic>> parsedConfigs,
  ) => _buildOutbounds(parsedConfigs);

  @visibleForTesting
  static Future<void> saveParsedImportForTest(Subscription subscription) =>
      _saveParsedImport(subscription);

  @visibleForTesting
  static String selectedProxyTagForOutboundsForTest(
    List<Outbound> outbounds, {
    String? preferredTag,
    List<SubscriptionGroup> groups = const [],
  }) => _selectedProxyTagForOutbounds(
    outbounds,
    preferredTag: preferredTag,
    groups: groups,
  );

  @visibleForTesting
  static ({
    List<Map<String, dynamic>> outbounds,
    List<Map<String, dynamic>> groups,
    List<String> warnings,
  })
  buildSubscriptionPayloadForTest(
    ParseResult parseResult, {
    String? providerName,
  }) {
    return _buildOutboundPayload(
      parseResult.outbounds,
      parseResult.groups.map((group) => group.toMap()).toList(growable: false),
      providerName,
    );
  }

  static bool isLocalFileImportUrl(String url) {
    return url.trim().startsWith('$_localFileImportScheme://');
  }

  static String _safeSubscriptionUrlForLog(String value) {
    try {
      final uri = SubscriptionFetcher.parseRequestUri(value);
      final redacted = HydraBoxJweCodec.uriWithoutSecretFragment(uri);
      final scheme = redacted.scheme.toLowerCase();
      if (scheme.isEmpty || redacted.host.isEmpty) {
        return '<subscription-source>';
      }
      final host = redacted.host.contains(':')
          ? '[${redacted.host}]'
          : redacted.host;
      final port = redacted.hasPort
          ? redacted.port
          : switch (scheme) {
              'https' => 443,
              'http' => 80,
              _ => 0,
            };
      return port == 0 ? '$scheme://$host' : '$scheme://$host:$port';
    } catch (_) {
      return '<invalid-subscription-url>';
    }
  }

  static bool _subscriptionUrlHasHydraBoxKey(String value) {
    try {
      return HydraBoxJweCodec.hasKeyFragment(
        SubscriptionFetcher.parseRequestUri(value),
      );
    } catch (_) {
      return false;
    }
  }

  static bool _subscriptionUrlHasHydraBoxKeyQuery(String value) {
    try {
      return HydraBoxJweCodec.hasKeyQueryParameter(
        SubscriptionFetcher.parseRequestUri(value),
      );
    } catch (_) {
      return false;
    }
  }

  static void _validatePersistentSourcePolicy(Subscription subscription) {
    if (_subscriptionUrlHasHydraBoxKeyQuery(subscription.url)) {
      throw const FormatException(
        'HydraBox hbx-key is allowed only in the URI fragment',
      );
    }
    if (!Platform.isAndroid &&
        _subscriptionUrlHasHydraBoxKey(subscription.url)) {
      throw UnsupportedError(
        'Persistent hbx-key subscriptions require Android '
        'Keystore-backed storage',
      );
    }
  }

  static void _assertStoredSourcePolicies() {
    for (final key in _metaStore.keys) {
      if (key == _storageSchemaVersionKey) continue;
      final raw = _metaStore.get(key);
      if (raw is! String) continue;
      try {
        final map = jsonDecode(raw) as Map<String, dynamic>;
        final url = map['url']?.toString() ?? '';
        if (_subscriptionUrlHasHydraBoxKeyQuery(url)) {
          throw UnsupportedError(
            'Stored HydraBox hbx-key must not appear in a URL query',
          );
        }
        if (!Platform.isAndroid && _subscriptionUrlHasHydraBoxKey(url)) {
          throw UnsupportedError(
            'Refusing plaintext persistence of an hbx-key subscription on '
            'this platform',
          );
        }
      } on UnsupportedError {
        rethrow;
      } catch (_) {
        // Corrupt unrelated metadata is skipped by normal reads as well.
      }
    }
  }

  static String? localFileImportDisplayName(String url) {
    if (!isLocalFileImportUrl(url)) {
      return null;
    }
    final trimmed = url.trim();
    final encoded = trimmed.substring('$_localFileImportScheme://'.length);
    final decoded = Uri.decodeComponent(encoded).trim();
    return decoded.isEmpty ? null : decoded;
  }

  static int _nextSortOrder() {
    final subscriptions = getAllMetadata();
    if (subscriptions.isEmpty) {
      return 0;
    }
    var maxOrder = -1;
    for (final subscription in subscriptions) {
      final order = subscription.sortOrder;
      if (order != null && order > maxOrder) {
        maxOrder = order;
      }
    }
    return maxOrder >= 0 ? maxOrder + 1 : subscriptions.length;
  }

  static Future<void> _saveOrdered(List<Subscription> subscriptions) async {
    for (var i = 0; i < subscriptions.length; i++) {
      final id = subscriptions[i].id;
      await _withSubscriptionMutationLock(id, () async {
        final current = _readMetadata(id);
        if (current == null) return;
        // The caller's list may have been captured before a refresh. Preserve
        // every current trust/payload field and change only the ordering value.
        await _saveMetadataUnlocked(current.copyWith(sortOrder: i));
      });
    }
  }

  static void _logBuildWarningEntries(List<dynamic> warnings) {
    for (final entry in warnings) {
      final message = entry.toString().trim();
      if (message.isNotEmpty) {
        AppLogStore.warning('subscription', message);
      }
    }
  }

  static Subscription _withPayload(Subscription metadata) {
    final raw = _payloadStore.get(_payloadKeyForMetadata(metadata));
    if (raw is! String) {
      return metadata;
    }
    return _withPayloadFromRaw(metadata, raw);
  }

  static Subscription? _readMetadata(String id) {
    if (!isSafeSubscriptionStorageId(id)) {
      return null;
    }
    final raw = _metaStore.get(id);
    if (raw is! String) return null;
    try {
      final subscription = Subscription.fromMetadataMap(
        jsonDecode(raw) as Map<String, dynamic>,
      );
      if (subscription.id != id ||
          !isSafeSubscriptionStorageId(subscription.id)) {
        return null;
      }
      return subscription;
    } catch (_) {
      return null;
    }
  }

  static String _payloadKeyForMetadata(Subscription metadata) {
    if (!isSafeSubscriptionStorageId(metadata.id)) {
      return '';
    }
    final candidate = metadata.payloadStorageKey.trim();
    final expectedPrefix = '${metadata.id}$_payloadGenerationSeparator';
    if (candidate.startsWith(expectedPrefix) &&
        candidate.length > expectedPrefix.length) {
      return candidate;
    }
    return metadata.id;
  }

  static void _ensureSubscriptionUnchanged({
    required Subscription current,
    required String expectedPayloadKey,
    String? expectedUrl,
    required String operation,
  }) {
    final currentPayloadKey = _payloadKeyForMetadata(current);
    if (currentPayloadKey != expectedPayloadKey ||
        (expectedUrl != null && current.url != expectedUrl)) {
      throw StateError(
        'Subscription ${current.id} changed while $operation; retry with the '
        'latest revision',
      );
    }
  }

  static Subscription _withPayloadFromRaw(Subscription metadata, String raw) {
    try {
      final map = jsonDecode(_decodeStoredPayload(raw)) as Map<String, dynamic>;
      return metadata.copyWith(
        rawContent: map['raw_content'] as String? ?? '',
        outbounds:
            (map['outbounds'] as List?)
                ?.map(
                  (entry) =>
                      Outbound.fromMap(Map<String, dynamic>.from(entry as Map)),
                )
                .toList() ??
            const [],
        groups:
            (map['groups'] as List?)
                ?.map(
                  (entry) => SubscriptionGroup.fromMap(
                    Map<String, dynamic>.from(entry as Map),
                  ),
                )
                .where((group) => group.tag.isNotEmpty)
                .toList() ??
            const [],
        profiles:
            (map['profiles'] as List?)
                ?.map(
                  (entry) => SubscriptionProfile.fromMap(
                    Map<String, dynamic>.from(entry as Map),
                  ),
                )
                .where((profile) => profile.id.isNotEmpty)
                .toList(growable: false) ??
            const [],
        nativeConfig: map['native_config'] is Map
            ? Map<String, dynamic>.from(map['native_config'] as Map)
            : null,
        clearNativeConfig: map['native_config'] is! Map,
        sourceMetadata: <String, dynamic>{
          ...Map<String, dynamic>.from(
            map['source_metadata'] as Map? ?? const {},
          ),
          // Durable trust state is authoritative over the immutable payload
          // copy. This preserves startup reconciliation blocks while retaining
          // opaque payload-only extension metadata.
          ...metadata.sourceMetadata,
        },
      );
    } catch (_) {
      return metadata;
    }
  }

  static Future<void> _migrateLegacyData() async {
    final updatedMetadata = <dynamic, String>{};
    final updatedPayloads = <dynamic, String>{};

    for (final key in _metaStore.keys) {
      final raw = _metaStore.get(key);
      if (raw is! String) {
        continue;
      }
      try {
        final map = jsonDecode(raw) as Map<String, dynamic>;
        final hasEmbeddedPayload =
            map.containsKey('raw_content') || map.containsKey('outbounds');
        if (!hasEmbeddedPayload) {
          continue;
        }
        final subscription = Subscription.fromMap(map);
        if (!isSafeSubscriptionStorageId(subscription.id)) {
          continue;
        }
        _validatePersistentSourcePolicy(subscription);
        updatedMetadata[subscription.id] = jsonEncode(
          subscription.toMetadataMap(),
        );
        updatedPayloads[subscription.id] = jsonEncode(
          subscription.toPayloadMap(),
        );
      } on UnsupportedError {
        rethrow;
      } catch (_) {
        // Leave corrupt legacy entries untouched so they can still be inspected.
      }
    }

    if (updatedPayloads.isNotEmpty) {
      await _payloadStore.putAll(updatedPayloads);
      await _payloadStore.flush();
    }
    // Metadata is destructive here because it removes the only embedded copy
    // of the payload. Switch it only after the split payload is durable.
    if (updatedMetadata.isNotEmpty) {
      await _metaStore.putAll(updatedMetadata);
      await _metaStore.flush();
    }
  }

  static Future<void> _cleanupLegacySummaryBox() async {
    if (Hive.isBoxOpen(_legacySummaryBoxName)) {
      await Hive.box(_legacySummaryBoxName).close();
    }
    if (!await Hive.boxExists(_legacySummaryBoxName)) {
      return;
    }
    // This cache is obsolete. Opening it would decode every legacy summary
    // before clearing it, which is especially expensive for huge profiles.
    await Hive.deleteBoxFromDisk(_legacySummaryBoxName);
  }

  /// Creates a lookup key from outbound config for matching across refreshes.
  static String _outboundKey(Map<String, dynamic> config) {
    final identity = <String, dynamic>{
      for (final key in const <String>[
        'type',
        'server',
        'server_port',
        'uuid',
        'password',
        'username',
        'method',
        'security',
        'flow',
        'network',
        'packet_encoding',
        'plugin',
        'plugin_opts',
        'obfs',
        'obfs-password',
        'tls',
        'transport',
        'multiplex',
      ])
        if (config.containsKey(key))
          key: _stableOutboundIdentityValue(config[key]),
    };
    return jsonEncode(_stableOutboundIdentityValue(identity));
  }

  static dynamic _stableOutboundIdentityValue(dynamic value) {
    if (value is Map) {
      final result = <String, dynamic>{};
      final entries =
          value.entries
              .map((entry) => MapEntry(entry.key.toString(), entry.value))
              .toList(growable: false)
            ..sort((a, b) => a.key.compareTo(b.key));
      for (final entry in entries) {
        result[entry.key] = _stableOutboundIdentityValue(entry.value);
      }
      return result;
    }
    if (value is Iterable) {
      return value.map(_stableOutboundIdentityValue).toList(growable: false);
    }
    return value;
  }

  /// Extracts a sensible name from a URL.
  static String _nameFromUrl(String url) {
    if (localFileImportDisplayName(url) case final displayName?) {
      return displayName;
    }
    try {
      final uri = SubscriptionFetcher.parseRequestUri(url);
      return uri.host.isNotEmpty ? uri.host : 'Subscription';
    } catch (_) {
      final match = RegExp(
        r'^[A-Za-z][A-Za-z0-9+.\-]*:\/\/(?:[^\/?#@]+@)?([^\/?#:]+)',
      ).firstMatch(url.trim());
      final host = match?.group(1)?.trim();
      if (host != null && host.isNotEmpty) {
        return host;
      }
      return 'Subscription';
    }
  }

  static String _localFileImportUrl(String sourceName) {
    return '$_localFileImportScheme://${Uri.encodeComponent(sourceName)}';
  }

  static String? _providerNameHint({
    required String? customName,
    required String? headerTitle,
  }) {
    final parts = [?_normalizeName(customName), ?_normalizeName(headerTitle)];
    return parts.isEmpty ? null : parts.join(' ');
  }

  static String _pickSubscriptionName({
    required String? customName,
    required String? headerTitle,
    required List<Outbound> outbounds,
    required String url,
  }) {
    final normalizedCustom = _normalizeName(customName);
    if (normalizedCustom != null) {
      return normalizedCustom;
    }

    final normalizedHeader = _normalizeName(headerTitle);
    if (normalizedHeader != null) {
      return normalizedHeader;
    }

    final outboundName = _nameFromOutbounds(outbounds);
    if (outboundName != null) {
      return outboundName;
    }

    return _nameFromUrl(url);
  }

  static String? _nameFromOutbounds(List<Outbound> outbounds) {
    String? genericFallback;
    for (final outbound in outbounds) {
      final normalized = _normalizeName(outbound.name);
      if (normalized == null) {
        continue;
      }
      if (!_looksGenericName(normalized)) {
        return normalized;
      }
      genericFallback ??= normalized;
    }
    for (final outbound in outbounds) {
      final server = _normalizeName(outbound.server);
      if (server != null) {
        return server;
      }
    }
    if (genericFallback != null) {
      return genericFallback;
    }
    for (final outbound in outbounds) {
      final type = outbound.type.trim();
      if (type.isNotEmpty) {
        return type.toUpperCase();
      }
    }
    return null;
  }

  static String? _normalizeName(String? value) {
    if (value == null) return null;
    final normalized = value.trim().replaceAll(RegExp(r'^"+|"+$'), '');
    if (normalized.isEmpty) return null;
    return normalized;
  }

  static bool _looksGenericName(String value) {
    final normalized = value.trim().toLowerCase();
    return RegExp(
      r'^(proxy|node|server|outbound|profile|subscription)\s*[-_#:]?\s*\d+$',
    ).hasMatch(normalized);
  }

  static bool _looksLikeLagomProviderName(String? value) {
    final normalized = value?.toLowerCase().replaceAll(
      RegExp(r'[^a-z0-9]+'),
      '',
    );
    return normalized != null && normalized.contains('lagomvpn');
  }

  static List<Map<String, dynamic>> _normalizeLagomConfigs(
    List<Map<String, dynamic>> parsedConfigs,
  ) {
    final results = <Map<String, dynamic>>[];
    final seenWlConfigs = <String>{};
    final nameCounts = <String, int>{};

    for (final rawConfig in parsedConfigs) {
      final config = Map<String, dynamic>.from(rawConfig);
      final sourceTag = config['_source_tag']?.toString().trim() ?? '';
      final type = config['type']?.toString().trim().toLowerCase() ?? '';

      if (sourceTag == 'proxy' && type == 'vless') {
        final profileName = _normalizeLagomProfileName(
          config['_source_profile_name']?.toString(),
        );
        if (profileName != null) {
          final countryCode = _extractCountryFromName(profileName).countryCode;
          if (countryCode != null) {
            config['_country_override'] = countryCode;
          }
        }
        config['_name'] = 'Direct';
        results.add(config);
        final whitelistConfig = Map<String, dynamic>.from(config);
        whitelistConfig['_name'] = 'WL';
        whitelistConfig['_source_tag'] = _lagomWhitelistProxySourceTag;
        whitelistConfig['_group_only'] = true;
        whitelistConfig['detour'] = _lagomWhitelistDetourTag;
        results.add(whitelistConfig);
        continue;
      }

      if (!_isLagomWlSourceTag(sourceTag) || type != 'vless') {
        continue;
      }

      final dedupeKey = _lagomWlDedupeKey(config, sourceTag);
      if (!seenWlConfigs.add(dedupeKey)) {
        continue;
      }

      final baseName = _lagomUnfuckSourceTag(sourceTag);
      final count = (nameCounts[baseName] ?? 0) + 1;
      nameCounts[baseName] = count;
      config['_name'] = count == 1 ? baseName : '$baseName $count';
      config['_country_override'] = 'RU';
      results.add(config);
    }

    return results;
  }

  static String? _normalizeLagomProfileName(String? value) {
    final normalized = _normalizeName(value);
    if (normalized == null) {
      return null;
    }
    return normalized
        .replaceAll(
          RegExp(r'\s*\(\s*Глобальный\s*\)', caseSensitive: false),
          '',
        )
        .trim();
  }

  static List<Map<String, dynamic>> _normalizeLagomGroups(
    List<Map<String, dynamic>> normalizedConfigs,
    List<Map<String, dynamic>> parsedGroups,
  ) {
    final whitelistSourceTags = <String>[];
    final seenWhitelistSourceTags = <String>{};
    final proxyByScope = <String, Map<String, dynamic>>{};
    final proxyWhitelistScopes = <String>{};
    for (final config in normalizedConfigs) {
      final sourceTag = config['_source_tag']?.toString().trim() ?? '';
      final sourceScope = config['_source_scope']?.toString().trim() ?? '';
      if (sourceTag == 'proxy') {
        proxyByScope[sourceScope] = config;
      } else if (sourceTag == _lagomWhitelistProxySourceTag) {
        proxyWhitelistScopes.add(sourceScope);
      } else if (_isLagomWlSourceTag(sourceTag) &&
          seenWhitelistSourceTags.add(sourceTag)) {
        whitelistSourceTags.add(sourceTag);
      }
    }

    ParsedOutboundGroup? urlTestSource;
    for (final parsedGroup in parsedGroups) {
      final group = ParsedOutboundGroup.fromMap(parsedGroup);
      if (group.url?.trim().isNotEmpty == true ||
          group.intervalSeconds != null ||
          group.timeoutSeconds != null) {
        urlTestSource = group;
        break;
      }
    }

    final url = urlTestSource?.url;
    final interval = urlTestSource?.intervalSeconds;
    final timeout = urlTestSource?.timeoutSeconds;

    final groups = <Map<String, dynamic>>[];
    var serverGroupIndex = 0;
    for (final entry in proxyByScope.entries) {
      final sourceScope = entry.key;
      if (!proxyWhitelistScopes.contains(sourceScope)) {
        continue;
      }
      final config = entry.value;
      final name =
          _normalizeLagomProfileName(
            config['_source_profile_name']?.toString(),
          ) ??
          _normalizeLagomProfileName(config['_name']?.toString());
      final group = <String, dynamic>{
        'tag': 'lagom-server-$serverGroupIndex',
        'name': name?.isNotEmpty == true ? name : 'Lagom server',
        'type': 'urltest',
        if (sourceScope.isNotEmpty) 'source_scope': sourceScope,
        'outbounds': ['proxy', _lagomWhitelistProxySourceTag],
        'method': 'setback',
      };
      if (url != null) {
        group['url'] = url;
      }
      if (interval != null) {
        group['interval'] = interval;
      }
      if (timeout != null) {
        group['timeout'] = timeout;
      }
      groups.add(group);
      serverGroupIndex++;
    }

    if (whitelistSourceTags.length >= 2) {
      final group = <String, dynamic>{
        'tag': _lagomWhitelistDetourTag,
        'name': 'Whitelist',
        'type': 'urltest',
        'outbounds': whitelistSourceTags,
        'method': 'lowest',
      };
      if (url != null) {
        group['url'] = url;
      }
      if (interval != null) {
        group['interval'] = interval;
      }
      if (timeout != null) {
        group['timeout'] = timeout;
      }
      groups.add(group);
    }
    return groups;
  }

  static bool _isLagomWlSourceTag(String value) {
    final normalized = value.trim().toUpperCase();
    return normalized.startsWith('WL-') && normalized != 'WL-IN';
  }

  static String _lagomWlDedupeKey(
    Map<String, dynamic> config,
    String sourceTag,
  ) {
    final transport = config['transport'];
    return [
      sourceTag,
      config['server']?.toString() ?? '',
      config['server_port']?.toString() ?? '',
      config['uuid']?.toString() ?? '',
      transport is Map ? transport['type']?.toString() ?? '' : '',
    ].join('\n');
  }

  static String _lagomUnfuckSourceTag(String sourceTag) {
    final aliases = const {
      'vkc': 'vk cloud',
      'ya': 'yandex',
      'con': 'contell',
      'yad': 'yandex',
    };
    final parts = sourceTag
        .trim()
        .toLowerCase()
        .split('-')
        .where((part) => part.isNotEmpty && int.tryParse(part) == null)
        .map((part) => aliases[part] ?? part)
        .expand((part) => part.split(' '))
        .where((part) => part.isNotEmpty)
        .map(_formatLagomNamePart)
        .toList(growable: false);
    return parts.isEmpty ? sourceTag.trim() : parts.join(' ');
  }

  static String _formatLagomNamePart(String part) {
    return switch (part) {
      'wl' => 'WL',
      'vk' => 'VK',
      'cdn' => 'CDN',
      'sel' => 'SEL',
      _ => part.substring(0, 1).toUpperCase() + part.substring(1),
    };
  }

  static ({String name, String? countryCode}) _extractCountryFromName(
    String rawName,
  ) {
    final trimmed = rawName.trim();
    if (trimmed.isEmpty) {
      return (name: trimmed, countryCode: null);
    }

    final match = RegExp(
      r'([\u{1F1E6}-\u{1F1FF}]{2})',
      unicode: true,
    ).firstMatch(trimmed);
    if (match == null) {
      return (
        name: trimmed,
        countryCode: _countryCodeFromLeadingLocation(
          _stripLeadingDecorations(trimmed),
        ),
      );
    }

    final flag = match.group(1)!;
    final start = match.start;
    final end = match.end;
    final remainder = '${trimmed.substring(0, start)} ${trimmed.substring(end)}'
        .trim()
        .replaceAll(RegExp(r'\s{2,}'), ' ');
    final countryCode = _countryCodeFromFlag(flag);
    return (
      name: remainder.isNotEmpty ? remainder : trimmed,
      countryCode: countryCode,
    );
  }

  static String? _normalizeCountryCode(String? countryCode) {
    final normalized = countryCode?.trim().toUpperCase() ?? '';
    if (!RegExp(r'^[A-Z]{2}$').hasMatch(normalized)) {
      return null;
    }
    return normalized;
  }

  static String _stripLeadingDecorations(String value) {
    var result = value.trim();
    while (result.isNotEmpty) {
      final changed = result
          .replaceFirst(RegExp(r'^[\s\-_.:/|]+'), '')
          .replaceFirst(
            RegExp(r'^[^\u{1F1E6}-\u{1F1FF}A-Za-zА-Яа-яЁё0-9]+', unicode: true),
            '',
          )
          .trimLeft();
      if (changed == result) {
        break;
      }
      result = changed;
    }
    return result;
  }

  static String? _countryCodeFromFlag(String flag) {
    final runes = flag.runes.toList(growable: false);
    if (runes.length != 2) {
      return null;
    }

    final first = runes[0] - 0x1F1E6;
    final second = runes[1] - 0x1F1E6;
    if (first < 0 || first > 25 || second < 0 || second > 25) {
      return null;
    }

    return String.fromCharCodes([65 + first, 65 + second]);
  }

  static String? _countryCodeFromLeadingLocation(String value) {
    final normalized = value.trim().toLowerCase().replaceAll(
      RegExp(r'^[\s\-_.:/|]+'),
      '',
    );
    for (final entry in _locationAliasesByLongestPrefix) {
      final key = entry.key;
      if (normalized == key ||
          normalized.startsWith('$key ') ||
          normalized.startsWith('$key-') ||
          normalized.startsWith('${key}_') ||
          normalized.startsWith('$key.') ||
          normalized.startsWith('$key/') ||
          normalized.startsWith('$key|') ||
          normalized.startsWith('$key:')) {
        return entry.value;
      }
    }
    return null;
  }

  static final List<MapEntry<String, String>> _locationAliasesByLongestPrefix =
      kLocationAliases.entries.toList(growable: false)
        ..sort((a, b) => b.key.length.compareTo(a.key.length));
}

String? _rewriteOutboundRuntimeInfoPayload(
  String raw,
  Map<String, Map<String, Object?>> updatesByTag,
) {
  try {
    final map = jsonDecode(_decodeStoredPayload(raw)) as Map<String, dynamic>;
    final rawOutbounds = map['outbounds'];
    if (rawOutbounds is! List || rawOutbounds.isEmpty) {
      return null;
    }
    var changed = false;
    final outbounds = rawOutbounds
        .map((rawOutbound) {
          if (rawOutbound is! Map) {
            return rawOutbound;
          }
          final outbound = Map<String, dynamic>.from(rawOutbound);
          final tag = outbound['tag']?.toString() ?? '';
          final update = updatesByTag[tag];
          if (update == null || update.isEmpty) {
            return rawOutbound;
          }
          final info = outbound['info'] is Map
              ? Map<String, dynamic>.from(outbound['info'] as Map)
              : <String, dynamic>{};
          var outboundChanged = false;
          final latestPing = update['latest_ping'];
          if (latestPing is int && latestPing > 0) {
            if ((info['latest_ping'] as num?)?.toInt() != latestPing) {
              info['latest_ping'] = latestPing;
              outboundChanged = true;
            }
          }
          final externalIp = update['external_ip'];
          if (externalIp is String && externalIp.isNotEmpty) {
            if (info['external_ip'] != externalIp) {
              info['external_ip'] = externalIp;
              outboundChanged = true;
            }
          }
          final sourceCountry = update['source_country'];
          if (sourceCountry is String && sourceCountry.isNotEmpty) {
            if (info['country'] != sourceCountry) {
              info['country'] = sourceCountry;
              outboundChanged = true;
            }
          }
          final exitCountry = update['exit_country'];
          if (exitCountry is String && exitCountry.isNotEmpty) {
            if (info['exit_country'] != exitCountry) {
              info['exit_country'] = exitCountry;
              outboundChanged = true;
            }
          }
          if (!outboundChanged) {
            return rawOutbound;
          }
          outbound['info'] = info;
          changed = true;
          return outbound;
        })
        .toList(growable: false);
    if (!changed) {
      return null;
    }
    final updated = Map<String, dynamic>.from(map);
    updated['outbounds'] = outbounds;
    return _encodeStoredPayload(jsonEncode(updated));
  } catch (_) {
    return null;
  }
}

class _StoreMutationWaiter {
  _StoreMutationWaiter({required this.exclusive});

  final bool exclusive;
  final Completer<void> ready = Completer<void>();
}

const _compressedPayloadPrefix = 'gzip-base64-v1:';

bool _isCompressedPayload(String value) =>
    value.startsWith(_compressedPayloadPrefix);

String _encodeStoredPayload(String json) {
  final compressed = gzip.encode(utf8.encode(json));
  final encoded = '$_compressedPayloadPrefix${base64Encode(compressed)}';
  return encoded.length < json.length ? encoded : json;
}

String _decodeStoredPayload(String value) {
  if (!_isCompressedPayload(value)) {
    return value;
  }
  final encoded = value.substring(_compressedPayloadPrefix.length);
  return utf8.decode(gzip.decode(base64Decode(encoded)));
}

Map<String, dynamic> _buildSubscriptionPayloadWorker(
  Map<String, dynamic> input,
) {
  final parsedConfigs = (input['outbounds'] as List? ?? const [])
      .map((entry) => Map<String, dynamic>.from(entry as Map))
      .toList(growable: false);
  final parsedGroups = (input['groups'] as List? ?? const [])
      .map((entry) => Map<String, dynamic>.from(entry as Map))
      .toList(growable: false);
  final providerName = input['provider_name']?.toString();
  final payload = SubscriptionStore._buildOutboundPayload(
    parsedConfigs,
    parsedGroups,
    providerName,
  );
  return {
    'outbounds': payload.outbounds,
    'groups': payload.groups,
    'warnings': payload.warnings,
  };
}
