import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:hydrabox/app/app.dart';
import 'package:hydrabox/logging/app_log_store.dart';
import 'package:hydrabox/singbox/singbox_runtime.dart';

void _recordFatalError(String source, Object error, StackTrace stackTrace) {
  final message = '$error\n$stackTrace';
  AppLogStore.error('fatal/$source', message);
  unawaited(
    SingboxRuntime.instance.recordIncident(
      category: 'flutter',
      code: 'fatal_$source',
      safePayload: AppLogStore.redact(message),
    ),
  );
}

Future<void> main() async {
  await runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();
      FlutterError.onError = (details) {
        FlutterError.presentError(details);
        _recordFatalError(
          'flutter',
          details.exception,
          details.stack ?? StackTrace.current,
        );
      };
      PlatformDispatcher.instance.onError = (error, stackTrace) {
        _recordFatalError('platform', error, stackTrace);
        return false;
      };
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      SystemChrome.setSystemUIOverlayStyle(
        const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          systemNavigationBarColor: Colors.transparent,
          systemNavigationBarDividerColor: Colors.transparent,
          systemNavigationBarContrastEnforced: false,
        ),
      );
      runApp(const ProviderScope(child: HydraBoxClient()));
    },
    (error, stackTrace) {
      _recordFatalError('zone', error, stackTrace);
    },
  );
}
