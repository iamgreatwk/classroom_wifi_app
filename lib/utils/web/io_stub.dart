// Web平台的dart:io stub实现
// 在Web平台上，dart:io不可用，提供空实现

class File {
  File(String path);
  Future<File> writeAsBytes(List<int> bytes) async => this;
  String get path => '';
}

class Directory {
  String get path => '';
}

class FileSystemException implements Exception {
  final String message;
  FileSystemException(this.message);
  @override
  String toString() => 'FileSystemException: $message';
}
