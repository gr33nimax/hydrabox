import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/foundation.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:meow_client/data/local/app_settings_store.dart';
import 'package:meow_client/logging/app_log_store.dart';
import 'package:meow_client/singbox/singbox_runtime.dart';
import 'package:path_provider/path_provider.dart';

enum AppUpdateStatus {
  unknown,
  checking,
  upToDate,
  updateAvailable,
  downloading,
  downloaded,
  error,
}

class AppUpdateAsset {
  const AppUpdateAsset({
    required this.name,
    required this.downloadUrl,
    required this.sizeBytes,
    this.digestSha256,
  });

  final String name;
  final String downloadUrl;
  final int sizeBytes;
  final String? digestSha256;

  Map<String, Object?> toMap() => {
    'name': name,
    'downloadUrl': downloadUrl,
    'sizeBytes': sizeBytes,
    'digestSha256': digestSha256,
  };

  static AppUpdateAsset? fromMap(Object? value) {
    if (value is! Map) return null;
    final name = value['name']?.toString().trim() ?? '';
    final downloadUrl = value['downloadUrl']?.toString().trim() ?? '';
    if (name.isEmpty || downloadUrl.isEmpty) return null;
    return AppUpdateAsset(
      name: name,
      downloadUrl: downloadUrl,
      sizeBytes: int.tryParse(value['sizeBytes']?.toString() ?? '') ?? 0,
      digestSha256: AppUpdateService.normalizeSha256Digest(
        value['digestSha256'],
      ),
    );
  }
}

class AppUpdateInfo {
  const AppUpdateInfo({
    required this.version,
    required this.tagName,
    required this.title,
    required this.body,
    required this.htmlUrl,
    required this.publishedAt,
    required this.asset,
  });

  final String version;
  final String tagName;
  final String title;
  final String body;
  final String htmlUrl;
  final DateTime? publishedAt;
  final AppUpdateAsset asset;

  Map<String, Object?> toMap() => {
    'version': version,
    'tagName': tagName,
    'title': title,
    'body': body,
    'htmlUrl': htmlUrl,
    'publishedAtMillis': publishedAt?.millisecondsSinceEpoch,
    'asset': asset.toMap(),
  };

  static AppUpdateInfo? fromMap(Object? value) {
    if (value is! Map) return null;
    final asset = AppUpdateAsset.fromMap(value['asset']);
    if (asset == null) return null;
    final version = value['version']?.toString().trim() ?? '';
    final tagName = value['tagName']?.toString().trim() ?? '';
    if (version.isEmpty || tagName.isEmpty) return null;
    final publishedAtMillis = int.tryParse(
      value['publishedAtMillis']?.toString() ?? '',
    );
    return AppUpdateInfo(
      version: version,
      tagName: tagName,
      title: value['title']?.toString().trim() ?? 'v$version',
      body: value['body']?.toString() ?? '',
      htmlUrl: value['htmlUrl']?.toString().trim() ?? '',
      publishedAt: publishedAtMillis == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(publishedAtMillis),
      asset: asset,
    );
  }
}

class AppUpdateMetadata {
  const AppUpdateMetadata({
    this.lastCheckAtMillis,
    this.lastStatus = AppUpdateStatus.unknown,
    this.lastError,
    this.latestInfo,
    this.downloadedUpdatePath,
  });

  final int? lastCheckAtMillis;
  final AppUpdateStatus lastStatus;
  final String? lastError;
  final AppUpdateInfo? latestInfo;
  final String? downloadedUpdatePath;

  DateTime? get lastCheckAt => lastCheckAtMillis == null
      ? null
      : DateTime.fromMillisecondsSinceEpoch(lastCheckAtMillis!);

  bool get isDue {
    final last = lastCheckAt;
    if (last == null) return true;
    return DateTime.now().difference(last) >= AppUpdateService.checkInterval;
  }

  Map<String, Object?> toMap() => {
    'lastCheckAtMillis': lastCheckAtMillis,
    'lastStatus': lastStatus.name,
    'lastError': lastError,
    'latestInfo': latestInfo?.toMap(),
    'downloadedUpdatePath': downloadedUpdatePath,
  };

