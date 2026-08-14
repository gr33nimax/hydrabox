import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/foundation.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:hydrabox/data/local/app_settings_store.dart';
import 'package:hydrabox/data/local/hive_storage_diagnostics.dart';
import 'package:hydrabox/logging/app_log_store.dart';
import 'package:hydrabox/singbox/singbox_runtime.dart';
import 'package:path_provider/path_provider.dart';

enum AppUpdateStatus {
  unknown,
  disabled,
  checking,
  upToDate,
  updateAvailable,
  unsupportedAndroid,
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

  AppUpdateAsset copyWith({int? sizeBytes, String? digestSha256}) =>
      AppUpdateAsset(
        name: name,
        downloadUrl: downloadUrl,
        sizeBytes: sizeBytes ?? this.sizeBytes,
        digestSha256: digestSha256 ?? this.digestSha256,
      );

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
    this.buildNumber,
    required this.tagName,
    required this.title,
    required this.body,
    required this.htmlUrl,
    required this.publishedAt,
    required this.asset,
    this.minimumAndroidSdk,
    this.packageName,
  });

  final String version;
  final int? buildNumber;
  final String tagName;
  final String title;
  final String body;
  final String htmlUrl;
  final DateTime? publishedAt;
  final AppUpdateAsset asset;
  final int? minimumAndroidSdk;
  final String? packageName;

  String get displayVersion => version;

  String get technicalVersion =>
      buildNumber == null ? version : '$version+$buildNumber';

  Map<String, Object?> toMap() => {
    'version': version,
    'buildNumber': buildNumber,
    'tagName': tagName,
    'title': title,
    'body': body,
    'htmlUrl': htmlUrl,
    'publishedAtMillis': publishedAt?.millisecondsSinceEpoch,
    'asset': asset.toMap(),
    'minimumAndroidSdk': minimumAndroidSdk,
    'packageName': packageName,
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
      buildNumber:
          AppUpdateService.parseBuildNumber(value['buildNumber']) ??
          AppUpdateService.extractBuildNumber(
            value['version']?.toString() ?? '',
          ),
      tagName: tagName,
      title: value['title']?.toString().trim() ?? 'v$version',
      body: value['body']?.toString() ?? '',
      htmlUrl: value['htmlUrl']?.toString().trim() ?? '',
      publishedAt: publishedAtMillis == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(publishedAtMillis),
      asset: asset,
      minimumAndroidSdk: AppUpdateService.parsePositiveInt(
        value['minimumAndroidSdk'],
      ),
      packageName: value['packageName']?.toString().trim(),
    );
  }
}

class AppUpdateManifest {
  const AppUpdateManifest({
    required this.releaseSequence,
    required this.sourceCommit,
    required this.publishedAt,
    required this.keyId,
    required this.version,
    required this.buildNumber,
    required this.minimumAndroidSdk,
    required this.packageName,
    required this.assets,
  });

  final int releaseSequence;
  final String sourceCommit;
  final DateTime publishedAt;
  final String keyId;
  final String version;
  final int? buildNumber;
  final int? minimumAndroidSdk;
  final String packageName;
  final Map<String, ({int sizeBytes, String? sha256})> assets;

