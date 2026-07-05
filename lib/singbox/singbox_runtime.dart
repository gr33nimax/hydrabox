import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:meow_client/singbox/singbox_api.g.dart' as pigeon;

@visibleForTesting
List<Map<String, dynamic>> normalizePigeonMapListForTest(Object? value) {
  return SingboxRuntime.instance._normalizeMapList(value);
}

class RuntimeFlags {
  const RuntimeFlags({
    this.wakeLockEnabled = false,
    this.networkHeartbeatEnabled = true,
    this.networkHeartbeatIntervalSeconds = 180,
    this.performanceMode = 'cool',
    this.memoryLimitEnabled = true,
  });

  final bool wakeLockEnabled;
  final bool networkHeartbeatEnabled;
  final int networkHeartbeatIntervalSeconds;
  final String performanceMode;
  final bool memoryLimitEnabled;
}

class AppVersionInfo {
  const AppVersionInfo({
    required this.packageName,
    required this.versionName,
    required this.versionCode,
  });

  final String packageName;
  final String versionName;
  final int versionCode;

  String get displayVersion {
    final normalized = versionName.trim();
    return normalized.isEmpty ? '0.2.1' : normalized;
  }

  int get updateBuildNumber => normalizeSplitApkVersionCode(versionCode);

  static int normalizeSplitApkVersionCode(int value) {
    if (value <= 0) return 0;
    final abiSplitBuildNumber = value % 1000;
    if (value >= 1000 && abiSplitBuildNumber > 0) {
      return abiSplitBuildNumber;
    }
    return value;
  }
}

class NetworkInterfaceSnapshot {
  const NetworkInterfaceSnapshot({
    required this.available,
    required this.interfaceName,
    required this.interfaceIndex,
    required this.generation,
    required this.reason,
    required this.updatedAtMillis,
  });

  static const unavailable = NetworkInterfaceSnapshot(
    available: false,
    interfaceName: '',
    interfaceIndex: -1,
    generation: 0,
    reason: 'unavailable',
    updatedAtMillis: 0,
  );

  final bool available;
  final String interfaceName;
  final int interfaceIndex;
  final int generation;
  final String reason;
  final int updatedAtMillis;

  bool get usable =>
      available && interfaceName.trim().isNotEmpty && interfaceIndex >= 0;
}

class EndpointProbeRequest {
  const EndpointProbeRequest({
    required this.tag,
    required this.host,
    required this.port,
    required this.timeoutMs,
  });

  final String tag;
  final String host;
  final int port;
  final int timeoutMs;
}

class EndpointProbeResult {
  const EndpointProbeResult({
    required this.tag,
    required this.reachable,
    required this.latencyMs,
    required this.errorCode,
    required this.checkedAtMillis,
    required this.protectedSocket,
  });

  final String tag;
  final bool reachable;
  final int? latencyMs;
  final String errorCode;
  final int checkedAtMillis;
  final bool protectedSocket;
}

class SingboxRuntime {
  SingboxRuntime._();

  static final SingboxRuntime instance = SingboxRuntime._();

  static const MethodChannel _methods = MethodChannel('meow_client/singbox');
  static final pigeon.SingboxHostApi _hostApi = pigeon.SingboxHostApi();
  static const EventChannel _events = EventChannel(
    'meow_client/singbox_events',
  );

  Stream<Map<String, dynamic>> get events => _events
      .receiveBroadcastStream()
      .map((event) => Map<String, dynamic>.from(event as Map));

  Map<String, dynamic> _normalizeMap(Object? value) {
    if (value is! Map) {
      return const {};
    }
    return <String, dynamic>{
      for (final entry in value.entries)
        if (entry.key != null) entry.key.toString(): entry.value,
    };
  }

  List<Map<String, dynamic>> _normalizeMapList(Object? value) {
    if (value is! Iterable) {
      return const <Map<String, dynamic>>[];
    }
    return value.whereType<Map>().map(_normalizeMap).toList(growable: false);
  }

  Future<T> _withMethodChannelFallback<T>(
    Future<T> Function() hostCall,
    Future<T> Function() fallback,
  ) async {
    if (!Platform.isAndroid) {
      return fallback();
    }
    try {
      return await hostCall();
    } on MissingPluginException {
      return fallback();
    } on PlatformException catch (error) {
      if (error.code == 'channel-error') {
        return fallback();
      }
      rethrow;
    }
  }

