import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:jni/jni.dart';
import 'package:jni_flutter/jni_flutter.dart';

class RussiaRouteDataStatus {
  const RussiaRouteDataStatus({
    required this.available,
    required this.sourceName,
    required this.versionTag,
    this.geositeRuBlockedPath,
    this.geositeRuAvailableOnlyInsidePath,
    this.geoipRuBlockedPath,
    this.curatedDirectServicesPath,
    this.aiServicesPath,
    this.installedAtMillis,
    this.lastUpdateCheckAtMillis,
    this.domainListCommunityUpdatedAtMillis,
    this.domainListCommunityCategoryCount = 0,
    this.domainListCommunityDomainCount = 0,
    this.domainListCommunityMetadata =
        const <String, RussiaRouteCategoryMetadata>{},
  });

  const RussiaRouteDataStatus.unavailable()
    : available = false,
      sourceName = RussiaRouteDataService.sourceName,
      versionTag = RussiaRouteDataService.bundledTag,
      geositeRuBlockedPath = null,
      geositeRuAvailableOnlyInsidePath = null,
      geoipRuBlockedPath = null,
      curatedDirectServicesPath = null,
      aiServicesPath = null,
      installedAtMillis = null,
      lastUpdateCheckAtMillis = null,
      domainListCommunityUpdatedAtMillis = null,
      domainListCommunityCategoryCount = 0,
      domainListCommunityDomainCount = 0,
      domainListCommunityMetadata =
          const <String, RussiaRouteCategoryMetadata>{};

  final bool available;
  final String sourceName;
  final String versionTag;
  final String? geositeRuBlockedPath;
  final String? geositeRuAvailableOnlyInsidePath;
  final String? geoipRuBlockedPath;
  final String? curatedDirectServicesPath;
  final String? aiServicesPath;
  final int? installedAtMillis;
  final int? lastUpdateCheckAtMillis;
  final int? domainListCommunityUpdatedAtMillis;
  final int domainListCommunityCategoryCount;
  final int domainListCommunityDomainCount;
  final Map<String, RussiaRouteCategoryMetadata> domainListCommunityMetadata;

  DateTime? get installedAt => installedAtMillis == null
      ? null
      : DateTime.fromMillisecondsSinceEpoch(installedAtMillis!);

  DateTime? get domainListCommunityUpdatedAt =>
      domainListCommunityUpdatedAtMillis == null
      ? null
      : DateTime.fromMillisecondsSinceEpoch(
          domainListCommunityUpdatedAtMillis!,
        );

  DateTime? get lastUpdateCheckAt => lastUpdateCheckAtMillis == null
      ? null
      : DateTime.fromMillisecondsSinceEpoch(lastUpdateCheckAtMillis!);

  bool get needsDailyUpdate {
    final lastCheck = lastUpdateCheckAt;
    if (lastCheck == null) {
      return true;
    }
    return DateTime.now().difference(lastCheck) >= const Duration(hours: 24);
  }
}

class RussiaRouteCategoryMetadata {
  const RussiaRouteCategoryMetadata({
    this.etag,
    this.lastModified,
    this.updatedAtMillis,
  });

  final String? etag;
  final String? lastModified;
  final int? updatedAtMillis;

  Map<String, Object?> toJson() => {
    if (etag != null && etag!.isNotEmpty) 'etag': etag,
    if (lastModified != null && lastModified!.isNotEmpty)
      'lastModified': lastModified,
    if (updatedAtMillis != null) 'updatedAtMillis': updatedAtMillis,
  };

  static RussiaRouteCategoryMetadata fromJson(Object? value) {
    if (value is! Map) {
      return const RussiaRouteCategoryMetadata();
    }
    return RussiaRouteCategoryMetadata(
      etag: value['etag']?.toString(),
      lastModified: value['lastModified']?.toString(),
      updatedAtMillis: int.tryParse(value['updatedAtMillis']?.toString() ?? ''),
    );
  }
}

class RussiaRouteDataService {
  RussiaRouteDataService._();

  static final RussiaRouteDataService instance = RussiaRouteDataService._();