  static AppUpdateManifest? fromJson(Object? value) {
    if (value is! Map) return null;
    if (value['schemaVersion'] != 1 ||
        value['distributionId'] != 'io.hydrabox.client') {
      return null;
    }
    final releaseSequence = AppUpdateService.parsePositiveInt(
      value['releaseSequence'],
    );
    final sourceCommit = value['sourceCommit']?.toString().trim() ?? '';
    final publishedAt = DateTime.tryParse(
      value['publishedAt']?.toString() ?? '',
    );
    final keyId = value['keyId']?.toString().trim() ?? '';
    final version = AppUpdateService.normalizeVersion(
      value['version']?.toString() ?? '',
    );
    final packageName = value['packageName']?.toString().trim() ?? '';
    final rawAssets = value['assets'];
    if (releaseSequence == null ||
        !RegExp(r'^[0-9a-f]{40}$').hasMatch(sourceCommit) ||
        publishedAt == null ||
        !RegExp(r'^[A-Za-z0-9._-]{1,64}$').hasMatch(keyId) ||
        version.isEmpty ||
        packageName != 'io.hydrabox.client' ||
        rawAssets is! Iterable) {
      return null;
    }
    final assets = <String, ({int sizeBytes, String? sha256})>{};
    for (final raw in rawAssets) {
      if (raw is! Map) continue;
      final name = raw['name']?.toString().trim() ?? '';
      final sizeBytes = int.tryParse(raw['sizeBytes']?.toString() ?? '') ?? 0;
      final sha256 = AppUpdateService.normalizeSha256Digest(raw['sha256']);
      if (name.isEmpty ||
          !name.toLowerCase().endsWith('.apk') ||
          sizeBytes <= 0 ||
          sha256 == null ||
          assets.containsKey(name)) {
        return null;
      }
      assets[name] = (sizeBytes: sizeBytes, sha256: sha256);
    }
    if (assets.isEmpty) return null;
    return AppUpdateManifest(
      releaseSequence: releaseSequence,
      sourceCommit: sourceCommit,
      publishedAt: publishedAt.toUtc(),
      keyId: keyId,
      version: version,
      buildNumber: AppUpdateService.parseBuildNumber(value['buildNumber']),
      minimumAndroidSdk: AppUpdateService.parsePositiveInt(value['minSdk']),
      packageName: packageName,
      assets: Map.unmodifiable(assets),
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
    this.stage = AppUpdateDownloadStage.downloading,
  });

  final int downloadedBytes;
  final int totalBytes;
  final double bytesPerSecond;
  final bool done;
  final String? filePath;
  final AppUpdateDownloadStage stage;

  double? get fraction =>
      totalBytes <= 0 ? null : (downloadedBytes / totalBytes).clamp(0.0, 1.0);

  int? get etaSeconds {
    if (bytesPerSecond <= 1 || totalBytes <= 0) return null;
    final remaining = totalBytes - downloadedBytes;
    if (remaining <= 0) return 0;
    return (remaining / bytesPerSecond).ceil();
  }
}

enum AppUpdateDownloadStage { cleaning, downloading, verifying, ready }

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

class AppUpdateCleanupResult {
  const AppUpdateCleanupResult({
    required this.deletedFiles,
    required this.metadataChanged,
    required this.installedAtLeastLatest,
  });

  final int deletedFiles;
  final bool metadataChanged;
  final bool installedAtLeastLatest;

  bool get changed => deletedFiles > 0 || metadataChanged;
}

class AppUpdateService {
  AppUpdateService._();

  static final AppUpdateService instance = AppUpdateService._();
  static const checkInterval = Duration(hours: 24);
  static const repositoryOwner = String.fromEnvironment(
    'HYDRABOX_UPDATE_REPOSITORY_OWNER',
  );
  static const repositoryName = String.fromEnvironment(
    'HYDRABOX_UPDATE_REPOSITORY_NAME',
  );
  static const _metadataBoxName = 'app_update_state';
  static const _assetTokens = ['arm64-v8a', 'armeabi-v7a', 'x86_64'];
  static const _manifestAssetName = 'hydrabox-update.json';
  static const _manifestSignatureAssetName = 'hydrabox-update.json.sig';
  Future<AppUpdateCheckResult>? _checkInFlight;

  /// Automatic updates stay fail-closed until a HydraBox-controlled release
  /// repository is supplied explicitly at build time.
  static bool get updatesConfigured =>
      repositoryOwner.trim().isNotEmpty && repositoryName.trim().isNotEmpty;

  static String get _latestReleaseUrl =>
      'https://api.github.com/repos/$repositoryOwner/$repositoryName/releases/latest';