  Future<bool> prepareVpn({required bool requiresVpn}) async {
    return _withMethodChannelFallback(
      () => _hostApi.prepareVpn(requiresVpn),
      () async {
        if (!Platform.isAndroid) {
          return !requiresVpn;
        }
        final granted = await _methods.invokeMethod<bool>('prepareVpn', {
          'requiresVpn': requiresVpn,
        });
        return granted ?? false;
      },
    );
  }

  Future<bool> vpnPermissionGranted() async {
    final value = await _withMethodChannelFallback<Map<String, dynamic>>(
      () async => _normalizeMap(await _hostApi.vpnPermissionStatus()),
      () async =>
          await _methods.invokeMapMethod<String, dynamic>(
            'vpnPermissionStatus',
          ) ??
          const {},
    );
    return value['granted'] == true;
  }

  Future<void> start({required String config, required bool useVpn}) {
    return _withMethodChannelFallback(
      () => _hostApi.start(config, useVpn),
      () => _methods.invokeMethod<void>('start', {
        'config': config,
        'useVpn': useVpn,
      }),
    );
  }

  Future<void> startPrepared({required bool useVpn}) {
    return _withMethodChannelFallback(
      () => _hostApi.startPrepared(useVpn),
      () => _methods.invokeMethod<void>('startPrepared', {'useVpn': useVpn}),
    );
  }

  Future<void> applyConfig({
    required String config,
    required bool useVpn,
    bool restartCore = false,
  }) {
    return _withMethodChannelFallback(
      () => _hostApi.applyConfig(config, useVpn, restartCore),
      () => _methods.invokeMethod<void>('applyConfig', {
        'config': config,
        'useVpn': useVpn,
        'restartCore': restartCore,
      }),
    );
  }

  Future<void> applyPreparedConfig({
    required bool useVpn,
    bool restartCore = false,
  }) {
    return _withMethodChannelFallback(
      () => _hostApi.applyPreparedConfig(useVpn, restartCore),
      () => _methods.invokeMethod<void>('applyPreparedConfig', {
        'useVpn': useVpn,
        'restartCore': restartCore,
      }),
    );
  }

  Future<String?> getConfigPath() async {
    if (!Platform.isAndroid) {
      return null;
    }
    try {
      final value = await _withMethodChannelFallback<String?>(
        () => _hostApi.getConfigPath(),
        () => _methods.invokeMethod<String>('getConfigPath'),
      );
      final normalized = value?.trim() ?? '';
      return normalized.isEmpty ? null : normalized;
    } on MissingPluginException {
      return null;
    }
  }

  Future<RuntimeFlags> getRuntimeFlags() async {
    if (!Platform.isAndroid) {
      return const RuntimeFlags();
    }
    try {
      final value = await _withMethodChannelFallback<Map<String, dynamic>>(
        () async => _normalizeMap(await _hostApi.getRuntimeFlags()),
        () async =>
            await _methods.invokeMapMethod<String, dynamic>(
              'getRuntimeFlags',
            ) ??
            const {},
      );
      return RuntimeFlags(
        wakeLockEnabled: value['wakeLockEnabled'] == true,
        networkHeartbeatEnabled: value['networkHeartbeatEnabled'] != false,
        networkHeartbeatIntervalSeconds:
            (value['networkHeartbeatIntervalSeconds'] as num?)?.toInt() ?? 180,
        performanceMode:
            value['performanceMode']?.toString().trim().isNotEmpty == true
            ? value['performanceMode'].toString()
            : 'cool',
        memoryLimitEnabled: value['memoryLimitEnabled'] != false,
      );
    } on MissingPluginException {
      return const RuntimeFlags();
    }
  }

  Future<void> setRuntimeFlags({
    bool? wakeLockEnabled,
    bool? networkHeartbeatEnabled,
    int? networkHeartbeatIntervalSeconds,
    String? performanceMode,
    bool? memoryLimitEnabled,
  }) async {
    if (!Platform.isAndroid) {
      return;
    }
    try {
      await _withMethodChannelFallback(
        () => _hostApi.setRuntimeFlags(
          pigeon.RuntimeFlagsMessage(
            wakeLockEnabled: wakeLockEnabled,
            networkHeartbeatEnabled: networkHeartbeatEnabled,
            networkHeartbeatIntervalSeconds: networkHeartbeatIntervalSeconds,
            performanceMode: performanceMode,
            memoryLimitEnabled: memoryLimitEnabled,
          ),
        ),
        () {
          final args = <String, dynamic>{};
          if (wakeLockEnabled != null) {
            args['wakeLockEnabled'] = wakeLockEnabled;
          }
          if (networkHeartbeatEnabled != null) {
            args['networkHeartbeatEnabled'] = networkHeartbeatEnabled;
          }
          if (networkHeartbeatIntervalSeconds != null) {
            args['networkHeartbeatIntervalSeconds'] =
                networkHeartbeatIntervalSeconds;
          }
          if (performanceMode != null) {
            args['performanceMode'] = performanceMode;
          }
          if (memoryLimitEnabled != null) {
            args['memoryLimitEnabled'] = memoryLimitEnabled;
          }
          return _methods.invokeMethod<void>('setRuntimeFlags', args);
        },
      );
    } on MissingPluginException {
      // Ignore on builds without the Android platform bridge.
    }
  }