  static const sourceName = 'runetfreedom + domain-list-community';
  static const bundledTag = 'bundled-20260327';
  static const domainListCommunitySourceName = 'v2fly/domain-list-community';
  static const _domainListCommunityRawBaseUrl =
      'https://raw.githubusercontent.com/v2fly/domain-list-community/master/data';
  static const _maxDomainListCategoryBytes = 2 * 1024 * 1024;

  static const _assetGeositeRuBlocked =
      'assets/route_data/russia/geosite-ru-blocked.srs';
  static const _assetGeositeRuAvailableOnlyInside =
      'assets/route_data/russia/geosite-ru-available-only-inside.srs';
  static const _assetGeoipRuBlocked =
      'assets/route_data/russia/geoip-ru-blocked.srs';
  static const _curatedDirectServicesCategories = <String>[
    'category-gov-ru',
    'vk',
    'yandex',
    'sber',
    'mailru-group',
    'tbank-ru',
    'avito',
    'ozon',
    'wildberries',
    'x5',
    'rutube',
  ];
  static const _aiServicesCategories = <String>['category-ai-!cn'];

  Future<RussiaRouteDataStatus>? _updateInFlight;

  Future<RussiaRouteDataStatus> loadStatus() async {
    final paths = await _storagePaths();
    final metadataFile = File(paths.metadataPath);
    final geositeBlockedFile = File(paths.geositeRuBlockedPath);
    final geositeAvailableOnlyInsideFile = File(
      paths.geositeRuAvailableOnlyInsidePath,
    );
    final geoipBlockedFile = File(paths.geoipRuBlockedPath);
    final curatedDirectServicesFile = File(paths.curatedDirectServicesPath);
    final aiServicesFile = File(paths.aiServicesPath);
    if (!metadataFile.existsSync() ||
        !geositeBlockedFile.existsSync() ||
        !geositeAvailableOnlyInsideFile.existsSync() ||
        !geoipBlockedFile.existsSync() ||
        !curatedDirectServicesFile.existsSync() ||
        !aiServicesFile.existsSync()) {
      return const RussiaRouteDataStatus.unavailable();
    }
    try {
      final metadata =
          jsonDecode(await metadataFile.readAsString()) as Map<String, dynamic>;
      return RussiaRouteDataStatus(
        available: true,
        sourceName: metadata['sourceName']?.toString() ?? sourceName,
        versionTag: metadata['versionTag']?.toString() ?? bundledTag,
        geositeRuBlockedPath: geositeBlockedFile.path,
        geositeRuAvailableOnlyInsidePath: geositeAvailableOnlyInsideFile.path,
        geoipRuBlockedPath: geoipBlockedFile.path,
        curatedDirectServicesPath: curatedDirectServicesFile.path,
        aiServicesPath: aiServicesFile.path,
        installedAtMillis: int.tryParse(
          metadata['installedAtMillis']?.toString() ?? '',
        ),
        lastUpdateCheckAtMillis: int.tryParse(
          metadata['lastUpdateCheckAtMillis']?.toString() ?? '',
        ),
        domainListCommunityUpdatedAtMillis: int.tryParse(
          metadata['domainListCommunityUpdatedAtMillis']?.toString() ?? '',
        ),
        domainListCommunityCategoryCount:
            int.tryParse(
              metadata['domainListCommunityCategoryCount']?.toString() ?? '',
            ) ??
            0,
        domainListCommunityDomainCount:
            int.tryParse(
              metadata['domainListCommunityDomainCount']?.toString() ?? '',
            ) ??
            0,
        domainListCommunityMetadata: _categoryMetadataFromJson(
          metadata['domainListCommunityMetadata'],
        ),
      );
    } catch (_) {
      return const RussiaRouteDataStatus.unavailable();
    }
  }

  Future<RussiaRouteDataStatus> ensureBundledInstalled() async {
    return ensureUpdated(force: true);
  }

  Future<RussiaRouteDataStatus> deleteInstalled() async {
    final paths = await _storagePaths();
    final base = Directory(paths.baseDirectoryPath);
    if (base.existsSync()) {
      await base.delete(recursive: true);
    }
    return const RussiaRouteDataStatus.unavailable();
  }

