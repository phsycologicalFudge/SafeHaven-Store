import 'dart:convert';
import 'package:http/http.dart' as http;

import 'store_service/store_auth_service.dart';
import 'store_service/store_config.dart';
import 'store_service/store_exceptions.dart';
import 'store_service/store_http_utils.dart';

export 'store_service/store_exceptions.dart';
export 'store_service/store_auth_service.dart' show StoreAccount, StoreAuthService;

class StoreService {
  StoreService._();

  static final StoreService instance = StoreService._();

  static const String defaultBaseUrl = storeDefaultBaseUrl;

  Future<StoreIndex> fetchIndex() async {
    final uri = Uri.parse('$defaultBaseUrl/store/index.json');
    final res = await http.get(uri);

    storeThrowIfBad(res);

    return StoreIndex.fromJson(storeDecodeMap(res.body));
  }

  Future<PublicStoreApp> fetchPublicApp(String packageName) async {
    final uri = Uri.parse(
      '$defaultBaseUrl/store/catalog/${Uri.encodeComponent(packageName)}',
    );
    final res = await http.get(uri);

    storeThrowIfBad(res);

    return PublicStoreApp.fromJson(storeDecodeMap(res.body));
  }

  Future<List<DeveloperStoreApp>> fetchDeveloperApps() async {
    final token = await StoreAuthService.instance.requireToken();
    final res = await http.get(
      Uri.parse('$defaultBaseUrl/store/apps'),
      headers: storeAuthHeaders(token),
    );

    storeThrowIfBad(res);

    final body = storeDecodeMap(res.body);
    final apps = body['apps'];
    if (apps is! List) return const [];

    return apps
        .whereType<Map<String, dynamic>>()
        .map(DeveloperStoreApp.fromJson)
        .toList();
  }

  Future<DeveloperAppDetail> fetchDeveloperApp(String appId) async {
    final token = await StoreAuthService.instance.requireToken();
    final res = await http.get(
      Uri.parse('$defaultBaseUrl/store/apps/$appId'),
      headers: storeAuthHeaders(token),
    );

    storeThrowIfBad(res);

    return DeveloperAppDetail.fromJson(storeDecodeMap(res.body));
  }

  Future<String> getDownloadUrl({
    required String packageName,
    required int versionCode,
  }) async {
    final res = await http.get(
      Uri.parse(
        '$defaultBaseUrl/store/apps/${Uri.encodeComponent(packageName)}/download/$versionCode',
      ),
    );

    storeThrowIfBad(res);

    final body = storeDecodeMap(res.body);
    final url = body['url'];
    if (url == null || url.toString().isEmpty) {
      throw const StoreApiException('missing_url');
    }
    return url.toString();
  }

  Future<String> submitRating({
    required String packageName,
    required String deviceToken,
    required int rating,
  }) async {
    final res = await http.post(
      Uri.parse('$defaultBaseUrl/store/ratings'),
      headers: {'content-type': 'application/json; charset=utf-8'},
      body: jsonEncode({
        'packageName': packageName,
        'deviceToken': deviceToken,
        'rating': rating,
      }),
    );

    storeThrowIfBad(res);
    return 'ok';
  }
}

class StoreIndex {
  const StoreIndex({
    required this.timestamp,
    required this.categories,
    required this.apps,
  });

  final int timestamp;
  final Map<String, String> categories;
  final List<PublicStoreApp> apps;

  factory StoreIndex.fromJson(Map<String, dynamic> json) {
    final apps = json['apps'];
    final cats = json['categories'];

    return StoreIndex(
      timestamp: _asInt(json['timestamp']),
      categories: cats is Map
          ? Map<String, String>.fromEntries(
        cats.entries.map((e) => MapEntry(e.key.toString(), e.value.toString())),
      )
          : const {},
      apps: apps is List
          ? apps
          .whereType<Map<String, dynamic>>()
          .map(PublicStoreApp.fromJson)
          .toList()
          : const [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'timestamp': timestamp,
      'categories': categories,
      'apps': apps.map((a) => a.toJson()).toList(),
    };
  }
}

class PublicStoreApp {
  const PublicStoreApp({
    required this.packageName,
    required this.name,
    required this.summary,
    required this.description,
    required this.repoUrl,
    required this.trustLevel,
    required this.category,
    required this.upstream,
    required this.ratingAvg,
    required this.ratingCount,
    required this.versions,
    required this.iconUrl,
    required this.screenshots,
    required this.signingKeyHash,
  });

  static final _vRegex = RegExp(r'^v', caseSensitive: false);

  final String packageName;
  final String name;
  final String summary;
  final String description;
  final String repoUrl;
  final String trustLevel;
  final String category;
  final String upstream;
  final double ratingAvg;
  final int ratingCount;
  final List<StoreVersion> versions;
  final String? iconUrl;
  final List<String> screenshots;
  final String? signingKeyHash;

