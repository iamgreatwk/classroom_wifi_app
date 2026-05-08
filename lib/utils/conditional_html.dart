// 条件导入文件：dart:html
// 在 Web 平台导出 dart:html，在其他平台导出空实现

export 'web/html_stub.dart' if (dart.library.html) 'web/html_real.dart';