  Future<Box<dynamic>> _openBox() async {
    await HiveAppSettingsStore.initHive();
    final stopwatch = Stopwatch()..start();
    final box = Hive.isBoxOpen(_metadataBoxName)
        ? Hive.box<dynamic>(_metadataBoxName)
        : await Hive.openBox<dynamic>(_metadataBoxName);
    stopwatch.stop();
    await HiveStorageDiagnostics.logBoxOnce(
      label: _metadataBoxName,
      box: box,
      openElapsed: stopwatch.elapsed,
    );
    return box;
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
    int? currentBuildNumber,
    bool manual = false,
  }) {
    final inFlight = _checkInFlight;
    if (inFlight != null) return inFlight;
    final operation = _checkForUpdates(
      currentVersion: currentVersion,
      currentBuildNumber: currentBuildNumber,
      manual: manual,
    );
    _checkInFlight = operation;
    return operation.whenComplete(() {
      if (identical(_checkInFlight, operation)) _checkInFlight = null;
    });
  }

  Future<AppUpdateCheckResult> _checkForUpdates({
    required String currentVersion,
    int? currentBuildNumber,
    required bool manual,
  }) async {
    if (!updatesConfigured) {
      return AppUpdateCheckResult(
        status: AppUpdateStatus.disabled,
        checkedAt: DateTime.now(),
      );
    }
    final metadata = await loadMetadata();
    final cachedInfoMissingDigest =
        metadata.latestInfo != null &&
        metadata.latestInfo!.asset.digestSha256 == null;
    if (!manual && !metadata.isDue && !cachedInfoMissingDigest) {
      final cached = await _cachedCheckResultFor(
        metadata,
        currentVersion: currentVersion,
        currentBuildNumber: currentBuildNumber,
      );
      if (cached != null) {
        return cached;
      }
    }

    final checkedAt = DateTime.now();
    try {
      final release = await _fetchLatestRelease();
      final manifest = await _fetchReleaseManifest(release['assets']);
      final assets = _parseAssets(release['assets'])
          .where((asset) => manifest.assets.containsKey(asset.name))
          .map((asset) {
            final metadata = manifest.assets[asset.name]!;
            return asset.copyWith(
              sizeBytes: metadata.sizeBytes,
              digestSha256: metadata.sha256,
            );
          })
          .toList(growable: false);
      final supportedAbis = await _supportedAbis();
      final asset = selectAssetForAbis(assets, supportedAbis);
      if (asset == null) {
        throw const FormatException('No compatible APK asset found.');
      }
      final tagName = release['tag_name']?.toString().trim() ?? '';
      final title = release['name']?.toString().trim().isNotEmpty == true
          ? release['name'].toString().trim()
          : '';
      final body = release['body']?.toString() ?? '';
      final version = normalizeVersion(tagName).isNotEmpty
          ? normalizeVersion(tagName)
          : normalizeVersion('$title\n$body\n${asset.name}');
      if (version.isEmpty) {
        throw const FormatException('Release tag does not contain a version.');
      }
      if (version != manifest.version) {
        throw const FormatException(
          'Release tag does not match the signed update manifest.',
        );
      }
      final info = AppUpdateInfo(
        version: manifest.version,
        buildNumber: manifest.buildNumber,
        tagName: tagName,
        title: title.isNotEmpty ? title : 'v$version',
        body: body,
        htmlUrl: release['html_url']?.toString().trim() ?? '',
        publishedAt: manifest.publishedAt,
        asset: asset,
        minimumAndroidSdk: manifest.minimumAndroidSdk,
        packageName: manifest.packageName,
      );
      final remoteIsNewer = isRemoteVersionNewer(
        info.version,
        currentVersion,
        remoteBuildNumber: info.buildNumber,
        currentBuildNumber: currentBuildNumber,
      );
      final deviceSdk = await _androidSdkInt();
      final unsupportedAndroid =
          remoteIsNewer &&
          info.minimumAndroidSdk != null &&
          deviceSdk != null &&
          deviceSdk < info.minimumAndroidSdk!;
      var status = unsupportedAndroid
          ? AppUpdateStatus.unsupportedAndroid
          : remoteIsNewer
          ? AppUpdateStatus.updateAvailable
          : AppUpdateStatus.upToDate;
      final downloadedFilePath = status == AppUpdateStatus.updateAvailable
          ? await _validDownloadedPathFor(info, metadata.downloadedUpdatePath)
          : null;
      if (downloadedFilePath != null) {
        status = AppUpdateStatus.downloaded;
      } else if (!remoteIsNewer) {
        await _deleteCachedUpdateFiles();
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
      final cached = await _cachedCheckResultFor(
        metadata,
        currentVersion: currentVersion,
        currentBuildNumber: currentBuildNumber,
        checkedAt: checkedAt,
        error: message,
      );
      if (cached != null) {
        return cached;
      }
      await _saveMetadata(
        AppUpdateMetadata(
          lastCheckAtMillis: checkedAt.millisecondsSinceEpoch,
          lastStatus: AppUpdateStatus.error,
          lastError: message,
          latestInfo: metadata.latestInfo,
          downloadedUpdatePath: null,
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

  Future<AppUpdateCheckResult?> _cachedCheckResultFor(
    AppUpdateMetadata metadata, {
    required String currentVersion,
    int? currentBuildNumber,
    DateTime? checkedAt,
    String? error,
  }) async {
    final info = metadata.latestInfo;
    if (info == null) {
      return null;
    }
    final remoteIsNewer = isRemoteVersionNewer(
      info.version,
      currentVersion,
      remoteBuildNumber: info.buildNumber,
      currentBuildNumber: currentBuildNumber,
    );
    if (!remoteIsNewer) {
      final deleted = await _deleteCachedUpdateFiles();
      await _saveMetadata(
        AppUpdateMetadata(
          lastCheckAtMillis:
              checkedAt?.millisecondsSinceEpoch ?? metadata.lastCheckAtMillis,
          lastStatus: AppUpdateStatus.upToDate,
          lastError: error,
          latestInfo: info,
          downloadedUpdatePath: null,
        ),
      );
      if (deleted > 0) {
        AppLogStore.info(
          'updates',
          'removed stale cached update files count=$deleted '
              'installed=$currentVersion latest=${info.technicalVersion}',
        );
      }
      return AppUpdateCheckResult(
        status: AppUpdateStatus.upToDate,
        checkedAt: checkedAt ?? metadata.lastCheckAt ?? DateTime.now(),
        info: info,
        error: error,
      );
    }

    final deviceSdk = await _androidSdkInt();
    if (info.minimumAndroidSdk != null &&
        deviceSdk != null &&
        deviceSdk < info.minimumAndroidSdk!) {
      await _deleteCachedUpdateFiles();
      return AppUpdateCheckResult(
        status: AppUpdateStatus.unsupportedAndroid,
        checkedAt: checkedAt ?? metadata.lastCheckAt ?? DateTime.now(),
        info: info,
        error: error ?? metadata.lastError,
        fromCache: checkedAt == null,
      );
    }

    final downloadedFilePath = await _validDownloadedPathFor(
      info,
      metadata.downloadedUpdatePath,
    );
    final status = downloadedFilePath != null
        ? AppUpdateStatus.downloaded
        : metadata.lastStatus == AppUpdateStatus.downloaded
        ? AppUpdateStatus.updateAvailable
        : metadata.lastStatus;
    return AppUpdateCheckResult(
      status: status,
      checkedAt: checkedAt ?? metadata.lastCheckAt ?? DateTime.now(),
      info: info,
      error: error ?? metadata.lastError,
      fromCache: checkedAt == null,
      downloadedFilePath: downloadedFilePath,
    );
  }

  Future<AppUpdateCleanupResult> cleanupInstalledUpdateArtifacts({
    required String currentVersion,
    int? currentBuildNumber,
  }) async {
    final metadata = await loadMetadata();
    final info = metadata.latestInfo;
    final installedAtLeastLatest =
        info == null ||
        !isRemoteVersionNewer(
          info.version,
          currentVersion,
          remoteBuildNumber: info.buildNumber,
          currentBuildNumber: currentBuildNumber,
        );
    if (!installedAtLeastLatest) {
      final downloadedFilePath = await _validDownloadedPathFor(
        info,
        metadata.downloadedUpdatePath,
      );
      final deleted = await cleanupOldDownloads(keepPath: downloadedFilePath);
      return AppUpdateCleanupResult(
        deletedFiles: deleted,
        metadataChanged: false,
        installedAtLeastLatest: false,
      );
    }

    final deleted = await _deleteCachedUpdateFiles();
    final nextStatus = info == null
        ? AppUpdateStatus.unknown
        : AppUpdateStatus.upToDate;
    final metadataChanged =
        metadata.lastStatus != nextStatus ||
        metadata.downloadedUpdatePath != null ||
        metadata.lastError != null;
    if (metadataChanged) {
      await _saveMetadata(
        AppUpdateMetadata(
          lastCheckAtMillis: metadata.lastCheckAtMillis,
          lastStatus: nextStatus,
          latestInfo: info,
        ),
      );
    }
    return AppUpdateCleanupResult(
      deletedFiles: deleted,
      metadataChanged: metadataChanged,
      installedAtLeastLatest: true,
    );
  }

  Future<Map<String, dynamic>> _fetchLatestRelease() async {
    final client = HttpClient();
    try {
      client.connectionTimeout = const Duration(seconds: 12);
      final request = await client
          .getUrl(Uri.parse(_latestReleaseUrl))
          .timeout(const Duration(seconds: 15));
      request.headers.set('Accept', 'application/vnd.github+json');
      request.headers.set('User-Agent', 'HydraBox-Android-Updater');
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

  Future<AppUpdateManifest> _fetchReleaseManifest(Object? rawAssets) async {
    if (rawAssets is! Iterable) {
      throw const FormatException('GitHub release assets are unavailable.');
    }
    Map? manifestAsset;
    Map? signatureAsset;
    for (final raw in rawAssets) {
      if (raw is Map && raw['name']?.toString() == _manifestAssetName) {
        manifestAsset = raw;
      } else if (raw is Map &&
          raw['name']?.toString() == _manifestSignatureAssetName) {
        signatureAsset = raw;
      }
    }
    final manifestUrl = Uri.tryParse(
      manifestAsset?['browser_download_url']?.toString().trim() ?? '',
    );
    final signatureUrl = Uri.tryParse(
      signatureAsset?['browser_download_url']?.toString().trim() ?? '',
    );
    if (manifestUrl == null ||
        signatureUrl == null ||
        manifestUrl.scheme != 'https' ||
        signatureUrl.scheme != 'https') {
      throw const FormatException(
        'Signed update manifest assets are unavailable.',
      );
    }
    final client = HttpClient();
    try {
      client.connectionTimeout = const Duration(seconds: 12);
      Future<Uint8List> download(Uri url, int maximumBytes) async {
        final request = await client
            .getUrl(url)
            .timeout(const Duration(seconds: 15));
        request.maxRedirects = 4;
        request.headers.set('Accept', 'application/octet-stream');
        request.headers.set('User-Agent', 'HydraBox-Android-Updater');
        final response = await request.close().timeout(
          const Duration(seconds: 20),
        );
        if (response.statusCode != HttpStatus.ok ||
            response.redirects.any(
              (redirect) => redirect.location.scheme != 'https',
            )) {
          throw HttpException(
            'GitHub returned an invalid signed-manifest response.',
          );
        }
        final bytes = await response.fold<List<int>>(<int>[], (all, chunk) {
          if (all.length + chunk.length > maximumBytes) {
            throw const FormatException('Update manifest asset is too large.');
          }
          return all..addAll(chunk);
        });
        return Uint8List.fromList(bytes);
      }

      final manifestBytes = await download(manifestUrl, 256 * 1024);
      final signatureBytes = await download(signatureUrl, 64);
      if (signatureBytes.length != 64) {
        throw const FormatException('Update manifest signature is invalid.');
      }
      final verifiedSequence = await SingboxRuntime.instance
          .verifyAppUpdateManifest(manifestBytes, signatureBytes);
      final manifest = AppUpdateManifest.fromJson(
        jsonDecode(utf8.decode(manifestBytes, allowMalformed: false)),
      );
      if (manifest == null || manifest.releaseSequence != verifiedSequence) {
        throw const FormatException('Signed update manifest is invalid.');
      }
      return manifest;
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

  Future<int?> _androidSdkInt() async {
    try {
      final info = await SingboxRuntime.instance.getPlatformDeviceInfo();
      return parsePositiveInt(info['sdkInt']);
    } catch (_) {
      return null;
    }
  }

  Future<void> downloadUpdate(
    AppUpdateInfo info, {
    required void Function(AppUpdateDownloadProgress progress) onProgress,
  }) async {
    final directory = await _updatesDirectory();
    final fileName = sanitizeAssetFileName(info.asset.name);
    final target = File('${directory.path}${Platform.pathSeparator}$fileName');
    onProgress(
      const AppUpdateDownloadProgress(
        downloadedBytes: 0,
        totalBytes: 0,
        bytesPerSecond: 0,
        done: false,
        stage: AppUpdateDownloadStage.cleaning,
      ),
    );
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
          stage: AppUpdateDownloadStage.ready,
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
      request.headers.set('User-Agent', 'HydraBox-Android-Updater');
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
      onProgress(
        AppUpdateDownloadProgress(
          downloadedBytes: downloaded,
          totalBytes: totalBytes,
          bytesPerSecond: _speed(downloaded, startedAt, DateTime.now()),
          done: false,
          stage: AppUpdateDownloadStage.verifying,
        ),
      );
      final verification = await verifyDownloadedApk(info, target.path);
      if (!verification.ok) {
        if (target.existsSync()) {
          await target.delete();
        }
        throw FormatException(
          verification.error ?? 'Downloaded APK checksum mismatch.',
        );
      }
      final compatibility = await verifyDownloadedApkCompatibility(
        info,
        target.path,
      );
      if (!compatibility.ok) {
        if (target.existsSync()) await target.delete();
        throw FormatException(
          compatibility.error ?? 'Downloaded APK is incompatible.',
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
          stage: AppUpdateDownloadStage.ready,
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

  Future<int> cleanupOldDownloads({String? keepPath}) {
    return _deleteCachedUpdateFiles(keepPath: keepPath);
  }

  Future<int> _deleteCachedUpdateFiles({String? keepPath}) async {
    final directory = await _updatesDirectory();
    final keep = keepPath?.trim();
    var deleted = 0;
    if (!directory.existsSync()) return deleted;
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is! File) continue;
      final name = entity.uri.pathSegments.last.toLowerCase();
      // This directory belongs exclusively to the updater. Do not depend on
      // a release asset naming convention: older or manually renamed assets
      // must not survive forever as stale installer files.
      final matches = name.endsWith('.apk') || name.endsWith('.apk.part');
      if (!matches) continue;
      if (keep != null && entity.path == keep) continue;
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
    return deleted;
  }

  Future<int> deleteCachedInstallers({
    required String currentVersion,
    int? currentBuildNumber,
  }) async {
    final deleted = await _deleteCachedUpdateFiles();
    final metadata = await loadMetadata();
    final info = metadata.latestInfo;
    final status = info == null
        ? AppUpdateStatus.unknown
        : isRemoteVersionNewer(
            info.version,
            currentVersion,
            remoteBuildNumber: info.buildNumber,
            currentBuildNumber: currentBuildNumber,
          )
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
    final compatibility = await verifyDownloadedApkCompatibility(
      info,
      file.path,
    );
    if (!compatibility.ok) {
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

  Future<AppUpdateVerificationResult> verifyDownloadedApkCompatibility(
    AppUpdateInfo info,
    String path,
  ) async {
    if (!Platform.isAndroid) {
      return const AppUpdateVerificationResult(ok: true);
    }
    try {
      final archive = await SingboxRuntime.instance.inspectDownloadedApk(path);
      if (archive['valid'] != true) {
        return const AppUpdateVerificationResult(
          ok: false,
          error: 'Android could not read the downloaded APK.',
        );
      }
      final packageName = archive['packageName']?.toString().trim() ?? '';
      final installedPackage =
          archive['installedPackageName']?.toString().trim() ?? '';
      final expectedPackage = info.packageName?.trim().isNotEmpty == true
          ? info.packageName!.trim()
          : installedPackage;
      if (expectedPackage.isNotEmpty && packageName != expectedPackage) {
        return AppUpdateVerificationResult(
          ok: false,
          error: 'Downloaded APK has a different package name: $packageName.',
        );
      }
      final minSdk = parsePositiveInt(archive['minSdk']);
      final deviceSdk = parsePositiveInt(archive['deviceSdk']);
      if (minSdk != null && deviceSdk != null && minSdk > deviceSdk) {
        return AppUpdateVerificationResult(
          ok: false,
          error:
              'This update requires Android SDK $minSdk, device has $deviceSdk.',
        );
      }
      final archiveCertificates = _stringSet(
        archive['signingCertificateSha256'],
      );
      final installedCertificates = _stringSet(
        archive['installedCertificateSha256'],
      );
      if (archiveCertificates.isEmpty ||
          installedCertificates.isEmpty ||
          archiveCertificates.intersection(installedCertificates).isEmpty) {
        return const AppUpdateVerificationResult(
          ok: false,
          error: 'Downloaded APK signature does not match installed HydraBox.',
        );
      }
      return const AppUpdateVerificationResult(ok: true);
    } catch (error) {
      return AppUpdateVerificationResult(ok: false, error: error.toString());
    }
  }

  static Set<String> _stringSet(Object? value) {
    if (value is! Iterable) return const <String>{};
    return value
        .map((item) => normalizeSha256Digest(item))
        .whereType<String>()
        .toSet();
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
  static int? extractBuildNumber(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;
    final versionBuild = RegExp(
      r'\b\d+(?:\.\d+){1,3}\+(\d+)\b',
    ).firstMatch(trimmed);
    final fromVersion = parseBuildNumber(versionBuild?.group(1));
    if (fromVersion != null) return fromVersion;
    final buildLabel = RegExp(
      r'\b(?:build|versionCode|version_code)\s*[:=#]?\s*(\d+)\b',
      caseSensitive: false,
    ).firstMatch(trimmed);
    return parseBuildNumber(buildLabel?.group(1));
  }

  @visibleForTesting
  static int? parseBuildNumber(Object? value) {
    final raw = value?.toString().trim() ?? '';
    if (raw.isEmpty) return null;
    final parsed = int.tryParse(raw);
    return parsed == null || parsed <= 0 ? null : parsed;
  }

  @visibleForTesting
  static int? parsePositiveInt(Object? value) {
    final parsed = int.tryParse(value?.toString().trim() ?? '');
    return parsed == null || parsed < 0 ? null : parsed;
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
    String currentVersion, {
    int? remoteBuildNumber,
    int? currentBuildNumber,
  }) {
    final remote = _versionParts(normalizeVersion(remoteVersion));
    final current = _versionParts(normalizeVersion(currentVersion));
    for (var i = 0; i < max(remote.length, current.length); i++) {
      final r = i < remote.length ? remote[i] : 0;
      final c = i < current.length ? current[i] : 0;
      if (r > c) return true;
      if (r < c) return false;
    }
    final remoteBuild =
        parseBuildNumber(remoteBuildNumber) ??
        extractBuildNumber(remoteVersion);
    final currentBuild =
        parseBuildNumber(currentBuildNumber) ??
        extractBuildNumber(currentVersion);
    if (remoteBuild != null && currentBuild != null) {
      return remoteBuild > currentBuild;
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
      return 'hydrabox-update.apk';
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
