// 条件导入：dart:io
// 在非Web平台导出 dart:io，在Web平台导出 stub

export 'dart:io' if (dart.library.html) 'web/io_stub.dart';
