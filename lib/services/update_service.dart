import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

class UpdateInfo {
  UpdateInfo({
    required this.latestVersion,
    required this.currentVersion,
    required this.apkUrl,
    required this.releaseNotes,
    required this.hasUpdate,
  });

  final String latestVersion;
  final String currentVersion;
  final String apkUrl;
  final String releaseNotes;
  final bool hasUpdate;
}

/// 通过 GitHub Release 检查/下载/安装 APK 更新。
/// 仓库:findscripter/P2P-IM-portal-app(tag 形式 vX.Y.Z,Release 资产为 .apk)
class UpdateService {
  UpdateService({
    this.owner = 'findscripter',
    this.repo = 'P2P-IM-portal-app',
  });

  final String owner;
  final String repo;
  final Dio _dio = Dio();

  Future<UpdateInfo?> checkUpdate() async {
    if (!Platform.isAndroid) return null;
    try {
      final info = await PackageInfo.fromPlatform();
      final current = info.version;
      final url = 'https://api.github.com/repos/$owner/$repo/releases/latest';
      final resp = await _dio.get<Map<String, dynamic>>(
        url,
        options: Options(
          headers: {'Accept': 'application/vnd.github+json'},
          receiveTimeout: const Duration(seconds: 10),
        ),
      );
      final data = resp.data;
      if (data == null) return null;
      final tag = (data['tag_name'] as String?)?.replaceFirst(RegExp(r'^v'), '');
      final notes = (data['body'] as String?) ?? '';
      final assets = (data['assets'] as List?) ?? [];
      String? apkUrl;
      for (final a in assets) {
        final name = (a['name'] as String?) ?? '';
        if (name.toLowerCase().endsWith('.apk')) {
          apkUrl = a['browser_download_url'] as String?;
          break;
        }
      }
      if (tag == null || apkUrl == null) return null;
      return UpdateInfo(
        latestVersion: tag,
        currentVersion: current,
        apkUrl: apkUrl,
        releaseNotes: notes,
        hasUpdate: _isNewer(tag, current),
      );
    } catch (e) {
      debugPrint('[UpdateService] checkUpdate failed: $e');
      return null;
    }
  }

  /// 下载并触发系统安装器。onProgress 回调 0.0~1.0
  Future<void> downloadAndInstall(
    String apkUrl, {
    void Function(double progress)? onProgress,
  }) async {
    final granted = await _ensureInstallPermission();
    if (!granted) {
      throw Exception('未授予"安装未知应用"权限,请在系统设置中开启后重试');
    }
    final dir = await getExternalStorageDirectory() ?? await getTemporaryDirectory();
    final file = File('${dir.path}/portal-update.apk');
    if (file.existsSync()) {
      await file.delete();
    }
    await _dio.download(
      apkUrl,
      file.path,
      onReceiveProgress: (count, total) {
        if (total > 0 && onProgress != null) {
          onProgress(count / total);
        }
      },
    );
    final result = await OpenFilex.open(file.path);
    if (result.type != ResultType.done) {
      throw Exception('打开安装器失败:${result.message}');
    }
  }

  Future<bool> _ensureInstallPermission() async {
    final status = await Permission.requestInstallPackages.status;
    if (status.isGranted) return true;
    final r = await Permission.requestInstallPackages.request();
    return r.isGranted;
  }

  /// 简易语义版本比较(只比 major.minor.patch,不处理 pre-release)
  bool _isNewer(String latest, String current) {
    final l = _parse(latest);
    final c = _parse(current);
    for (var i = 0; i < 3; i++) {
      if (l[i] > c[i]) return true;
      if (l[i] < c[i]) return false;
    }
    return false;
  }

  List<int> _parse(String v) {
    final parts = v.split('.').map((p) {
      final m = RegExp(r'^\d+').firstMatch(p);
      return int.tryParse(m?.group(0) ?? '0') ?? 0;
    }).toList();
    while (parts.length < 3) {
      parts.add(0);
    }
    return parts;
  }
}
