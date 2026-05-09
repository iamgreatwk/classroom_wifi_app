// Web平台的share_plus stub实现
// 在Web平台上，分享功能通过JavaScript实现

import 'dart:typed_data';

class Share {
  static Future<void> shareXFiles(List<XFile> files, {String? subject}) async {
    throw UnsupportedError('Share.shareXFiles is not supported on Web');
  }

  static Future<void> share(String text, {String? subject}) async {
    throw UnsupportedError('Share.share is not supported on Web');
  }
}

class XFile {
  final String path;
  final String? mimeType;
  final String? name;

  XFile(
    this.path, {
    this.mimeType,
    this.name,
  });

  XFile.fromData(
    Uint8List bytes, {
    this.mimeType,
    this.name,
    int? length,
    DateTime? lastModified,
    String? path,
  }) : path = path ?? '';

  Future<Uint8List> readAsBytes() async => Uint8List(0);
  Future<String> readAsString() async => '';
}
