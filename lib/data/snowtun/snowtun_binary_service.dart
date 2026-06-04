import 'dart:ffi';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:jni/jni.dart';
import 'package:jni_flutter/jni_flutter.dart';
import 'package:pointycastle/digests/sha256.dart';

import 'package:meow_client/singbox/singbox_runtime.dart';

class SnowtunBinaryStatus {
  const SnowtunBinaryStatus({
    required this.available,
    required this.manifestUrl,
    this.binaryPath,
    this.version,
    this.artifactAbi,
    this.binarySha256,
    this.binarySizeBytes = 0,
    this.chunkCount = 0,
    this.installedAtMillis,
  });

  const SnowtunBinaryStatus.unavailable({this.manifestUrl = ''})
    : available = false,
      binaryPath = null,
      version = null,
      artifactAbi = null,
      binarySha256 = null,
      binarySizeBytes = 0,
      chunkCount = 0,
      installedAtMillis = null;

  final bool available;
  final String manifestUrl;
  final String? binaryPath;
  final String? version;
  final String? artifactAbi;
  final String? binarySha256;
  final int binarySizeBytes;
  final int chunkCount;
  final int? installedAtMillis;

  DateTime? get installedAt => installedAtMillis == null
      ? null
      : DateTime.fromMillisecondsSinceEpoch(installedAtMillis!);
}

enum SnowtunDownloadPhase { fetchingManifest, downloadingChunks, finalizing }

const _maxSnowtunManifestBytes = 512 * 1024;
const _maxSnowtunArtifactBytes = 128 * 1024 * 1024;
const _maxSnowtunChunkBytes = 32 * 1024 * 1024;

List<String> resolveSnowtunArtifactKeysForCurrentPlatform({Abi? abi}) {
  final currentAbi = abi ?? Abi.current();
  final candidates = switch (currentAbi) {
    Abi.androidArm64 => ['arm64-v8a', 'arm64', 'aarch64'],
    Abi.androidArm => ['armeabi-v7a', 'armeabi', 'armv7', 'arm'],
    Abi.androidX64 => ['x86_64', 'amd64'],
    Abi.androidIA32 => ['x86', 'i686', 'i386'],
    Abi.linuxArm64 => ['linux-arm64', 'arm64', 'aarch64'],
    Abi.linuxArm => ['linux-armv7', 'linux-arm', 'armv7', 'arm'],
    Abi.linuxX64 => ['linux-x86_64', 'x86_64', 'amd64'],
    Abi.linuxIA32 => ['linux-x86', 'x86', 'i686', 'i386'],
    Abi.macosArm64 => ['darwin-arm64', 'macos-arm64', 'arm64', 'aarch64'],
    Abi.macosX64 => ['darwin-x86_64', 'macos-x86_64', 'x86_64', 'amd64'],
    Abi.windowsArm64 => ['windows-arm64', 'arm64', 'aarch64'],
    Abi.windowsX64 => ['windows-x86_64', 'x86_64', 'amd64'],
    Abi.windowsIA32 => ['windows-x86', 'x86', 'i686', 'i386'],
    _ => <String>[],
  };
  return <String>[...candidates, 'universal', 'all', 'any'];
}

class SnowtunDownloadProgress {
  const SnowtunDownloadProgress({
    required this.phase,
    required this.downloadedChunks,
    required this.totalChunks,
    required this.downloadedBytes,
    required this.totalBytes,
  });

  final SnowtunDownloadPhase phase;
  final int downloadedChunks;
  final int totalChunks;
  final int downloadedBytes;
  final int totalBytes;

  double? get progress {
    if (totalBytes <= 0) {
      return null;
    }
    return downloadedBytes.clamp(0, totalBytes) / totalBytes;
  }
}

class SnowtunBinaryService {
  SnowtunBinaryService._();

  static final SnowtunBinaryService instance = SnowtunBinaryService._();
  static const defaultManifestUrl =
      'https://xtun.ddosxd.ru/snowtun/manifest.json';
  static const defaultSplitName = 'snowtun';
  static const defaultPackageName = 'com.etonify.meow_client';
  static const defaultNativeLibraryName = 'libsnowtun.so';