  static AppUpdateMetadata fromMap(Map<dynamic, dynamic> map) {
    final statusName = map['lastStatus']?.toString();
    final status = AppUpdateStatus.values.firstWhere(
      (value) => value.name == statusName,
      orElse: () => AppUpdateStatus.unknown,
    );
    return AppUpdateMetadata(
      lastCheckAtMillis: int.tryParse(
        map['lastCheckAtMillis']?.toString() ?? '',
      ),
      lastStatus: status,
      lastError: map['lastError']?.toString(),
      latestInfo: AppUpdateInfo.fromMap(map['latestInfo']),
      downloadedUpdatePath: map['downloadedUpdatePath']?.toString(),
    );
  }
}

class AppUpdateCheckResult {
  const AppUpdateCheckResult({
    required this.status,
    required this.checkedAt,
    this.info,
    this.error,
    this.fromCache = false,
    this.downloadedFilePath,
  });

  final AppUpdateStatus status;
  final DateTime checkedAt;
  final AppUpdateInfo? info;
  final String? error;
  final bool fromCache;
  final String? downloadedFilePath;
}

class AppUpdateDownloadProgress {
  const AppUpdateDownloadProgress({
    required this.downloadedBytes,
    required this.totalBytes,
    required this.bytesPerSecond,
    required this.done,
    this.filePath,
  });

  final int downloadedBytes;
  final int totalBytes;
  final double bytesPerSecond;
  final bool done;
  final String? filePath;

  double? get fraction =>
      totalBytes <= 0 ? null : (downloadedBytes / totalBytes).clamp(0.0, 1.0);

  int? get etaSeconds {
    if (bytesPerSecond <= 1 || totalBytes <= 0) return null;
    final remaining = totalBytes - downloadedBytes;
    if (remaining <= 0) return 0;
    return (remaining / bytesPerSecond).ceil();
  }
}

class AppUpdateVerificationResult {
  const AppUpdateVerificationResult({
    required this.ok,
    this.expectedSha256,
    this.actualSha256,
    this.error,
  });

  final bool ok;
  final String? expectedSha256;
  final String? actualSha256;
  final String? error;

  bool get checksumAvailable =>
      expectedSha256 != null && expectedSha256!.isNotEmpty;
}

class AppUpdateService {
  AppUpdateService._();

  static final AppUpdateService instance = AppUpdateService._();
  static const checkInterval = Duration(hours: 24);
  static const repositoryOwner = 'yamixdev';
  static const repositoryName = 'Etonify';
  static const _metadataBoxName = 'app_update_state';
  static const _latestReleaseUrl =
      'https://api.github.com/repos/$repositoryOwner/$repositoryName/releases/latest';
  static const _assetTokens = ['arm64-v8a', 'armeabi-v7a', 'x86_64'];

  Future<Box<dynamic>> _openBox() async {
    await HiveAppSettingsStore.initHive();
    return Hive.isBoxOpen(_metadataBoxName)
        ? Hive.box<dynamic>(_metadataBoxName)
        : Hive.openBox<dynamic>(_metadataBoxName);
  }

  Future<AppUpdateMetadata> loadMetadata() async {
    final box = await _openBox();
    return AppUpdateMetadata.fromMap(box.toMap());
  }

  Future<void> _saveMetadata(AppUpdateMetadata metadata) async {
    final box = await _openBox();
    await box.putAll(metadata.toMap());
    await box.flush();
  }