  Future<RussiaRouteDataStatus> ensureUpdated({bool force = false}) async {
    final inFlight = _updateInFlight;
    if (inFlight != null) {
      return inFlight;
    }
    final future = _ensureUpdated(force: force);
    _updateInFlight = future;
    try {
      return await future;
    } finally {
      if (identical(_updateInFlight, future)) {
        _updateInFlight = null;
      }
    }
  }

  Future<RussiaRouteDataStatus> _ensureUpdated({required bool force}) async {
    final current = await loadStatus();
    if (!force &&
        current.available &&
        current.versionTag == bundledTag &&
        !current.needsDailyUpdate) {
      return current;
    }
    final paths = await _storagePaths();
    await Directory(paths.baseDirectoryPath).create(recursive: true);
    await Directory(
      paths.domainListCommunitySourceDirectoryPath,
    ).create(recursive: true);
    final nowMillis = DateTime.now().millisecondsSinceEpoch;
    try {
      final bundledChanged =
          !current.available || current.versionTag != bundledTag;
      if (bundledChanged ||
          !File(paths.geositeRuBlockedPath).existsSync() ||
          !File(paths.geositeRuAvailableOnlyInsidePath).existsSync() ||
          !File(paths.geoipRuBlockedPath).existsSync()) {
        await _copyBundledAsset(
          asset: _assetGeositeRuBlocked,
          outputPath: paths.geositeRuBlockedPath,
        );
        await _copyBundledAsset(
          asset: _assetGeositeRuAvailableOnlyInside,
          outputPath: paths.geositeRuAvailableOnlyInsidePath,
        );
        await _copyBundledAsset(
          asset: _assetGeoipRuBlocked,
          outputPath: paths.geoipRuBlockedPath,
        );
      }
      final downloaded = await _downloadDomainListCommunityCategories(
        sourceDirectoryPath: paths.domainListCommunitySourceDirectoryPath,
        previousMetadata: current.domainListCommunityMetadata,
        force: force,
      );
      final shouldRebuildDomainLists =
          force ||
          !current.available ||
          downloaded.changed ||
          !File(paths.curatedDirectServicesPath).existsSync() ||
          !File(paths.aiServicesPath).existsSync();
      var downloadedCategoryCount = current.domainListCommunityCategoryCount;
      var compiledDomainCount = current.domainListCommunityDomainCount;
      var domainListCommunityUpdatedAtMillis =
          current.domainListCommunityUpdatedAtMillis;
      if (shouldRebuildDomainLists) {
        final categoryFiles = downloaded.categoryFiles;
        final compiledCuratedDirectServices = await Isolate.run(
          () => _compileCuratedDirectServicesArtifact(categoryFiles),
        );
        final compiledAiServices = await Isolate.run(
          () => _compileAiServicesArtifact(categoryFiles),
        );
        await _writeAtomically(
          paths.curatedDirectServicesPath,
          compiledCuratedDirectServices.ruleSetBytes,
        );
        await _writeAtomically(
          paths.aiServicesPath,
          compiledAiServices.ruleSetBytes,
        );
        downloadedCategoryCount = categoryFiles.length;
        compiledDomainCount =
            compiledCuratedDirectServices.domainCount +
            compiledAiServices.domainCount;
        domainListCommunityUpdatedAtMillis = nowMillis;
      }
      final installedAtMillis = current.installedAtMillis ?? nowMillis;
      await _writeMetadata(
        paths,
        installedAtMillis: installedAtMillis,
        lastUpdateCheckAtMillis: nowMillis,
        domainListCommunityUpdatedAtMillis:
            domainListCommunityUpdatedAtMillis ?? nowMillis,
        domainListCommunityCategoryCount: downloadedCategoryCount,
        domainListCommunityDomainCount: compiledDomainCount,
        domainListCommunityMetadata: downloaded.metadata,
      );
      return RussiaRouteDataStatus(
        available: true,
        sourceName: sourceName,
        versionTag: bundledTag,
        geositeRuBlockedPath: paths.geositeRuBlockedPath,
        geositeRuAvailableOnlyInsidePath:
            paths.geositeRuAvailableOnlyInsidePath,
        geoipRuBlockedPath: paths.geoipRuBlockedPath,
        curatedDirectServicesPath: paths.curatedDirectServicesPath,
        aiServicesPath: paths.aiServicesPath,
        installedAtMillis: installedAtMillis,
        lastUpdateCheckAtMillis: nowMillis,
        domainListCommunityUpdatedAtMillis:
            domainListCommunityUpdatedAtMillis ?? nowMillis,
        domainListCommunityCategoryCount: downloadedCategoryCount,
        domainListCommunityDomainCount: compiledDomainCount,
        domainListCommunityMetadata: downloaded.metadata,
      );
    } catch (_) {
      if (!force && current.available) {
        await _writeMetadata(
          paths,
          installedAtMillis: current.installedAtMillis ?? nowMillis,
          lastUpdateCheckAtMillis: nowMillis,
          domainListCommunityUpdatedAtMillis:
              current.domainListCommunityUpdatedAtMillis ?? nowMillis,
          domainListCommunityCategoryCount:
              current.domainListCommunityCategoryCount,
          domainListCommunityDomainCount:
              current.domainListCommunityDomainCount,
          domainListCommunityMetadata: current.domainListCommunityMetadata,
        );
        return loadStatus();
      }
      rethrow;
    }
  }