  Future<void> reload() => _withMethodChannelFallback(
    () => _hostApi.reload(),
    () => _methods.invokeMethod<void>('reload'),
  );

  Future<void> setRuntimeUiForeground(bool foreground) async {
    if (!Platform.isAndroid) {
      return;
    }
    try {
      await _methods.invokeMethod<void>('setRuntimeUiForeground', {
        'foreground': foreground,
      });
    } on MissingPluginException {
      // Older Android bridges keep their existing telemetry behavior.
    }
  }

  Future<void> stop({String reason = 'unspecified'}) {
    return _withMethodChannelFallback(
      () => _hostApi.stop(reason),
      () => _methods.invokeMethod<void>('stop', {'reason': reason}),
    );
  }

  Future<void> selectOutbound({
    required String groupTag,
    required String outboundTag,
  }) {
    return _withMethodChannelFallback(
      () => _hostApi.selectOutbound(groupTag, outboundTag),
      () => _methods.invokeMethod<void>('selectOutbound', {
        'groupTag': groupTag,
        'outboundTag': outboundTag,
      }),
    );
  }

  Future<void> addOutbound({
    required String selectorTag,
    required String outboundJson,
  }) {
    if (!Platform.isAndroid) {
      return Future<void>.value();
    }
    return _withMethodChannelFallback(
      () => _hostApi.addOutbound(selectorTag, outboundJson),
      () => _methods.invokeMethod<void>('addOutbound', {
        'selectorTag': selectorTag,
        'outboundJson': outboundJson,
      }),
    );
  }

  Future<void> removeOutbound({
    required String selectorTag,
    required String outboundTag,
  }) {
    if (!Platform.isAndroid) {
      return Future<void>.value();
    }
    return _withMethodChannelFallback(
      () => _hostApi.removeOutbound(selectorTag, outboundTag),
      () => _methods.invokeMethod<void>('removeOutbound', {
        'selectorTag': selectorTag,
        'outboundTag': outboundTag,
      }),
    );
  }

  Future<void> urlTest({
    required String groupTag,
    String targetOutboundTag = '',
    String priorityOutboundTag = '',
    String excludeOutboundTag = '',
    String url = '',
    int timeoutMillis = 3000,
    int concurrency = 0,
    int deadlineMillis = 10000,
    bool force = true,
  }) {
    return _withMethodChannelFallback(
      () async {
        await _hostApi.urlTest(
          pigeon.UrlTestRequestMessage(
            groupTag: groupTag,
            targetOutboundTag: targetOutboundTag,
            priorityOutboundTag: priorityOutboundTag,
            excludeOutboundTag: excludeOutboundTag,
            url: url,
            timeoutMillis: timeoutMillis,
            concurrency: concurrency,
            deadlineMillis: deadlineMillis,
            force: force,
          ),
        );
      },
      () async {
        await _methods.invokeMethod<void>('urlTest', {
          'groupTag': groupTag,
          'targetOutboundTag': targetOutboundTag,
          'priorityOutboundTag': priorityOutboundTag,
          'excludeOutboundTag': excludeOutboundTag,
          'url': url,
          'timeoutMillis': timeoutMillis,
          'concurrency': concurrency,
          'deadlineMillis': deadlineMillis,
          'force': force,
        });
      },
    );
  }

  Future<void> removeUrlTestOutbounds({
    required String groupTag,
    required Iterable<String> outboundTags,
  }) {
    if (!Platform.isAndroid) {
      return Future<void>.value();
    }
    final normalizedGroupTag = groupTag.trim();
    final normalizedTags = outboundTags
        .map((tag) => tag.trim())
        .where((tag) => tag.isNotEmpty)
        .toList(growable: false);
    if (normalizedGroupTag.isEmpty || normalizedTags.isEmpty) {
      return Future<void>.value();
    }
    return _withMethodChannelFallback(
      () => _hostApi.removeUrlTestOutbounds(normalizedGroupTag, normalizedTags),
      () => _methods.invokeMethod<void>('removeUrlTestOutbounds', {
        'groupTag': normalizedGroupTag,
        'outboundTags': normalizedTags,
      }),
    );
  }