  factory PublicStoreApp.fromJson(Map<String, dynamic> json) {
    final versions = json['versions'];
    final screenshots = json['screenshots'];

    return PublicStoreApp(
      packageName: _asString(json['packageName']),
      name: _asString(json['name']),
      summary: _asString(json['summary']),
      description: _asString(json['description']),
      repoUrl: _asString(json['repoUrl']),
      trustLevel: _normaliseTrustLevel(json['trustLevel']),
      category: _asString(json['category']),
      upstream: _asString(json['upstream']),
      ratingAvg: _asDouble(json['ratingAvg']),
      ratingCount: _asInt(json['ratingCount']),
      versions: versions is List
          ? versions
          .whereType<Map<String, dynamic>>()
          .map(StoreVersion.fromJson)
          .toList()
          : const [],
      iconUrl: _normaliseImageUrl(_asNullableString(json['iconUrl'])),
      screenshots: screenshots is List
          ? screenshots.whereType<String>().map((s) => _normaliseImageUrl(s) ?? s).toList()
          : const [],
      signingKeyHash: _asNullableString(json['signingKeyHash']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'packageName': packageName,
      'name': name,
      'summary': summary,
      'description': description,
      'repoUrl': repoUrl,
      'trustLevel': trustLevel,
      'category': category,
      'upstream': upstream,
      'ratingAvg': ratingAvg,
      'ratingCount': ratingCount,
      'versions': versions.map((v) => v.toJson()).toList(),
      'iconUrl': iconUrl,
      'screenshots': screenshots,
      'signingKeyHash': signingKeyHash,
    };
  }

  StoreVersion? get latestVersion {
    if (versions.isEmpty) return null;
    return versions.reduce((a, b) => a.versionCode >= b.versionCode ? a : b);
  }

  bool get hasTrustBadge => trustLevel.isNotEmpty;

  bool get securityReviewed => trustLevel == 'security_reviewed';

  bool get verifiedSource => trustLevel == 'verified_source';

  String get trustLabel {
    switch (trustLevel) {
      case 'security_reviewed':
        return 'Security Reviewed';
      case 'verified_source':
        return 'Verified Source';
      default:
        return 'Unverified developer';
    }
  }

  String get trustDescription {
    if (upstream.toLowerCase() == 'fdroid') {
      return 'This application is from F-Droid.';
    }
    if (upstream.toLowerCase() == 'izzyondroid') {
      return 'This application is from IzzyOnDroid.';
    }

    switch (trustLevel) {
      case 'security_reviewed':
        return 'This app has received an enhanced security review.';
      case 'verified_source':
        return 'Source ownership has been verified for this listing.';
      default:
        return 'This listing was submitted by the community, not the original developer.';
    }
  }

  String get displaySummary {
    if (summary.trim().isNotEmpty) return summary.trim();
    if (description.trim().isNotEmpty) return description.trim();
    return 'No description available.';
  }

  String get displayVersion {
    final latest = latestVersion;
    if (latest == null || latest.versionName.isEmpty) return 'No live version';
    final name = latest.versionName.replaceFirst(_vRegex, '');
    return 'v$name';
  }

  String get developerName {
    if (repoUrl.isEmpty) return '';
    final uri = Uri.tryParse(repoUrl.trim());
    if (uri == null) return '';
    final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    return segments.isNotEmpty ? segments.first : '';
  }

  String get displayRating {
    if (ratingCount == 0) return '—';
    return ratingAvg.toStringAsFixed(1);
  }
}

class StoreVersion {
  const StoreVersion({
    required this.versionName,
    required this.versionCode,
    required this.apkPath,
    required this.apkSize,
    required this.sha256,
    required this.scannedAt,
    required this.added,
    required this.whatsNew,
  });

  final String versionName;
  final int versionCode;
  final String apkPath;
  final int apkSize;
  final String sha256;
  final int scannedAt;
  final int added;
  final String? whatsNew;

  factory StoreVersion.fromJson(Map<String, dynamic> json) {
    return StoreVersion(
      versionName: _asString(json['versionName']),
      versionCode: _asInt(json['versionCode']),
      apkPath: _asString(json['apkPath']),
      apkSize: _asInt(json['apkSize']),
      sha256: _asString(json['sha256']),
      scannedAt: _asInt(json['scannedAt']),
      added: _asInt(json['added']),
      whatsNew: _asNullableString(json['whatsNew']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'versionName': versionName,
      'versionCode': versionCode,
      'apkPath': apkPath,
      'apkSize': apkSize,
      'sha256': sha256,
      'scannedAt': scannedAt,
      'added': added,
      'whatsNew': whatsNew,
    };
  }
}

class DeveloperStoreApp {
  const DeveloperStoreApp({
    required this.id,
    required this.packageName,
    required this.name,
    required this.summary,
    required this.description,
    required this.repoUrl,
    required this.repoVerified,
    required this.trustLevel,
    required this.status,
    required this.signingKeyHash,
  });

  final String id;
  final String packageName;
  final String name;
  final String summary;
  final String description;
  final String repoUrl;
  final bool repoVerified;
  final String trustLevel;
  final String status;
  final String signingKeyHash;

