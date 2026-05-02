import 'package:flutter/material.dart';

/// 微信式 + 号面板（嵌入页面，不遮挡输入框）
class PlusMenu extends StatelessWidget {
  final VoidCallback? onFile;
  final VoidCallback? onImage;
  final VoidCallback? onCamera;
  final VoidCallback? onVoiceCall;
  final VoidCallback? onVideoCall;
  final VoidCallback? onLocation;

  const PlusMenu({
    super.key,
    this.onFile,
    this.onImage,
    this.onCamera,
    this.onVoiceCall,
    this.onVideoCall,
    this.onLocation,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.all(16),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
          _buildItem(Icons.photo_library, '图片', onImage),
          _buildItem(Icons.camera_alt, '拍照', onCamera),
          _buildItem(Icons.insert_drive_file, '文件', onFile),
          _buildItem(Icons.location_on, '位置', onLocation),
        ]),
        const SizedBox(height: 12),
        Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
          _buildItem(Icons.phone, '语音', onVoiceCall, color: Colors.green),
          _buildItem(Icons.videocam, '视频', onVideoCall, color: Colors.green),
          const SizedBox(width: 72),
          const SizedBox(width: 72),
        ]),
      ]),
    );
  }

  Widget _buildItem(IconData icon, String label, VoidCallback? onTap, {Color color = const Color(0xFF6C63FF)}) {
    return GestureDetector(
      onTap: onTap,
      child: Column(children: [
        Container(width: 56, height: 56, decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(16)), child: Icon(icon, color: color, size: 28)),
        const SizedBox(height: 4),
        Text(label, style: TextStyle(fontSize: 11, color: Colors.grey[700])),
      ]),
    );
  }
}
