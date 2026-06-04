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
  });

  final bool wakeLockEnabled;
  final bool networkHeartbeatEnabled;
  final int networkHeartbeatIntervalSeconds;
  final String performanceMode;
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

  Future<void> urlTest({required String groupTag}) {
    return _withMethodChannelFallback(
      () => _hostApi.urlTest(groupTag),
      () => _methods.invokeMethod<void>('urlTest', {'groupTag': groupTag}),
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
      return await _withMethodChannelFallback<List<Map<String, dynamic>>>(
        () async => _normalizeMapList(await _hostApi.getInstalledApps()),
        () async {
          final value = await _methods.invokeListMethod<dynamic>(
            'getInstalledApps',
          );
          if (value == null) {
            return const <Map<String, dynamic>>[];
          }
          return value
              .whereType<Map>()
              .map((item) => Map<String, dynamic>.from(item))
              .toList(growable: false);
        },
      );
    } on MissingPluginException {
      return const <Map<String, dynamic>>[];
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