  Future<void> _writeMetadata(
    _RussiaRouteStoragePaths paths, {
    required int installedAtMillis,
    required int lastUpdateCheckAtMillis,
    required int domainListCommunityUpdatedAtMillis,
    required int domainListCommunityCategoryCount,
    required int domainListCommunityDomainCount,
    required Map<String, RussiaRouteCategoryMetadata>
    domainListCommunityMetadata,
  }) {
    return _writeAtomically(
      paths.metadataPath,
      utf8.encode(
        jsonEncode({
          'sourceName': sourceName,
          'versionTag': bundledTag,
          'installedAtMillis': installedAtMillis,
          'lastUpdateCheckAtMillis': lastUpdateCheckAtMillis,
          'domainListCommunityUpdatedAtMillis':
              domainListCommunityUpdatedAtMillis,
          'domainListCommunityCategoryCount': domainListCommunityCategoryCount,
          'domainListCommunityDomainCount': domainListCommunityDomainCount,
          'domainListCommunityMetadata': {
            for (final entry in domainListCommunityMetadata.entries)
              entry.key: entry.value.toJson(),
          },
        }),
      ),
    );
  }

  Future<_DownloadedDomainListCommunity>
  _downloadDomainListCommunityCategories({
    required String sourceDirectoryPath,
    required Map<String, RussiaRouteCategoryMetadata> previousMetadata,
    required bool force,
  }) async {
    final client = HttpClient();
    final categoryFiles = <String, String>{};
    final metadata = <String, RussiaRouteCategoryMetadata>{};
    final pending = <String>[
      ..._curatedDirectServicesCategories,
      ..._aiServicesCategories,
    ];
    var changed = false;
    try {
      while (pending.isNotEmpty) {
        final category = pending.removeLast();
        if (categoryFiles.containsKey(category)) {
          continue;
        }
        final downloaded = await _downloadDomainListCommunityCategory(
          client,
          category: category,
          sourceDirectoryPath: sourceDirectoryPath,
          previousMetadata: previousMetadata[category],
          force: force,
        );
        final content = downloaded.content;
        categoryFiles[category] = content;
        metadata[category] = downloaded.metadata;
        changed = changed || downloaded.changed;
        for (final include in _extractIncludedCategories(content)) {
          if (!categoryFiles.containsKey(include)) {
            pending.add(include);
          }
        }
      }
      return _DownloadedDomainListCommunity(
        categoryFiles: categoryFiles,
        metadata: metadata,
        changed: changed,
      );
    } finally {
      client.close(force: true);
    }
  }