  Future<Map<String, dynamic>> status() async {
    return _withMethodChannelFallback(
      () async => _normalizeMap(await _hostApi.status()),
      () async =>
          await _methods.invokeMapMethod<String, dynamic>('status') ?? const {},
    );
  }

  Future<Map<String, dynamic>> lookupOutboundExternalInfo({
    required String outboundTag,
  }) async {
    if (!Platform.isAndroid) {
      return const {};
    }
    final normalizedTag = outboundTag.trim();
    if (normalizedTag.isEmpty) {
      return const {};
    }
    try {
      final value = await _withMethodChannelFallback<Map<String, dynamic>>(
        () async => _normalizeMap(
          await _hostApi.lookupOutboundExternalInfo(normalizedTag),
        ),
        () async =>
            await _methods.invokeMapMethod<String, dynamic>(
              'lookupOutboundExternalInfo',
              {'outboundTag': normalizedTag},
            ) ??
            const {},
      );
      return value;
    } on MissingPluginException {
      return const {};
    }
  }

  Future<NetworkInterfaceSnapshot> getNetworkInterfaceState() async {
    if (!Platform.isAndroid) {
      return NetworkInterfaceSnapshot.unavailable;
    }
    try {
      final value = await _withMethodChannelFallback<NetworkInterfaceSnapshot>(
        () async {
          final state = await _hostApi.getNetworkInterfaceState();
          return NetworkInterfaceSnapshot(
            available: state.available,
            interfaceName: state.interfaceName?.trim() ?? '',
            interfaceIndex: state.interfaceIndex,
            generation: state.generation,
            reason: state.reason?.trim() ?? 'host_api',
            updatedAtMillis: state.updatedAtMillis,
          );
        },
        () async {
          final raw =
              await _methods.invokeMapMethod<String, dynamic>(
                'getNetworkInterfaceState',
              ) ??
              const {};
          return NetworkInterfaceSnapshot(
            available: raw['available'] == true,
            interfaceName: raw['interfaceName']?.toString().trim() ?? '',
            interfaceIndex: (raw['interfaceIndex'] as num?)?.toInt() ?? -1,
            generation: (raw['generation'] as num?)?.toInt() ?? 0,
            reason: raw['reason']?.toString().trim() ?? 'method_channel',
            updatedAtMillis: (raw['updatedAtMillis'] as num?)?.toInt() ?? 0,
          );
        },
      );
      return value;
    } on MissingPluginException {
      return NetworkInterfaceSnapshot.unavailable;
    }
  }

  Future<EndpointProbeResult> probeProxyEndpoint(
    EndpointProbeRequest request,
  ) async {
    if (!Platform.isAndroid) {
      return EndpointProbeResult(
        tag: request.tag,
        reachable: false,
        latencyMs: null,
        errorCode: 'unsupported_platform',
        checkedAtMillis: DateTime.now().millisecondsSinceEpoch,
        protectedSocket: false,
      );
    }
    final tag = request.tag.trim();
    final host = request.host.trim();
    final port = request.port;
    final timeoutMs = request.timeoutMs.clamp(500, 10000).toInt();
    if (tag.isEmpty || host.isEmpty || port <= 0 || port > 65535) {
      return EndpointProbeResult(
        tag: tag,
        reachable: false,
        latencyMs: null,
        errorCode: 'invalid_endpoint',
        checkedAtMillis: DateTime.now().millisecondsSinceEpoch,
        protectedSocket: false,
      );
    }
    try {
      return await _withMethodChannelFallback<EndpointProbeResult>(
        () async {
          final result = await _hostApi.probeProxyEndpoint(
            pigeon.EndpointProbeRequestMessage(
              tag: tag,
              host: host,
              port: port,
              timeoutMs: timeoutMs,
            ),
          );
          return EndpointProbeResult(
            tag: result.tag,
            reachable: result.reachable,
            latencyMs: result.latencyMs,
            errorCode: result.errorCode?.trim() ?? '',
            checkedAtMillis: result.checkedAtMillis,
            protectedSocket: result.protectedSocket,
          );
        },
        () async {
          final raw =
              await _methods.invokeMapMethod<String, dynamic>(
                'probeProxyEndpoint',
                {
                  'tag': tag,
                  'host': host,
                  'port': port,
                  'timeoutMs': timeoutMs,
                },
              ) ??
              const {};
          return EndpointProbeResult(
            tag: raw['tag']?.toString() ?? tag,
            reachable: raw['reachable'] == true,
            latencyMs: (raw['latencyMs'] as num?)?.toInt(),
            errorCode: raw['errorCode']?.toString().trim() ?? '',
            checkedAtMillis:
                (raw['checkedAtMillis'] as num?)?.toInt() ??
                DateTime.now().millisecondsSinceEpoch,
            protectedSocket: raw['protectedSocket'] == true,
          );
        },
      );
    } on MissingPluginException {
      return EndpointProbeResult(
        tag: tag,
        reachable: false,
        latencyMs: null,
        errorCode: 'missing_plugin',
        checkedAtMillis: DateTime.now().millisecondsSinceEpoch,
        protectedSocket: false,
      );
    }
  }