  Future<AppUpdateCheckResult> checkForUpdates({
    required String currentVersion,
    bool manual = false,
  }) async {
    final metadata = await loadMetadata();
    if (!manual && !metadata.isDue) {
      final downloadedFilePath = await _validDownloadedPathFor(
        metadata.latestInfo,
        metadata.downloadedUpdatePath,
      );
      final status = downloadedFilePath != null
          ? AppUpdateStatus.downloaded
          : metadata.lastStatus;
      return AppUpdateCheckResult(
        status: status,
        checkedAt: metadata.lastCheckAt ?? DateTime.now(),
        info: metadata.latestInfo,
        error: metadata.lastError,
        fromCache: true,
        downloadedFilePath: downloadedFilePath,
      );
    }

    final checkedAt = DateTime.now();
    try {
      final release = await _fetchLatestRelease();
      final assets = _parseAssets(release['assets']);
      final supportedAbis = await _supportedAbis();
      final asset = selectAssetForAbis(assets, supportedAbis);
      if (asset == null) {
        throw const FormatException('No compatible APK asset found.');
      }
      final tagName = release['tag_name']?.toString().trim() ?? '';
      final version = normalizeVersion(tagName);
      if (version.isEmpty) {
        throw const FormatException('Release tag does not contain a version.');
      }
      final info = AppUpdateInfo(
        version: version,
        tagName: tagName,
        title: release['name']?.toString().trim().isNotEmpty == true
            ? release['name'].toString().trim()
            : 'v$version',
        body: release['body']?.toString() ?? '',
        htmlUrl: release['html_url']?.toString().trim() ?? '',
        publishedAt: DateTime.tryParse(
          release['published_at']?.toString() ?? '',
        ),
        asset: asset,
      );
      var status = isRemoteVersionNewer(version, currentVersion)
          ? AppUpdateStatus.updateAvailable
          : AppUpdateStatus.upToDate;
      final downloadedFilePath = status == AppUpdateStatus.updateAvailable
          ? await _validDownloadedPathFor(info, metadata.downloadedUpdatePath)
          : null;
      if (downloadedFilePath != null) {
        status = AppUpdateStatus.downloaded;
      }
      await _saveMetadata(
        AppUpdateMetadata(
          lastCheckAtMillis: checkedAt.millisecondsSinceEpoch,
          lastStatus: status,
          latestInfo: info,
          downloadedUpdatePath: downloadedFilePath,
        ),
      );
      return AppUpdateCheckResult(
        status: status,
        checkedAt: checkedAt,
        info: info,
        downloadedFilePath: downloadedFilePath,
      );
    } catch (error) {
      final message = error.toString();
      AppLogStore.warning('updates', 'GitHub update check failed: $message');
      final downloadedFilePath = await _validDownloadedPathFor(
        metadata.latestInfo,
        metadata.downloadedUpdatePath,
      );
      if (downloadedFilePath != null) {
        await _saveMetadata(
          AppUpdateMetadata(
            lastCheckAtMillis: checkedAt.millisecondsSinceEpoch,
            lastStatus: AppUpdateStatus.downloaded,
            lastError: message,
            latestInfo: metadata.latestInfo,
            downloadedUpdatePath: downloadedFilePath,
          ),
        );
        return AppUpdateCheckResult(
          status: AppUpdateStatus.downloaded,
          checkedAt: checkedAt,
          info: metadata.latestInfo,
          error: message,
          downloadedFilePath: downloadedFilePath,
        );
      }
      await _saveMetadata(
        AppUpdateMetadata(
          lastCheckAtMillis: checkedAt.millisecondsSinceEpoch,
          lastStatus: AppUpdateStatus.error,
          lastError: message,
          latestInfo: metadata.latestInfo,
          downloadedUpdatePath: metadata.downloadedUpdatePath,
        ),
      );
      return AppUpdateCheckResult(
        status: AppUpdateStatus.error,
        checkedAt: checkedAt,
        info: metadata.latestInfo,
        error: message,
      );
    }
  }

