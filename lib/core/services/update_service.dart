import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

class ReleaseAsset {
  const ReleaseAsset({
    required this.name,
    required this.browserDownloadUrl,
    required this.size,
  });

  final String name;
  final String browserDownloadUrl;
  final int size;
}

class AppUpdateInfo {
  const AppUpdateInfo({
    required this.currentVersion,
    required this.latestVersion,
    required this.tagName,
    required this.releaseUrl,
    required this.releaseNotes,
    required this.assets,
    required this.hasUpdate,
  });

  final String currentVersion;
  final String latestVersion;
  final String tagName;
  final String releaseUrl;
  final String releaseNotes;
  final List<ReleaseAsset> assets;
  final bool hasUpdate;

  ReleaseAsset? preferredApkAsset() {
    if (assets.isEmpty) {
      return null;
    }
    final apks = assets
        .where((a) => a.name.toLowerCase().endsWith('.apk'))
        .toList(growable: false);
    if (apks.isEmpty) {
      return null;
    }
    for (final nameHint in const <String>['arm64-v8a', 'armeabi-v7a']) {
      for (final asset in apks) {
        if (asset.name.contains(nameHint)) {
          return asset;
        }
      }
    }
    return apks.first;
  }
}

class UpdateService {
  UpdateService({http.Client? client}) : _client = client ?? http.Client();

  static const String _latestReleaseUrl =
      'https://api.github.com/repos/bitplugg/mouvi/releases/latest';

  final http.Client _client;

  Future<AppUpdateInfo> checkForUpdates() async {
    final packageInfo = await PackageInfo.fromPlatform();
    final current = packageInfo.version.trim();
    final response = await _client
        .get(
          Uri.parse(_latestReleaseUrl),
          headers: const <String, String>{
            'Accept': 'application/vnd.github+json',
            'X-GitHub-Api-Version': '2022-11-28',
          },
        )
        .timeout(const Duration(seconds: 15));

    if (response.statusCode != 200) {
      throw UpdateCheckException('http_${response.statusCode}');
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const UpdateCheckException('invalid_response');
    }

    final tagName = (decoded['tag_name'] as String?)?.trim() ?? '';
    final latest = _normalizeVersion(tagName);
    final releaseUrl =
        (decoded['html_url'] as String?)?.trim() ??
        'https://github.com/bitplugg/mouvi/releases';
    final notes = (decoded['body'] as String?)?.trim() ?? '';
    final assets = <ReleaseAsset>[];
    final rawAssets = decoded['assets'];
    if (rawAssets is List) {
      for (final item in rawAssets) {
        if (item is! Map<String, dynamic>) {
          continue;
        }
        final name = (item['name'] as String?)?.trim() ?? '';
        final url = (item['browser_download_url'] as String?)?.trim() ?? '';
        if (name.isEmpty || url.isEmpty) {
          continue;
        }
        final size = item['size'] is int ? item['size'] as int : 0;
        assets.add(
          ReleaseAsset(name: name, browserDownloadUrl: url, size: size),
        );
      }
    }

    return AppUpdateInfo(
      currentVersion: current.isEmpty ? packageInfo.version : current,
      latestVersion: latest.isEmpty ? tagName : latest,
      tagName: tagName,
      releaseUrl: releaseUrl,
      releaseNotes: notes,
      assets: List<ReleaseAsset>.unmodifiable(assets),
      hasUpdate: _isNewer(latest, current),
    );
  }

  static String _normalizeVersion(String value) {
    var v = value.trim();
    if (v.startsWith('v') || v.startsWith('V')) {
      v = v.substring(1);
    }
    final plus = v.indexOf('+');
    if (plus >= 0) {
      v = v.substring(0, plus);
    }
    return v.trim();
  }

  static bool _isNewer(String latest, String current) {
    final a = _parseSemver(latest);
    final b = _parseSemver(current);
    if (a == null || b == null) {
      if (latest.isEmpty || current.isEmpty) {
        return false;
      }
      return latest != current;
    }
    for (var i = 0; i < 3; i++) {
      if (a[i] != b[i]) {
        return a[i] > b[i];
      }
    }
    return false;
  }

  static List<int>? _parseSemver(String value) {
    final normalized = _normalizeVersion(value);
    if (normalized.isEmpty) {
      return null;
    }
    final core = normalized.split('-').first;
    final parts = core.split('.');
    if (parts.isEmpty) {
      return null;
    }
    final nums = <int>[0, 0, 0];
    for (var i = 0; i < parts.length && i < 3; i++) {
      final match = RegExp(r'^\d+').firstMatch(parts[i]);
      if (match == null) {
        return null;
      }
      nums[i] = int.tryParse(match.group(0)!) ?? 0;
    }
    return nums;
  }
}

class UpdateCheckException implements Exception {
  const UpdateCheckException(this.code);

  final String code;

  @override
  String toString() => 'UpdateCheckException($code)';
}

final updateServiceProvider = Provider<UpdateService>((ref) {
  return UpdateService();
});
