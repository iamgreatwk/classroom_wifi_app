// 非 Web 平台：提供 JS 的 stub 实现

class JsObject {
  dynamic operator [](dynamic key) => null;
  void operator []=(dynamic key, dynamic value) {}
  dynamic callMethod(String method, [List<dynamic>? args]) => null;
  void deleteProperty(dynamic key) {}
}

class JsFunction {
  static dynamic allowInterop(Function fn) => fn;
}

// 模拟 js 库的结构
class _JsContext {
  dynamic operator [](dynamic key) => null;
  void operator []=(dynamic key, dynamic value) {}
  dynamic callMethod(String method, [List<dynamic>? args]) => null;
  void deleteProperty(dynamic key) {}
  dynamic allowInterop(Function fn) => fn;
}

class _JsStub {
  final _JsContext context = _JsContext();
  dynamic allowInterop(Function fn) => fn;
}

final js = _JsStub();