  Future<SnowtunBinaryStatus> loadStatus() async {
    if (!Platform.isAndroid) {
      return const SnowtunBinaryStatus.unavailable();
    }
    final metadata = await _readMetadata();
    final runtimeStatus = await SingboxRuntime.instance.getSnowtunModuleStatus(
      splitName: metadata?['splitName']?.toString() ?? defaultSplitName,
      nativeLibraryName:
          metadata?['nativeLibraryName']?.toString() ??
          defaultNativeLibraryName,
    );
    final binaryPath = runtimeStatus['binaryPath']?.toString();
    final available =
        runtimeStatus['splitInstalled'] == true &&
        binaryPath != null &&
        binaryPath.trim().isNotEmpty;
    return SnowtunBinaryStatus(
      available: available,
      manifestUrl: metadata?['manifestUrl']?.toString() ?? defaultManifestUrl,
      binaryPath: available ? binaryPath : null,
      version: metadata?['version']?.toString(),
      artifactAbi: metadata?['artifactAbi']?.toString(),
      binarySha256: metadata?['binarySha256']?.toString(),
      binarySizeBytes:
          int.tryParse(metadata?['binarySizeBytes']?.toString() ?? '') ?? 0,
      chunkCount: int.tryParse(metadata?['chunkCount']?.toString() ?? '') ?? 0,
      installedAtMillis: int.tryParse(
        metadata?['installedAtMillis']?.toString() ?? '',
      ),
    );
  }

  Future<SnowtunBinaryStatus> installLatest({
    void Function(SnowtunDownloadProgress progress)? onProgress,
  }) async {
    if (!Platform.isAndroid) {
      throw UnsupportedError(
        'Snowtun optional module is only supported on Android.',
      );
    }
    const normalizedUrl = defaultManifestUrl;
    final paths = await _storagePaths();
    await Directory(paths.baseDirectoryPath).create(recursive: true);

    onProgress?.call(
      const SnowtunDownloadProgress(
        phase: SnowtunDownloadPhase.fetchingManifest,
        downloadedChunks: 0,
        totalChunks: 0,
        downloadedBytes: 0,
        totalBytes: 0,
      ),
    );

    final downloadResult = await _downloadInWorker(
      manifestUrl: normalizedUrl,
      tempApkPath: paths.tempApkPath,
      preferredKeys: resolveSnowtunArtifactKeysForCurrentPlatform(),
      onProgress: onProgress,
    );

    try {
      onProgress?.call(
        SnowtunDownloadProgress(
          phase: SnowtunDownloadPhase.finalizing,
          downloadedChunks: downloadResult.chunkCount,
          totalChunks: downloadResult.chunkCount,
          downloadedBytes: downloadResult.sizeBytes,
          totalBytes: downloadResult.sizeBytes,
        ),
      );
      final runtimeStatus = await SingboxRuntime.instance
          .getSnowtunModuleStatus(
            splitName: downloadResult.splitName,
            nativeLibraryName: downloadResult.nativeLibraryName,
          );
      final runtimePackageName = runtimeStatus['packageName']
          ?.toString()
          .trim();
      if (runtimePackageName != null &&
          runtimePackageName.isNotEmpty &&
          runtimePackageName != downloadResult.packageName) {
        throw StateError(
          'Snowtun module package mismatch: manifest expects '
          '${downloadResult.packageName}, app package is $runtimePackageName.',
        );
      }
      final runtimeVersionCode =
          int.tryParse(runtimeStatus['versionCode']?.toString() ?? '') ?? 0;
      if (runtimeVersionCode > 0 &&
          runtimeVersionCode != downloadResult.versionCode) {
        throw StateError(
          'Snowtun module version mismatch: manifest targets '
          '${downloadResult.versionCode}, app versionCode is $runtimeVersionCode.',
        );
      }
      await SingboxRuntime.instance.installSnowtunModule(
        apkPath: paths.tempApkPath,
        expectedPackageName: downloadResult.packageName,
        splitName: downloadResult.splitName,
      );
      final installedAtMillis = DateTime.now().millisecondsSinceEpoch;
      await _writeMetadata({
        'manifestUrl': normalizedUrl,
        'packageName': downloadResult.packageName,
        'versionCode': downloadResult.versionCode,
        'splitName': downloadResult.splitName,
        'nativeLibraryName': downloadResult.nativeLibraryName,
        'version': downloadResult.version,
        'artifactAbi': downloadResult.abi,
        'binarySha256': downloadResult.sha256,
        'binarySizeBytes': downloadResult.sizeBytes,
        'chunkCount': downloadResult.chunkCount,
        'installedAtMillis': installedAtMillis,
      });
      return await loadStatus();
    } finally {
      final tempFile = File(paths.tempApkPath);
      if (tempFile.existsSync()) {
        await tempFile.delete();
      }
    }
  }

