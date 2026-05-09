// 条件导入文件
// 在 Web 平台导出 dart:js 和 dart:html，在其他平台导出空实现

export 'web/js_stub.dart' if (dart.library.js) 'web/js_real.dart' hide JsObject;
export 'web/html_stub.dart' if (dart.library.html) 'web/html_real.dart';