  Future<String?> exportLogs({
    required String content,
    required String suggestedName,
  }) {
    return _withMethodChannelFallback(
      () => _hostApi.exportLogs(content, suggestedName),
      () => _methods.invokeMethod<String>('exportLogs', {
        'content': content,
        'suggestedName': suggestedName,
      }),
    );
  }

  Future<bool> canInstallApks() async {
    if (!Platform.isAndroid) {
      return false;
    }
    try {
      final value = await _methods.invokeMethod<bool>('canInstallApks');
      return value == true;
    } on MissingPluginException {
      return false;
    }
  }

  Future<void> openApkInstallSettings() async {
    if (!Platform.isAndroid) {
      return;
    }
    try {
      await _methods.invokeMethod<void>('openApkInstallSettings');
    } on MissingPluginException {
      // Ignore on non-Android bridge builds.
    }
  }

  Future<void> installDownloadedApk(String path) async {
    if (!Platform.isAndroid) {
      return;
    }
    final normalizedPath = path.trim();
    if (normalizedPath.isEmpty) {
      throw ArgumentError.value(path, 'path', 'APK path is empty');
    }
    await _methods.invokeMethod<void>('installDownloadedApk', {
      'path': normalizedPath,
    });
  }

  Future<Map<String, dynamic>> inspectDownloadedApk(String path) async {
    if (!Platform.isAndroid) {
      return const <String, dynamic>{'valid': true};
    }
    final normalizedPath = path.trim();
    if (normalizedPath.isEmpty) {
      throw ArgumentError.value(path, 'path', 'APK path is empty');
    }
    return await _methods.invokeMapMethod<String, dynamic>(
          'inspectDownloadedApk',
          <String, Object?>{'path': normalizedPath},
        ) ??
        const <String, dynamic>{'valid': false};
  }

  Future<Map<String, dynamic>> fetchUrlOnUnderlyingNetwork({
    required Uri uri,
    required Map<String, String> headers,
    required int maxBytes,
    required Duration timeout,
  }) async {
    if (!Platform.isAndroid) {
      throw UnsupportedError(
        'Underlying-network HTTP is only available on Android.',
      );
    }
    return await _methods.invokeMapMethod<String, dynamic>(
          'fetchUrlOnUnderlyingNetwork',
          <String, Object?>{
            'url': uri.toString(),
            'headers': headers,
            'maxBytes': maxBytes,
            'timeoutMs': timeout.inMilliseconds,
          },
        ) ??
        const <String, dynamic>{};
  }

  Future<String> getAndroidId() async {
    final value = await _withMethodChannelFallback<String?>(
      () => _hostApi.getAndroidId(),
      () => _methods.invokeMethod<String>('getAndroidId'),
    );
    return value ?? '';
  }

  Future<Map<String, dynamic>> getSubscriptionRequestDeviceInfo() async {
    final value = await _withMethodChannelFallback<Map<String, dynamic>>(
      () async =>
          _normalizeMap(await _hostApi.getSubscriptionRequestDeviceInfo()),
      () async =>
          await _methods.invokeMapMethod<String, dynamic>(
            'getSubscriptionRequestDeviceInfo',
          ) ??
          const {},
    );
    return value;
  }

  Future<Map<String, dynamic>> getPlatformDeviceInfo() async {
    if (!Platform.isAndroid) {
      return const {};
    }
    try {
      final value = await _withMethodChannelFallback<Map<String, dynamic>>(
        () async => _normalizeMap(await _hostApi.getPlatformDeviceInfo()),
        () async =>
            await _methods.invokeMapMethod<String, dynamic>(
              'getPlatformDeviceInfo',
            ) ??
            const {},
      );
      return value;
    } on MissingPluginException {
      return const {};
    }
  }

