import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hydrabox/app/app.dart';
import 'package:hydrabox/logging/app_log_store.dart';

void _recordFatalError(String source, Object error, StackTrace stackTrace) {
  final message = '$error\n$stackTrace';
  AppLogStore.error('fatal/$source', message);
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
        return true;
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
      runApp(const HydraBoxClient());
    },
    (error, stackTrace) {
      _recordFatalError('zone', error, stackTrace);
    },
  );
}
