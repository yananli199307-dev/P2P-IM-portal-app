import 'package:flutter/material.dart';

/// 根据文件名返回对应图标
class FileIconHelper {
  static Map<String, IconData> _iconMap = {
    'pdf': Icons.picture_as_pdf,
    'doc': Icons.description,
    'docx': Icons.description,
    'xls': Icons.table_chart,
    'xlsx': Icons.table_chart,
    'csv': Icons.table_chart,
    'ppt': Icons.slideshow,
    'pptx': Icons.slideshow,
    'jpg': Icons.image,
    'jpeg': Icons.image,
    'png': Icons.image,
    'gif': Icons.gif,
    'webp': Icons.image,
    'mp4': Icons.movie,
    'mov': Icons.movie,
    'avi': Icons.movie,
    'mp3': Icons.audiotrack,
    'wav': Icons.audiotrack,
    'aac': Icons.audiotrack,
    'zip': Icons.folder_zip,
    'rar': Icons.folder_zip,
    '7z': Icons.folder_zip,
    'txt': Icons.article,
    'md': Icons.article,
  };

  static Map<String, Color> _colorMap = {
    'pdf': Colors.red,
    'doc': Colors.blue,
    'docx': Colors.blue,
    'xls': Colors.green,
    'xlsx': Colors.green,
    'csv': Colors.green,
    'ppt': Colors.orange,
    'pptx': Colors.orange,
    'jpg': Colors.purple,
    'jpeg': Colors.purple,
    'png': Colors.purple,
    'gif': Colors.purple,
    'webp': Colors.purple,
    'mp4': Colors.deepPurple,
    'mov': Colors.deepPurple,
    'avi': Colors.deepPurple,
    'mp3': Colors.teal,
    'wav': Colors.teal,
    'aac': Colors.teal,
    'zip': Colors.brown,
    'rar': Colors.brown,
    '7z': Colors.brown,
    'txt': Colors.grey,
    'md': Colors.grey,
  };

  static IconData getIcon(String? fileName) {
    final ext = _getExtension(fileName);
    return _iconMap[ext] ?? Icons.insert_drive_file;
  }

  static Color getColor(String? fileName) {
    final ext = _getExtension(fileName);
    return _colorMap[ext] ?? Colors.grey;
  }

  static String _getExtension(String? fileName) {
    if (fileName == null) return '';
    final idx = fileName.lastIndexOf('.');
    return idx >= 0 ? fileName.substring(idx + 1).toLowerCase() : '';
  }
}
