// 非 Web 平台：提供 JS 的 stub 实现
// 注意：类名使用 _Js 前缀避免与 dart:js 冲突

class _JsStubObject {
  dynamic operator [](dynamic key) => null;
  void operator []=(dynamic key, dynamic value) {}
  dynamic callMethod(String method, [List<dynamic>? args]) => null;
  void deleteProperty(dynamic key) {}
}

class _JsStubFunction {
  static dynamic allowInterop(Function fn) => fn;
}

// 模拟 js 库的结构
class _JsStubContext {
  dynamic operator [](dynamic key) => null;
  void operator []=(dynamic key, dynamic value) {}
  dynamic callMethod(String method, [List<dynamic>? args]) => null;
  void deleteProperty(dynamic key) {}
  dynamic allowInterop(Function fn) => fn;
}

// 导出 js 对象，与 dart:js 保持一致
class _JsStubLibrary {
  final _JsStubContext context = _JsStubContext();
  dynamic allowInterop(Function fn) => fn;
}

final _JsStubLibrary js = _JsStubLibrary();
