import 'package:flutter/material.dart';
import '../services/update_service.dart';

class UpdateDialog extends StatefulWidget {
  const UpdateDialog({super.key, required this.info});

  final UpdateInfo info;

  static Future<void> show(BuildContext context, UpdateInfo info) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => UpdateDialog(info: info),
    );
  }

  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<UpdateDialog> {
  final UpdateService _service = UpdateService();
  double _progress = 0;
  bool _downloading = false;
  String? _error;

  Future<void> _doUpdate() async {
    setState(() {
      _downloading = true;
      _error = null;
    });
    try {
      await _service.downloadAndInstall(
        widget.info.apkUrl,
        onProgress: (p) => setState(() => _progress = p),
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() {
          _downloading = false;
          _error = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final info = widget.info;
    return AlertDialog(
      title: Text('发现新版本 v${info.latestVersion}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('当前版本:v${info.currentVersion}',
              style: const TextStyle(color: Colors.grey)),
          const SizedBox(height: 12),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 200),
            child: SingleChildScrollView(
              child: Text(info.releaseNotes.isEmpty ? '(无更新说明)' : info.releaseNotes),
            ),
          ),
          if (_downloading) ...[
            const SizedBox(height: 16),
            LinearProgressIndicator(value: _progress),
            const SizedBox(height: 4),
            Text('${(_progress * 100).toStringAsFixed(1)}%'),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: const TextStyle(color: Colors.red)),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _downloading ? null : () => Navigator.pop(context),
          child: const Text('稍后'),
        ),
        FilledButton(
          onPressed: _downloading ? null : _doUpdate,
          child: const Text('立即更新'),
        ),
      ],
    );
  }
}