  Future<_DownloadedCategory> _downloadDomainListCommunityCategory(
    HttpClient client, {
    required String category,
    required String sourceDirectoryPath,
    required RussiaRouteCategoryMetadata? previousMetadata,
    required bool force,
  }) async {
    final uri = Uri.parse('$_domainListCommunityRawBaseUrl/$category');
    final cacheFile = File(
      '$sourceDirectoryPath/${Uri.encodeComponent(category)}.txt',
    );
    final request = await client.getUrl(uri);
    request.headers.set(HttpHeaders.acceptHeader, 'text/plain,*/*');
    if (!force && cacheFile.existsSync()) {
      final etag = previousMetadata?.etag;
      if (etag != null && etag.isNotEmpty) {
        request.headers.set(HttpHeaders.ifNoneMatchHeader, etag);
      }
      final lastModified = previousMetadata?.lastModified;
      if (lastModified != null && lastModified.isNotEmpty) {
        request.headers.set(HttpHeaders.ifModifiedSinceHeader, lastModified);
      }
    }
    final response = await request.close();
    if (response.statusCode == HttpStatus.notModified &&
        cacheFile.existsSync()) {
      return _DownloadedCategory(
        content: await cacheFile.readAsString(),
        metadata: previousMetadata ?? const RussiaRouteCategoryMetadata(),
        changed: false,
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
        'Failed to download route category: HTTP ${response.statusCode}',
        uri: uri,
      );
    }
    final builder = BytesBuilder(copy: false);
    var length = 0;
    await for (final chunk in response) {
      length += chunk.length;
      if (length > _maxDomainListCategoryBytes) {
        throw HttpException('Route category is too large', uri: uri);
      }
      builder.add(chunk);
    }
    final bytes = builder.takeBytes();
    final content = utf8.decode(bytes, allowMalformed: true);
    final previousContent = cacheFile.existsSync()
        ? await cacheFile.readAsString()
        : null;
    final changed = previousContent != content;
    await cacheFile.parent.create(recursive: true);
    await cacheFile.writeAsString(content, flush: true);
    final nowMillis = DateTime.now().millisecondsSinceEpoch;
    return _DownloadedCategory(
      content: content,
      metadata: RussiaRouteCategoryMetadata(
        etag: response.headers.value(HttpHeaders.etagHeader),
        lastModified: response.headers.value(HttpHeaders.lastModifiedHeader),
        updatedAtMillis: changed
            ? nowMillis
            : previousMetadata?.updatedAtMillis ?? nowMillis,
      ),
      changed: changed,
    );
  }

  List<String> _extractIncludedCategories(String content) {
    final includes = <String>[];
    final seen = <String>{};
    for (final rawLine in const LineSplitter().convert(content)) {
      final line = rawLine.split('#').first.trim();
      if (!line.startsWith('include:')) {
        continue;
      }
      final include = _parseIncludedCategory(line);
      if (include.isNotEmpty && seen.add(include)) {
        includes.add(include);
      }
    }
    return includes;
  }

  Future<void> _copyBundledAsset({
    required String asset,
    required String outputPath,
  }) async {
    final data = await rootBundle.load(asset);
    await _writeAtomically(outputPath, data.buffer.asUint8List());
  }

  Future<void> _writeAtomically(String path, List<int> bytes) async {
    final target = File(path);
    await target.parent.create(recursive: true);
    final temp = File('$path.tmp');
    await temp.writeAsBytes(bytes, flush: true);
    try {
      await temp.rename(path);
      return;
    } on FileSystemException {
      final backup = File('$path.bak');
      if (backup.existsSync()) {
        await backup.delete();
      }
      if (target.existsSync()) {
        await target.rename(backup.path);
      }
      try {
        await temp.rename(path);
        if (backup.existsSync()) {
          await backup.delete();
        }
      } catch (_) {
        if (!target.existsSync() && backup.existsSync()) {
          await backup.rename(path);
        }
        rethrow;
      }
    }
  }

  Future<_RussiaRouteStoragePaths> _storagePaths() async {
    final baseDirPath = Platform.isAndroid
        ? _androidFilesDirPath()
        : Directory.systemTemp.path;
    final base = Directory('$baseDirPath/route-data/russia-v2ray-rules-dat');
    return _RussiaRouteStoragePaths(
      baseDirectoryPath: base.path,
      geositeRuBlockedPath:
          '${base.path}/rule-set-geosite/geosite-ru-blocked.srs',
      geositeRuAvailableOnlyInsidePath:
          '${base.path}/rule-set-geosite/geosite-ru-available-only-inside.srs',
      geoipRuBlockedPath: '${base.path}/rule-set-geoip/geoip-ru-blocked.srs',
      curatedDirectServicesPath:
          '${base.path}/rule-set-geosite/ru-direct-services.srs',
      aiServicesPath: '${base.path}/rule-set-geosite/ai-services.srs',
      domainListCommunitySourceDirectoryPath:
          '${base.path}/domain-list-community',
      metadataPath: '${base.path}/manifest.json',
    );
  }