  factory DeveloperStoreApp.fromJson(Map<String, dynamic> json) {
    return DeveloperStoreApp(
      id: _asString(json['id']),
      packageName: _asString(json['package_name']),
      name: _asString(json['name']),
      summary: _asString(json['summary']),
      description: _asString(json['description']),
      repoUrl: _asString(json['repo_url']),
      repoVerified: _asBool(json['repo_verified']),
      trustLevel: _asString(json['trust_level'], fallback: 'verified_source'),
      status: _asString(json['status'], fallback: 'active'),
      signingKeyHash: _asString(json['signing_key_hash']),
    );
  }

  String get trustLabel {
    if (trustLevel == 'security_reviewed') return 'Security Reviewed';
    return 'Verified Source';
  }

  String get statusLabel {
    switch (status) {
      case 'live':
        return 'Live';
      case 'active':
        return 'Active';
      case 'pending_upload':
        return 'Pending upload';
      case 'pending_scan':
        return 'Pending scan';
      case 'scanning':
        return 'Scanning';
      case 'pending_review':
        return 'Pending review';
      case 'rejected':
        return 'Rejected';
      case 'suspended':
        return 'Suspended';
      case 'removed':
        return 'Removed';
      default:
        return status.isEmpty ? 'Unknown' : status;
    }
  }
}

class DeveloperAppDetail {
  const DeveloperAppDetail({
    required this.app,
    required this.submissions,
  });

  final DeveloperStoreApp app;
  final List<StoreSubmission> submissions;

  factory DeveloperAppDetail.fromJson(Map<String, dynamic> json) {
    final app = json['app'];
    final submissions = json['submissions'];

    if (app is! Map<String, dynamic>) {
      throw const StoreApiException('app_missing');
    }

    return DeveloperAppDetail(
      app: DeveloperStoreApp.fromJson(app),
      submissions: submissions is List
          ? submissions
          .whereType<Map<String, dynamic>>()
          .map(StoreSubmission.fromJson)
          .toList()
          : const [],
    );
  }
}

class StoreSubmission {
  const StoreSubmission({
    required this.id,
    required this.appId,
    required this.packageName,
    required this.versionName,
    required this.versionCode,
    required this.status,
    required this.apkSha256,
    required this.apkSize,
    required this.scanPassed,
    required this.scanResult,
    required this.rejectionReason,
    required this.submittedAt,
    required this.scannedAt,
  });

  final String id;
  final String appId;
  final String packageName;
  final String versionName;
  final int versionCode;
  final String status;
  final String apkSha256;
  final int apkSize;
  final bool scanPassed;
  final String scanResult;
  final String rejectionReason;
  final int submittedAt;
  final int scannedAt;

  factory StoreSubmission.fromJson(Map<String, dynamic> json) {
    return StoreSubmission(
      id: _asString(json['id']),
      appId: _asString(json['app_id']),
      packageName: _asString(json['package_name']),
      versionName: _asString(json['version_name']),
      versionCode: _asInt(json['version_code']),
      status: _asString(json['status']),
      apkSha256: _asString(json['apk_sha256']),
      apkSize: _asInt(json['apk_size']),
      scanPassed: _asBool(json['scan_passed']),
      scanResult: _asString(json['scan_result']),
      rejectionReason: _asString(json['rejection_reason']),
      submittedAt: _asInt(json['submitted_at']),
      scannedAt: _asInt(json['scanned_at']),
    );
  }

  String get statusLabel {
    switch (status) {
      case 'pending_upload':
        return 'Pending upload';
      case 'pending_scan':
        return 'Pending scan';
      case 'scanning':
        return 'Scanning';
      case 'pending_review':
        return 'Pending review';
      case 'live':
        return 'Live';
      case 'rejected':
        return 'Rejected';
      default:
        return status.isEmpty ? 'Unknown' : status;
    }
  }
}

String _asString(dynamic value, {String fallback = ''}) {
  if (value == null) return fallback;
  return value.toString();
}

int _asInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

double _asDouble(dynamic value) {
  if (value is double) return value;
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0.0;
}

bool _asBool(dynamic value) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  final clean = value?.toString().toLowerCase().trim();
  return clean == 'true' || clean == '1' || clean == 'yes';
}

String _normaliseTrustLevel(dynamic value) {
  final clean = value?.toString().trim().toLowerCase();

  switch (clean) {
    case 'verified_source':
    case 'security_reviewed':
      return clean!;
    default:
      return '';
  }
}

String? _asNullableString(dynamic value) {
  if (value == null) return null;

  final clean = value.toString().trim();
  if (clean.isEmpty) return null;

  return clean;
}

const _cdnBase = '$storeDefaultBaseUrl/store/img';

String? _normaliseImageUrl(String? url) {
  if (url == null || url.isEmpty) return null;
  if (url.contains('/store/img/')) return url;
  final match = RegExp(r'https?://[^/]+\.your-objectstorage\.com/[^/]+/(.+)').firstMatch(url);
  if (match == null) return url;
  final key = match.group(1)!;
  if (!key.startsWith('images/')) return url;
  return '$_cdnBase/$key';
}