// ignore: avoid_web_libraries_in_flutter
import 'dart:js' as js;

/// Web 平台 JS 桥接
class JSBridge {
  /// 调用 JS eval
  static void eval(String script) {
    js.context.callMethod('eval', [script]);
  }
  
  /// 获取 JS 变量
  static dynamic getProperty(String name) {
    return js.context[name];
  }
  
  /// 设置 JS 变量
  static void setProperty(String name, dynamic value) {
    js.context[name] = value;
  }
  
  /// 调用 JS 方法
  static dynamic callMethod(String method, [List<dynamic>? args]) {
    return js.context.callMethod(method, args);
  }
}