  String _androidFilesDirPath() {
    final context = androidApplicationContext;
    final contextClass = context.jClass;
    final getFilesDir = contextClass.instanceMethodId(
      'getFilesDir',
      '()Ljava/io/File;',
    );
    final filesDir = getFilesDir.call(context, JObject.type, []);
    final fileClass = filesDir.jClass;
    final getAbsolutePath = fileClass.instanceMethodId(
      'getAbsolutePath',
      '()Ljava/lang/String;',
    );
    final path = getAbsolutePath
        .call(filesDir, JString.type, [])
        .toDartString(releaseOriginal: true);

    fileClass.release();
    filesDir.release();
    contextClass.release();
    context.release();

    return path;
  }
}

class _RussiaRouteStoragePaths {
  const _RussiaRouteStoragePaths({
    required this.baseDirectoryPath,
    required this.geositeRuBlockedPath,
    required this.geositeRuAvailableOnlyInsidePath,
    required this.geoipRuBlockedPath,
    required this.curatedDirectServicesPath,
    required this.aiServicesPath,
    required this.domainListCommunitySourceDirectoryPath,
    required this.metadataPath,
  });

  final String baseDirectoryPath;
  final String geositeRuBlockedPath;
  final String geositeRuAvailableOnlyInsidePath;
  final String geoipRuBlockedPath;
  final String curatedDirectServicesPath;
  final String aiServicesPath;
  final String domainListCommunitySourceDirectoryPath;
  final String metadataPath;
}

class _DownloadedDomainListCommunity {
  const _DownloadedDomainListCommunity({
    required this.categoryFiles,
    required this.metadata,
    required this.changed,
  });

  final Map<String, String> categoryFiles;
  final Map<String, RussiaRouteCategoryMetadata> metadata;
  final bool changed;
}

class _DownloadedCategory {
  const _DownloadedCategory({
    required this.content,
    required this.metadata,
    required this.changed,
  });

  final String content;
  final RussiaRouteCategoryMetadata metadata;
  final bool changed;
}

Map<String, RussiaRouteCategoryMetadata> _categoryMetadataFromJson(
  Object? value,
) {
  if (value is! Map) {
    return const <String, RussiaRouteCategoryMetadata>{};
  }
  return {
    for (final entry in value.entries)
      entry.key.toString(): RussiaRouteCategoryMetadata.fromJson(entry.value),
  };
}

_CompiledRuleSetArtifact _compileCuratedDirectServicesArtifact(
  Map<String, String> categoryFiles,
) {
  return _compileDomainListCommunityArtifact(
    categoryFiles,
    RussiaRouteDataService._curatedDirectServicesCategories,
  );
}

_CompiledRuleSetArtifact _compileAiServicesArtifact(
  Map<String, String> categoryFiles,
) {
  return _compileDomainListCommunityArtifact(
    categoryFiles,
    RussiaRouteDataService._aiServicesCategories,
  );
}

_CompiledRuleSetArtifact _compileDomainListCommunityArtifact(
  Map<String, String> categoryFiles,
  List<String> rootCategories,
) {
  final exactDomains = <String>{};
  final suffixDomains = <String>{};
  final visiting = <String>{};
  final visited = <String>{};

  void loadCategory(String category) {
    if (!visiting.add(category) || visited.contains(category)) {
      return;
    }
    final content = categoryFiles[category];
    if (content == null) {
      visiting.remove(category);
      return;
    }
    for (final rawLine in const LineSplitter().convert(content)) {
      final line = rawLine.split('#').first.trim();
      if (line.isEmpty || line.contains('@ads') || line.contains('@!cn')) {
        continue;
      }
      if (line.startsWith('include:')) {
        loadCategory(_parseIncludedCategory(line));
        continue;
      }
      if (line.startsWith('regexp:') ||
          line.startsWith('keyword:') ||
          line.startsWith('geosite:') ||
          line.startsWith('ext:')) {
        continue;
      }
      final normalized = _normalizeServiceDomainLine(line);
      if (normalized == null) {
        continue;
      }
      switch (normalized.type) {
        case _RuleDomainType.exact:
          exactDomains.add(normalized.value);
        case _RuleDomainType.suffix:
          suffixDomains.add(normalized.value);
      }
    }
    visiting.remove(category);
    visited.add(category);
  }

  for (final category in rootCategories) {
    loadCategory(category);
  }

  final exactList = exactDomains.toList()..sort();
  final suffixList = suffixDomains.toList()..sort();
  return _CompiledRuleSetArtifact(
    ruleSetBytes: _buildSrsRuleSet(
      domains: exactList,
      domainSuffixes: suffixList,
    ),
    domainCount: exactList.length + suffixList.length,
  );
}

