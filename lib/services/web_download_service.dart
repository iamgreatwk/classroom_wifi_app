import 'dart:html' as html;
import 'dart:typed_data';
import 'package:flutter/foundation.dart';

/// Web 下载服务
/// 用于在 Web 平台下载文件
class WebDownloadService {
  /// 下载二进制文件（Web 版使用 HTML5 下载）
  static Future<void> downloadBytes(Uint8List bytes, String fileName) async {
    if (kIsWeb) {
      await _downloadForWeb(bytes, fileName);
    } else {
      // 非 Web 平台暂不支持
      throw UnsupportedError('仅支持 Web 平台');
    }
  }
  
  /// Web 平台下载实现
  static Future<void> _downloadForWeb(Uint8List bytes, String fileName) async {
    // 创建 Blob
    final blob = html.Blob([bytes], 'image/png');
    
    // 创建 Object URL
    final url = html.Url.createObjectUrlFromBlob(blob);
    
    // 创建 a 标签并触发下载
    final anchor = html.AnchorElement(href: url)
      ..setAttribute('download', fileName)
      ..style.display = 'none';
    
    html.document.body!.children.add(anchor);
    anchor.click();
    html.document.body!.children.remove(anchor);
    
    // 释放 Object URL
    html.Url.revokeObjectUrl(url);
  }
  
  /// 下载文本文件
  static Future<void> downloadText(String text, String fileName) async {
    if (kIsWeb) {
      final bytes = Uint8List.fromList(text.codeUnits);
      await _downloadForWeb(bytes, fileName);
    } else {
      throw UnsupportedError('仅支持 Web 平台');
    }
  }
}