  Future<Map<String, dynamic>> _fetchLatestRelease() async {
    final client = HttpClient();
    try {
      client.connectionTimeout = const Duration(seconds: 12);
      final request = await client
          .getUrl(Uri.parse(_latestReleaseUrl))
          .timeout(const Duration(seconds: 15));
      request.headers.set('Accept', 'application/vnd.github+json');
      request.headers.set('User-Agent', 'Etonify-Android-Updater');
      final response = await request.close().timeout(
        const Duration(seconds: 20),
      );
      final body = await utf8.decoder.bind(response).join();
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException('GitHub returned HTTP ${response.statusCode}');
      }
      final decoded = jsonDecode(body);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('GitHub response is not an object.');
      }
      return decoded;
    } finally {
      client.close(force: true);
    }
  }

  Future<List<String>> _supportedAbis() async {
    try {
      final info = await SingboxRuntime.instance.getPlatformDeviceInfo();
      final raw = info['supportedAbis'];
      if (raw is Iterable) {
        return raw
            .map((value) => value.toString().trim())
            .where((value) => value.isNotEmpty)
            .toList(growable: false);
      }
      final abi = info['abi']?.toString().trim();
      if (abi != null && abi.isNotEmpty) {
        return [abi];
      }
    } catch (_) {}
    return const <String>[];
  }

  Future<void> downloadUpdate(
    AppUpdateInfo info, {
    required void Function(AppUpdateDownloadProgress progress) onProgress,
  }) async {
    final directory = await _updatesDirectory();
    final fileName = sanitizeAssetFileName(info.asset.name);
    final target = File('${directory.path}${Platform.pathSeparator}$fileName');
    final existingPath = await _validDownloadedPathFor(info, target.path);
    if (existingPath != null) {
      await cleanupOldDownloads(keepPath: existingPath);
      await _saveMetadata(
        AppUpdateMetadata(
          lastCheckAtMillis: DateTime.now().millisecondsSinceEpoch,
          lastStatus: AppUpdateStatus.downloaded,
          latestInfo: info,
          downloadedUpdatePath: existingPath,
        ),
      );
      onProgress(
        AppUpdateDownloadProgress(
          downloadedBytes: await File(existingPath).length(),
          totalBytes: info.asset.sizeBytes,
          bytesPerSecond: 0,
          done: true,
          filePath: existingPath,
        ),
      );
      return;
    }
    await cleanupOldDownloads(keepPath: target.path);
    final temp = File('${target.path}.part');
    if (target.existsSync()) {
      await target.delete();
    }
    if (temp.existsSync()) {
      await temp.delete();
    }
    final client = HttpClient();
    final startedAt = DateTime.now();
    var downloaded = 0;
    var lastEmitAt = startedAt;
    try {
      client.connectionTimeout = const Duration(seconds: 12);
      final request = await client
          .getUrl(Uri.parse(info.asset.downloadUrl))
          .timeout(const Duration(seconds: 15));
      request.headers.set('User-Agent', 'Etonify-Android-Updater');
      final response = await request.close().timeout(
        const Duration(seconds: 20),
      );
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException('Download returned HTTP ${response.statusCode}');
      }
      final totalBytes = response.contentLength > 0
          ? response.contentLength
          : info.asset.sizeBytes;
      final sink = temp.openWrite();
      try {
        await for (final chunk in response) {
          downloaded += chunk.length;
          sink.add(chunk);
          final now = DateTime.now();
          if (now.difference(lastEmitAt) >= const Duration(milliseconds: 250)) {
            lastEmitAt = now;
            onProgress(
              AppUpdateDownloadProgress(
                downloadedBytes: downloaded,
                totalBytes: totalBytes,
                bytesPerSecond: _speed(downloaded, startedAt, now),
                done: false,
              ),
            );
          }
        }
      } finally {
        await sink.flush();
        await sink.close();
      }
      if (target.existsSync()) {
        await target.delete();
      }
      await temp.rename(target.path);
      final verification = await verifyDownloadedApk(info, target.path);
      if (!verification.ok) {
        if (target.existsSync()) {
          await target.delete();
        }
        throw FormatException(
          verification.error ?? 'Downloaded APK checksum mismatch.',
        );
      }
      await _saveMetadata(
        AppUpdateMetadata(
          lastCheckAtMillis: DateTime.now().millisecondsSinceEpoch,
          lastStatus: AppUpdateStatus.downloaded,
          latestInfo: info,
          downloadedUpdatePath: target.path,
        ),
      );
      onProgress(
        AppUpdateDownloadProgress(
          downloadedBytes: downloaded,
          totalBytes: totalBytes,
          bytesPerSecond: _speed(downloaded, startedAt, DateTime.now()),
          done: true,
          filePath: target.path,
        ),
      );
      await cleanupOldDownloads(keepPath: target.path);
    } finally {
      client.close(force: true);
      if (temp.existsSync()) {
        await temp.delete();
      }
    }
  }

  static double _speed(int bytes, DateTime startedAt, DateTime now) {
    final seconds = now.difference(startedAt).inMilliseconds / 1000;
    if (seconds <= 0) return 0;
    return bytes / seconds;
  }

  Future<Directory> _updatesDirectory() async {
    final root = await getApplicationSupportDirectory();
    final directory = Directory('${root.path}${Platform.pathSeparator}updates');
    if (!directory.existsSync()) {
      directory.createSync(recursive: true);
    }
    return directory;
  }

  Future<void> cleanupOldDownloads({String? keepPath}) async {
    final directory = await _updatesDirectory();
    final keep = keepPath?.trim();
    if (!directory.existsSync()) return;
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is! File) continue;
      final name = entity.uri.pathSegments.last.toLowerCase();
      final matches =
          name.startsWith('etonify-') &&
          (name.endsWith('.apk') || name.endsWith('.apk.part'));
      if (!matches) continue;
      if (keep != null && entity.path == keep) continue;
      await entity.delete();
    }
  }

  Future<int> deleteCachedInstallers({required String currentVersion}) async {
    final directory = await _updatesDirectory();
    var deleted = 0;
    if (directory.existsSync()) {
      await for (final entity in directory.list(followLinks: false)) {
        if (entity is! File) continue;
        final name = entity.uri.pathSegments.last.toLowerCase();
        final matches =
            name.startsWith('etonify-') &&
            (name.endsWith('.apk') || name.endsWith('.apk.part'));
        if (!matches) continue;
        try {
          await entity.delete();
          deleted++;
        } catch (error) {
          AppLogStore.warning(
            'updates',
            'Failed to delete cached update APK: $error',
          );
        }
      }
    }

    final metadata = await loadMetadata();
    final info = metadata.latestInfo;
    final status = info == null
        ? AppUpdateStatus.unknown
        : isRemoteVersionNewer(info.version, currentVersion)
        ? AppUpdateStatus.updateAvailable
        : AppUpdateStatus.upToDate;
    await _saveMetadata(
      AppUpdateMetadata(
        lastCheckAtMillis: metadata.lastCheckAtMillis,
        lastStatus: status,
        lastError: metadata.lastError,
        latestInfo: info,
      ),
    );
    return deleted;
  }

  Future<String?> _validDownloadedPathFor(
    AppUpdateInfo? info,
    String? path,
  ) async {
    if (info == null) return null;
    final normalizedPath = path?.trim();
    if (normalizedPath == null || normalizedPath.isEmpty) return null;
    final file = File(normalizedPath);
    if (!file.existsSync()) return null;
    if (!file.path.toLowerCase().endsWith('.apk')) return null;
    final expectedName = sanitizeAssetFileName(info.asset.name).toLowerCase();
    final actualName = file.uri.pathSegments.last.toLowerCase();
    if (actualName != expectedName) return null;
    final length = await file.length();
    if (length <= 0) return null;
    if (info.asset.sizeBytes > 0 && length != info.asset.sizeBytes) {
      return null;
    }
    final verification = await verifyDownloadedApk(info, file.path);
    if (!verification.ok) {
      return null;
    }
    return file.path;
  }

  Future<AppUpdateVerificationResult> verifyDownloadedApk(
    AppUpdateInfo info,
    String path,
  ) async {
    final expected = info.asset.digestSha256;
    if (expected == null || expected.isEmpty) {
      return const AppUpdateVerificationResult(ok: true);
    }
    final file = File(path);
    if (!file.existsSync()) {
      return AppUpdateVerificationResult(
        ok: false,
        expectedSha256: expected,
        error: 'Downloaded APK file is missing.',
      );
    }
    try {
      final actual = await sha256File(file);
      final ok = actual == expected;
      return AppUpdateVerificationResult(
        ok: ok,
        expectedSha256: expected,
        actualSha256: actual,
        error: ok ? null : 'Downloaded APK checksum mismatch.',
      );
    } catch (error) {
      return AppUpdateVerificationResult(
        ok: false,
        expectedSha256: expected,
        error: error.toString(),
      );
    }
  }

  @visibleForTesting
  static Future<String> sha256File(File file) async {
    final digest = await crypto.sha256.bind(file.openRead()).first;
    return digest.toString().toLowerCase();
  }

  static List<AppUpdateAsset> _parseAssets(Object? value) {
    if (value is! Iterable) return const <AppUpdateAsset>[];
    final result = <AppUpdateAsset>[];
    for (final item in value) {
      if (item is! Map) continue;
      final name = item['name']?.toString().trim() ?? '';
      final url = item['browser_download_url']?.toString().trim() ?? '';
      if (name.isEmpty || url.isEmpty || !name.toLowerCase().endsWith('.apk')) {
        continue;
      }
      result.add(
        AppUpdateAsset(
          name: name,
          downloadUrl: url,
          sizeBytes: int.tryParse(item['size']?.toString() ?? '') ?? 0,
          digestSha256: normalizeSha256Digest(item['digest']),
        ),
      );
    }
    return result;
  }

  @visibleForTesting
  static AppUpdateAsset? selectAssetForAbis(
    List<AppUpdateAsset> assets,
    List<String> supportedAbis,
  ) {
    final normalizedAbis = supportedAbis
        .map((value) => value.toLowerCase().trim())
        .where((value) => value.isNotEmpty)
        .toList(growable: false);
    final abiPriority = normalizedAbis
        .where(_assetTokens.contains)
        .toList(growable: false);
    for (final abi in abiPriority) {
      final match = assets.firstWhereOrNull(
        (asset) => asset.name.toLowerCase().contains(abi),
      );
      if (match != null) return match;
    }
    return assets.firstWhereOrNull(
      (asset) => asset.name.toLowerCase().contains('universal'),
    );
  }

  static String normalizeVersion(String value) {
    final trimmed = value.trim();
    final match = RegExp(r'v?(\d+(?:\.\d+){1,3})').firstMatch(trimmed);
    return match?.group(1) ?? '';
  }

  @visibleForTesting
  static String? normalizeSha256Digest(Object? value) {
    final raw = value?.toString().trim().toLowerCase();
    if (raw == null || raw.isEmpty) return null;
    final match = RegExp(r'(?:sha256:)?([a-f0-9]{64})').firstMatch(raw);
    return match?.group(1);
  }

  @visibleForTesting
  static bool isRemoteVersionNewer(
    String remoteVersion,
    String currentVersion,
  ) {
    final remote = _versionParts(normalizeVersion(remoteVersion));
    final current = _versionParts(normalizeVersion(currentVersion));
    for (var i = 0; i < max(remote.length, current.length); i++) {
      final r = i < remote.length ? remote[i] : 0;
      final c = i < current.length ? current[i] : 0;
      if (r > c) return true;
      if (r < c) return false;
    }
    return false;
  }

  static List<int> _versionParts(String version) => version
      .split('.')
      .map((value) => int.tryParse(value) ?? 0)
      .toList(growable: false);

  @visibleForTesting
  static String sanitizeAssetFileName(String name) {
    final sanitized = name
        .trim()
        .replaceAll(RegExp(r'[^a-zA-Z0-9._-]+'), '-')
        .replaceAll(RegExp(r'-+'), '-');
    if (sanitized.isEmpty || !sanitized.toLowerCase().endsWith('.apk')) {
      return 'etonify-update.apk';
    }
    return sanitized;
  }
}

extension _FirstWhereOrNull<T> on Iterable<T> {
  T? firstWhereOrNull(bool Function(T value) test) {
    for (final value in this) {
      if (test(value)) return value;
    }
    return null;
  }
}