String _parseIncludedCategory(String line) {
  final include = line.substring('include:'.length).trim();
  final separator = include.indexOf(RegExp(r'\s'));
  return separator < 0 ? include : include.substring(0, separator);
}

_NormalizedRuleDomain? _normalizeServiceDomainLine(String line) {
  var value = line.trim();
  if (value.isEmpty) {
    return null;
  }
  if (value.startsWith('full:')) {
    value = value.substring('full:'.length).trim();
    final normalized = _normalizeDomainValue(value);
    return normalized == null
        ? null
        : _NormalizedRuleDomain(_RuleDomainType.exact, normalized);
  }
  if (value.startsWith('domain:')) {
    value = value.substring('domain:'.length).trim();
    final normalized = _normalizeDomainValue(value);
    return normalized == null
        ? null
        : _NormalizedRuleDomain(_RuleDomainType.exact, normalized);
  }
  final normalized = _normalizeDomainValue(value);
  return normalized == null
      ? null
      : _NormalizedRuleDomain(_RuleDomainType.suffix, normalized);
}

String? _normalizeDomainValue(String value) {
  var normalized = value.trim().toLowerCase();
  if (normalized.isEmpty) {
    return null;
  }
  while (normalized.startsWith('.')) {
    normalized = normalized.substring(1);
  }
  while (normalized.endsWith('.')) {
    normalized = normalized.substring(0, normalized.length - 1);
  }
  if (normalized.isEmpty ||
      normalized.contains('..') ||
      normalized.contains(':') ||
      normalized.contains('/') ||
      normalized.contains('*') ||
      !RegExp(r'^[a-z0-9.\-_]+$').hasMatch(normalized)) {
    return null;
  }
  return normalized;
}

Uint8List _buildSrsRuleSet({
  required List<String> domains,
  required List<String> domainSuffixes,
}) {
  final body = _ByteAccumulator();
  _writeUvarint(
    body,
    (domains.isNotEmpty || domainSuffixes.isNotEmpty) ? 1 : 0,
  );
  if (domains.isNotEmpty || domainSuffixes.isNotEmpty) {
    _writeDefaultDomainRule(
      body,
      domains: domains,
      domainSuffixes: domainSuffixes,
    );
  }
  final compressedBody = Uint8List.fromList(
    ZLibEncoder(level: 9).convert(body.toBytes()),
  );
  final result = _ByteAccumulator();
  result.writeBytes(_srsMagicBytes);
  result.writeByte(_srsVersion2);
  result.writeBytes(compressedBody);
  return result.toBytes();
}

void _writeDefaultDomainRule(
  _ByteAccumulator writer, {
  required List<String> domains,
  required List<String> domainSuffixes,
}) {
  writer.writeByte(0);
  writer.writeByte(_ruleItemDomain);
  _buildDomainMatcher(
    domains: domains,
    domainSuffixes: domainSuffixes,
  ).writeTo(writer);
  writer.writeByte(_ruleItemFinal);
  writer.writeByte(0);
}

_DomainMatcher _buildDomainMatcher({
  required List<String> domains,
  required List<String> domainSuffixes,
}) {
  final domainList = <String>[];
  final seen = <String>{};

  for (final domain in domainSuffixes) {
    if (domain.isEmpty || !seen.add('s:$domain')) {
      continue;
    }
    domainList.add(_reverseAscii('$_rootLabelMarker$domain'));
  }
  for (final domain in domains) {
    if (domain.isEmpty || !seen.add('d:$domain')) {
      continue;
    }
    domainList.add(_reverseAscii(domain));
  }

  domainList.sort();
  return _DomainMatcher(_buildSuccinctSet(domainList));
}

