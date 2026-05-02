import 'package:flutter/material.dart';

/// 输入框 + 号弹出面板
class PlusMenuSheet {
  static void show(BuildContext context, {
    VoidCallback? onFile,
    VoidCallback? onImage,
    VoidCallback? onCamera,
    VoidCallback? onVoiceCall,
    VoidCallback? onVideoCall,
    VoidCallback? onLocation,
  }) {
    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2))),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildItem(Icons.photo_library, '图片', onImage),
                  _buildItem(Icons.camera_alt, '拍照', onCamera),
                  _buildItem(Icons.insert_drive_file, '文件', onFile),
                  _buildItem(Icons.location_on, '位置', onLocation),
                ],
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildItem(Icons.phone, '语音通话', onVoiceCall, color: Colors.green),
                  _buildItem(Icons.videocam, '视频通话', onVideoCall, color: Colors.green),
                  const SizedBox(width: 72),
                  const SizedBox(width: 72),
                ],
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  static Widget _buildItem(IconData icon, String label, VoidCallback? onTap, {Color color = const Color(0xFF6C63FF)}) {
    return GestureDetector(
      onTap: onTap,
      child: Column(children: [
        Container(
          width: 56, height: 56,
          decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(16)),
          child: Icon(icon, color: color, size: 28),
        ),
        const SizedBox(height: 6),
        Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[700])),
      ]),
    );
  }
}