  Future<SnowtunBinaryStatus> deleteInstalled() async {
    if (!Platform.isAndroid) {
      return const SnowtunBinaryStatus.unavailable();
    }
    final metadata = await _readMetadata();
    await SingboxRuntime.instance.removeSnowtunModule(
      splitName: metadata?['splitName']?.toString() ?? defaultSplitName,
    );
    final paths = await _storagePaths();
    for (final path in [paths.metadataPath, paths.tempApkPath]) {
      final file = File(path);
      if (file.existsSync()) {
        await file.delete();
      }
    }
    final filesDir = _androidFilesDirPath();
    for (final legacyPath in [
      '$filesDir/snowtun/bin/snowtun',
      '$filesDir/snowtun/bin/snowtun.download',
      '$filesDir/snowtun/snowtun-meta.json',
    ]) {
      final legacyFile = File(legacyPath);
      if (legacyFile.existsSync()) {
        await legacyFile.delete();
      }
    }
    return const SnowtunBinaryStatus.unavailable();
  }

  Future<Map<String, dynamic>?> _readMetadata() async {
    final paths = await _storagePaths();
    final metadataFile = File(paths.metadataPath);
    if (!metadataFile.existsSync()) {
      return null;
    }
    try {
      final raw = jsonDecode(await metadataFile.readAsString());
      if (raw is! Map) {
        return null;
      }
      return Map<String, dynamic>.from(raw);
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeMetadata(Map<String, dynamic> metadata) async {
    final paths = await _storagePaths();
    final target = File(paths.metadataPath);
    await target.parent.create(recursive: true);
    final temp = File('${paths.metadataPath}.tmp');
    await temp.writeAsBytes(utf8.encode(jsonEncode(metadata)), flush: true);
    if (target.existsSync()) {
      await target.delete();
    }
    await temp.rename(paths.metadataPath);
  }

  Future<_SnowtunStoragePaths> _storagePaths() async {
    if (!Platform.isAndroid) {
      throw UnsupportedError(
        'Snowtun optional module is only supported on Android.',
      );
    }
    final base = Directory('${_androidFilesDirPath()}/snowtun');
    return _SnowtunStoragePaths(
      baseDirectoryPath: base.path,
      tempApkPath: '${base.path}/snowtun-split.apk',
      metadataPath: '${base.path}/snowtun-meta.json',
    );
  }

  String _androidFilesDirPath() {
    final context = androidApplicationContext;
    final contextClass = context.jClass;
    final getFilesDir = contextClass.instanceMethodId(
      'getFilesDir',
      '()Ljava/io/File;',
    );
    final directory = getFilesDir.call(context, JObject.type, []);
    final path = _javaFileAbsolutePath(directory);

    directory.release();
    contextClass.release();
    context.release();

    return path;
  }

  String _javaFileAbsolutePath(JObject fileObject) {
    final fileClass = fileObject.jClass;
    final getAbsolutePath = fileClass.instanceMethodId(
      'getAbsolutePath',
      '()Ljava/lang/String;',
    );
    final path = getAbsolutePath
        .call(fileObject, JString.type, [])
        .toDartString(releaseOriginal: true);

    fileClass.release();
    return path;
  }
}

Future<_SnowtunDownloadedArtifact> _downloadInWorker({
  required String manifestUrl,
  required String tempApkPath,
  required List<String> preferredKeys,
  void Function(SnowtunDownloadProgress progress)? onProgress,
}) async {
  final receivePort = ReceivePort();
  final isolate = await Isolate.spawn<_SnowtunDownloadWorkerArgs>(
    _snowtunDownloadWorker,
    _SnowtunDownloadWorkerArgs(
      sendPort: receivePort.sendPort,
      manifestUrl: manifestUrl,
      tempApkPath: tempApkPath,
      preferredKeys: preferredKeys,
    ),
  );

  try {
    await for (final rawMessage in receivePort) {
      if (rawMessage is! Map) {
        continue;
      }
      final type = rawMessage['type'];
      if (type == 'progress') {
        onProgress?.call(
          SnowtunDownloadProgress(
            phase: SnowtunDownloadPhase.values[rawMessage['phase'] as int],
            downloadedChunks: rawMessage['downloadedChunks'] as int,
            totalChunks: rawMessage['totalChunks'] as int,
            downloadedBytes: rawMessage['downloadedBytes'] as int,
            totalBytes: rawMessage['totalBytes'] as int,
          ),
        );
        continue;
      }
      if (type == 'done') {
        return _SnowtunDownloadedArtifact(
          packageName: rawMessage['packageName'] as String,
          versionCode: rawMessage['versionCode'] as int,
          splitName: rawMessage['splitName'] as String,
          nativeLibraryName: rawMessage['nativeLibraryName'] as String,
          abi: rawMessage['abi'] as String,
          version: rawMessage['version'] as String,
          sha256: rawMessage['sha256'] as String,
          sizeBytes: rawMessage['sizeBytes'] as int,
          chunkCount: rawMessage['chunkCount'] as int,
        );
      }
      if (type == 'error') {
        throw StateError(rawMessage['error']?.toString() ?? 'Unknown error');
      }
    }
    throw StateError('Snowtun worker stopped unexpectedly.');
  } finally {
    isolate.kill(priority: Isolate.immediate);
    receivePort.close();
  }
}

Future<void> _snowtunDownloadWorker(_SnowtunDownloadWorkerArgs args) async {
  final sendPort = args.sendPort;
  final manifestUri = Uri.parse(args.manifestUrl);
  final tempFile = File(args.tempApkPath);
  final client = HttpClient();
  try {
    await tempFile.parent.create(recursive: true);
    sendPort.send(
      _progressMessage(
        const SnowtunDownloadProgress(
          phase: SnowtunDownloadPhase.fetchingManifest,
          downloadedChunks: 0,
          totalChunks: 0,
          downloadedBytes: 0,
          totalBytes: 0,
        ),
      ),
    );

    final manifest = await _downloadSnowtunManifest(
      client,
      manifestUri,
      args.preferredKeys,
    );
    final sink = tempFile.openWrite();
    final digest = SHA256Digest();
    var downloadedBytes = 0;
    try {
      for (var index = 0; index < manifest.chunks.length; index++) {
        final chunk = manifest.chunks[index];
        final chunkBytes = await _downloadBytes(
          client,
          manifestUri.resolve(chunk.path),
          maxBytes: chunk.sizeBytes > 0
              ? chunk.sizeBytes
              : _maxSnowtunChunkBytes,
        );
        if (chunk.sizeBytes > 0 && chunkBytes.length != chunk.sizeBytes) {
          throw StateError(
            'Snowtun chunk size mismatch for ${chunk.path}: expected '
            '${chunk.sizeBytes}, got ${chunkBytes.length}.',
          );
        }
        final chunkSha256 = _sha256Hex(chunkBytes);
        if (chunkSha256 != chunk.sha256) {
          throw StateError(
            'Snowtun chunk checksum mismatch for ${chunk.path}.',
          );
        }
        final chunkData = Uint8List.fromList(chunkBytes);
        sink.add(chunkData);
        digest.update(chunkData, 0, chunkData.length);
        downloadedBytes += chunkBytes.length;
        sendPort.send(
          _progressMessage(
            SnowtunDownloadProgress(
              phase: SnowtunDownloadPhase.downloadingChunks,
              downloadedChunks: index + 1,
              totalChunks: manifest.chunks.length,
              downloadedBytes: downloadedBytes,
              totalBytes: manifest.sizeBytes,
            ),
          ),
        );
      }
    } finally {
      await sink.close();
    }

    sendPort.send(
      _progressMessage(
        SnowtunDownloadProgress(
          phase: SnowtunDownloadPhase.finalizing,
          downloadedChunks: manifest.chunks.length,
          totalChunks: manifest.chunks.length,
          downloadedBytes: downloadedBytes,
          totalBytes: manifest.sizeBytes,
        ),
      ),
    );

    final artifactSha256 = _digestToHex(digest);
    if (artifactSha256 != manifest.sha256) {
      throw StateError('Snowtun split checksum mismatch.');
    }
    final tempLength = await tempFile.length();
    if (manifest.sizeBytes > 0 && tempLength != manifest.sizeBytes) {
      throw StateError(
        'Snowtun split size mismatch: expected ${manifest.sizeBytes}, got $tempLength.',
      );
    }
    sendPort.send({
      'type': 'done',
      'packageName': manifest.packageName,
      'versionCode': manifest.versionCode,
      'splitName': manifest.splitName,
      'nativeLibraryName': manifest.nativeLibraryName,
      'abi': manifest.abi,
      'version': manifest.version,
      'sha256': manifest.sha256,
      'sizeBytes': manifest.sizeBytes,
      'chunkCount': manifest.chunks.length,
    });
  } catch (error) {
    if (tempFile.existsSync()) {
      await tempFile.delete();
    }
    sendPort.send({'type': 'error', 'error': error.toString()});
  } finally {
    client.close(force: true);
  }
}

Map<String, Object> _progressMessage(SnowtunDownloadProgress progress) => {
  'type': 'progress',
  'phase': progress.phase.index,
  'downloadedChunks': progress.downloadedChunks,
  'totalChunks': progress.totalChunks,
  'downloadedBytes': progress.downloadedBytes,
  'totalBytes': progress.totalBytes,
};

Future<_SnowtunManifest> _downloadSnowtunManifest(
  HttpClient client,
  Uri manifestUri,
  List<String> preferredKeys,
) async {
  final bytes = await _downloadBytes(
    client,
    manifestUri,
    maxBytes: _maxSnowtunManifestBytes,
  );
  final raw = jsonDecode(utf8.decode(bytes, allowMalformed: true));
  if (raw is! Map) {
    throw const FormatException('Snowtun manifest must be a JSON object.');
  }
  final manifest = Map<String, dynamic>.from(raw);
  final artifactsRaw = manifest['artifacts'];
  if (artifactsRaw is! Map) {
    throw const FormatException('Snowtun manifest is missing artifacts.');
  }
  final packageName =
      manifest['package_name']?.toString().trim().isNotEmpty == true
      ? manifest['package_name'].toString().trim()
      : SnowtunBinaryService.defaultPackageName;
  final versionCode =
      int.tryParse(manifest['version_code']?.toString() ?? '') ?? 0;
  final splitName = manifest['split_name']?.toString().trim().isNotEmpty == true
      ? manifest['split_name'].toString().trim()
      : SnowtunBinaryService.defaultSplitName;
  final nativeLibraryName =
      manifest['native_library_name']?.toString().trim().isNotEmpty == true
      ? manifest['native_library_name'].toString().trim()
      : SnowtunBinaryService.defaultNativeLibraryName;
  final manifestVersion = manifest['version']?.toString().trim() ?? '';
  return _selectArtifactFromManifestMap(
    Map<String, dynamic>.from(artifactsRaw),
    packageName: packageName,
    versionCode: versionCode,
    splitName: splitName,
    nativeLibraryName: nativeLibraryName,
    manifestVersion: manifestVersion,
    preferredKeys: preferredKeys,
  );
}

_SnowtunManifest _selectArtifactFromManifestMap(
  Map<String, dynamic> artifacts, {
  required String packageName,
  required int versionCode,
  required String splitName,
  required String nativeLibraryName,
  required String manifestVersion,
  required List<String> preferredKeys,
}) {
  for (final key in preferredKeys) {
    final entry = artifacts[key];
    if (entry is! Map) {
      continue;
    }
    final artifact = _parseArtifactEntry(
      abi: key,
      packageName: packageName,
      versionCode: versionCode,
      splitName: splitName,
      nativeLibraryName: nativeLibraryName,
      value: Map<String, dynamic>.from(entry),
      fallbackVersion: manifestVersion,
    );
    if (artifact != null) {
      return artifact;
    }
  }
  throw StateError(
    'Snowtun manifest does not contain a compatible artifact for ${preferredKeys.join(', ')}.',
  );
}

_SnowtunManifest? _parseArtifactEntry({
  required String abi,
  required String packageName,
  required int versionCode,
  required String splitName,
  required String nativeLibraryName,
  required Map<String, dynamic> value,
  required String fallbackVersion,
}) {
  final version = value['version']?.toString().trim().isNotEmpty == true
      ? value['version'].toString().trim()
      : fallbackVersion;
  final sha256 = value['sha256']?.toString().trim().toLowerCase() ?? '';
  final sizeBytes = int.tryParse(value['size']?.toString() ?? '') ?? 0;
  final chunksRaw = value['chunks'];
  if (sha256.isEmpty || sizeBytes <= 0 || chunksRaw is! List) {
    return null;
  }
  if (sizeBytes > _maxSnowtunArtifactBytes) {
    throw FormatException(
      'Snowtun artifact is larger than $_maxSnowtunArtifactBytes bytes.',
    );
  }
  final chunks = _parseChunks(chunksRaw);
  if (chunks.isEmpty) {
    return null;
  }
  return _SnowtunManifest(
    packageName: packageName,
    versionCode: versionCode,
    splitName: splitName,
    nativeLibraryName: nativeLibraryName,
    abi: abi,
    version: version,
    sha256: sha256,
    sizeBytes: sizeBytes,
    chunks: chunks,
  );
}

List<_SnowtunChunk> _parseChunks(List<dynamic> chunksRaw) {
  final chunks = <_SnowtunChunk>[];
  for (final entry in chunksRaw) {
    if (entry is! Map) {
      throw const FormatException('Snowtun manifest chunk entry is invalid.');
    }
    final chunk = Map<String, dynamic>.from(entry);
    final path = chunk['path']?.toString().trim() ?? '';
    final chunkSha256 = chunk['sha256']?.toString().trim().toLowerCase() ?? '';
    final chunkSize = int.tryParse(chunk['size']?.toString() ?? '') ?? 0;
    if (path.isEmpty || chunkSha256.isEmpty || chunkSize <= 0) {
      throw const FormatException(
        'Snowtun manifest chunk is missing required fields.',
      );
    }
    if (chunkSize > _maxSnowtunChunkBytes) {
      throw FormatException(
        'Snowtun chunk is larger than $_maxSnowtunChunkBytes bytes.',
      );
    }
    chunks.add(
      _SnowtunChunk(path: path, sha256: chunkSha256, sizeBytes: chunkSize),
    );
  }
  return chunks;
}

Future<List<int>> _downloadBytes(
  HttpClient client,
  Uri uri, {
  required int maxBytes,
}) async {
  final request = await client.getUrl(uri);
  request.headers.set(HttpHeaders.acceptHeader, 'application/json,*/*');
  final response = await request.close();
  if (response.statusCode < 200 || response.statusCode >= 300) {
    throw HttpException(
      'Failed to download Snowtun artifact: HTTP ${response.statusCode}',
      uri: uri,
    );
  }
  final declaredLength = response.contentLength;
  if (declaredLength > maxBytes) {
    throw HttpException(
      'Snowtun response is larger than $maxBytes bytes',
      uri: uri,
    );
  }
  final builder = BytesBuilder(copy: false);
  var totalBytes = 0;
  await for (final chunk in response) {
    totalBytes += chunk.length;
    if (totalBytes > maxBytes) {
      throw HttpException(
        'Snowtun response is larger than $maxBytes bytes',
        uri: uri,
      );
    }
    builder.add(chunk);
  }
  return builder.takeBytes();
}

String _sha256Hex(List<int> bytes) {
  final digest = SHA256Digest();
  final input = Uint8List.fromList(bytes);
  digest.update(input, 0, input.length);
  return _digestToHex(digest);
}

String _digestToHex(SHA256Digest digest) {
  final output = Uint8List(digest.digestSize);
  digest.doFinal(output, 0);
  return output.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
}

class _SnowtunStoragePaths {
  const _SnowtunStoragePaths({
    required this.baseDirectoryPath,
    required this.tempApkPath,
    required this.metadataPath,
  });

  final String baseDirectoryPath;
  final String tempApkPath;
  final String metadataPath;
}

class _SnowtunDownloadWorkerArgs {
  const _SnowtunDownloadWorkerArgs({
    required this.sendPort,
    required this.manifestUrl,
    required this.tempApkPath,
    required this.preferredKeys,
  });

  final SendPort sendPort;
  final String manifestUrl;
  final String tempApkPath;
  final List<String> preferredKeys;
}

class _SnowtunDownloadedArtifact {
  const _SnowtunDownloadedArtifact({
    required this.packageName,
    required this.versionCode,
    required this.splitName,
    required this.nativeLibraryName,
    required this.abi,
    required this.version,
    required this.sha256,
    required this.sizeBytes,
    required this.chunkCount,
  });

  final String packageName;
  final int versionCode;
  final String splitName;
  final String nativeLibraryName;
  final String abi;
  final String version;
  final String sha256;
  final int sizeBytes;
  final int chunkCount;
}

class _SnowtunManifest {
  const _SnowtunManifest({
    required this.packageName,
    required this.versionCode,
    required this.splitName,
    required this.nativeLibraryName,
    required this.abi,
    required this.version,
    required this.sha256,
    required this.sizeBytes,
    required this.chunks,
  });

  final String packageName;
  final int versionCode;
  final String splitName;
  final String nativeLibraryName;
  final String abi;
  final String version;
  final String sha256;
  final int sizeBytes;
  final List<_SnowtunChunk> chunks;
}

class _SnowtunChunk {
  const _SnowtunChunk({
    required this.path,
    required this.sha256,
    required this.sizeBytes,
  });

  final String path;
  final String sha256;
  final int sizeBytes;
}