_SuccinctSet _buildSuccinctSet(List<String> keys) {
  final leaves = <int>[];
  final labelBitmap = <int>[];
  final labels = <int>[];
  var labelIndex = 0;
  final queue = <_QueueEntry>[_QueueEntry(0, keys.length, 0)];

  for (var i = 0; i < queue.length; i++) {
    final entry = queue[i];
    if (entry.start >= entry.end) {
      continue;
    }
    var start = entry.start;
    if (entry.column == keys[start].length) {
      start++;
      _setBit(leaves, i, 1);
    }
    for (var j = start; j < entry.end;) {
      final from = j;
      final currentByte = keys[from].codeUnitAt(entry.column);
      while (j < entry.end && keys[j].codeUnitAt(entry.column) == currentByte) {
        j++;
      }
      queue.add(_QueueEntry(from, j, entry.column + 1));
      labels.add(currentByte);
      _setBit(labelBitmap, labelIndex, 0);
      labelIndex++;
    }
    _setBit(labelBitmap, labelIndex, 1);
    labelIndex++;
  }

  return _SuccinctSet(
    leaves: leaves,
    labelBitmap: labelBitmap,
    labels: Uint8List.fromList(labels),
  );
}

String _reverseAscii(String value) {
  return String.fromCharCodes(value.codeUnits.reversed);
}

void _setBit(List<int> bitmap, int index, int value) {
  final wordIndex = index >> 6;
  while (wordIndex >= bitmap.length) {
    bitmap.add(0);
  }
  bitmap[wordIndex] |= value << (index & 63);
}

void _writeUvarint(_ByteAccumulator writer, int value) {
  var current = value;
  while (current >= 0x80) {
    writer.writeByte((current & 0xFF) | 0x80);
    current >>= 7;
  }
  writer.writeByte(current & 0xFF);
}

class _ByteAccumulator {
  final BytesBuilder _builder = BytesBuilder(copy: false);

  void writeByte(int value) => _builder.addByte(value & 0xFF);

  void writeBytes(List<int> values) {
    if (values.isNotEmpty) {
      _builder.add(values);
    }
  }

  void writeUint64List(List<int> values) {
    _writeUvarint(this, values.length);
    if (values.isEmpty) {
      return;
    }
    final data = ByteData(values.length * 8);
    for (var i = 0; i < values.length; i++) {
      data.setUint64(i * 8, values[i], Endian.big);
    }
    writeBytes(data.buffer.asUint8List());
  }

  void writeByteList(Uint8List values) {
    _writeUvarint(this, values.length);
    writeBytes(values);
  }

  Uint8List toBytes() => _builder.takeBytes();
}

class _CompiledRuleSetArtifact {
  const _CompiledRuleSetArtifact({
    required this.ruleSetBytes,
    required this.domainCount,
  });

  final Uint8List ruleSetBytes;
  final int domainCount;
}

class _DomainMatcher {
  const _DomainMatcher(this.set);

  final _SuccinctSet set;

  void writeTo(_ByteAccumulator writer) => set.writeTo(writer);
}

class _SuccinctSet {
  const _SuccinctSet({
    required this.leaves,
    required this.labelBitmap,
    required this.labels,
  });

  final List<int> leaves;
  final List<int> labelBitmap;
  final Uint8List labels;

  void writeTo(_ByteAccumulator writer) {
    writer.writeByte(0);
    writer.writeUint64List(leaves);
    writer.writeUint64List(labelBitmap);
    writer.writeByteList(labels);
  }
}

class _QueueEntry {
  const _QueueEntry(this.start, this.end, this.column);

  final int start;
  final int end;
  final int column;
}

class _NormalizedRuleDomain {
  const _NormalizedRuleDomain(this.type, this.value);

  final _RuleDomainType type;
  final String value;
}

enum _RuleDomainType { exact, suffix }

const List<int> _srsMagicBytes = <int>[0x53, 0x52, 0x53];
const int _srsVersion2 = 2;
const int _ruleItemDomain = 2;
const int _ruleItemFinal = 0xFF;
const String _rootLabelMarker = '\n';