  Future<AppVersionInfo> getAppVersionInfo() async {
    if (!Platform.isAndroid) {
      return const AppVersionInfo(
        packageName: '',
        versionName: '0.2.1',
        versionCode: 0,
      );
    }
    try {
      final value = await _withMethodChannelFallback<Map<String, dynamic>>(
        () async => _normalizeMap(await _hostApi.getAppVersionInfo()),
        () async =>
            await _methods.invokeMapMethod<String, dynamic>(
              'getAppVersionInfo',
            ) ??
            const {},
      );
      return AppVersionInfo(
        packageName: value['packageName']?.toString().trim() ?? '',
        versionName: value['versionName']?.toString().trim() ?? '',
        versionCode: int.tryParse(value['versionCode']?.toString() ?? '') ?? 0,
      );
    } on MissingPluginException {
      return const AppVersionInfo(
        packageName: '',
        versionName: '0.2.1',
        versionCode: 0,
      );
    }
  }

  Future<String?> getCoreVersion() async {
    if (!Platform.isAndroid) {
      return null;
    }
    try {
      final value = await _withMethodChannelFallback<String?>(
        () => _hostApi.getCoreVersion(),
        () => _methods.invokeMethod<String>('getCoreVersion'),
      );
      final normalized = value?.trim() ?? '';
      return normalized.isEmpty ? null : normalized;
    } on MissingPluginException {
      return null;
    }
  }

  Future<Map<String, dynamic>> getPerformanceSnapshot() async {
    if (!Platform.isAndroid) {
      return const {};
    }
    try {
      final value = await _withMethodChannelFallback<Map<String, dynamic>>(
        () async => _normalizeMap(await _hostApi.getPerformanceSnapshot()),
        () async =>
            await _methods.invokeMapMethod<String, dynamic>(
              'getPerformanceSnapshot',
            ) ??
            const {},
      );
      return value;
    } on MissingPluginException {
      return const {};
    }
  }

  Future<Map<String, dynamic>> getHappCrypt5Support() async {
    if (!Platform.isAndroid) {
      return const {
        'supported': false,
        'detail': 'This platform is not supported.',
      };
    }
    try {
      final value = await _withMethodChannelFallback<Map<String, dynamic>>(
        () async => _normalizeMap(await _hostApi.getHappCrypt5Support()),
        () async =>
            await _methods.invokeMapMethod<String, dynamic>(
              'getHappCrypt5Support',
            ) ??
            const {},
      );
      return value;
    } on MissingPluginException {
      return const {
        'supported': false,
        'detail': 'Android bridge is unavailable.',
      };
    }
  }

  Future<List<Map<String, dynamic>>> getInstalledApps() async {
    if (!Platform.isAndroid) {
      return const <Map<String, dynamic>>[];
    }
    try {
      // Pigeon map generics are stricter than Android's runtime payload shape
      // here: the codec can return _Map<Object?, Object?> and generated Pigeon
      // code casts it before our normalizer runs. Keep installed-apps on the
      // legacy MethodChannel until it is migrated to a typed Pigeon DTO.
      final value = await _methods.invokeListMethod<dynamic>(
        'getInstalledApps',
      );
      return _normalizeMapList(value);
    } on MissingPluginException {
      return const <Map<String, dynamic>>[];
    }
  }

  Future<Uint8List?> getInstalledAppIcon(
    String packageName, {
    int sizePx = 48,
  }) async {
    if (!Platform.isAndroid || packageName.trim().isEmpty) {
      return null;
    }
    try {
      return await _methods.invokeMethod<Uint8List>('getInstalledAppIcon', {
        'packageName': packageName.trim(),
        'sizePx': sizePx.clamp(24, 96).toInt(),
      });
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  Future<void> setQuickSettingsTileLabel(String? label) async {
    if (!Platform.isAndroid) {
      return;
    }
    try {
      final normalizedLabel = label?.trim() ?? '';
      await _withMethodChannelFallback(
        () => _hostApi.setQuickSettingsTileLabel(normalizedLabel),
        () => _methods.invokeMethod<void>('setQuickSettingsTileLabel', {
          'label': normalizedLabel,
        }),
      );
    } on MissingPluginException {
      // Ignore on builds without the Android platform bridge.
    }
  }
}
