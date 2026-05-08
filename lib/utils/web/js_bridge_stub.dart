/// Web 平台 JS 桥接（Stub 实现，用于非 Web 平台）
class JSBridge {
  /// 调用 JS eval
  static void eval(String script) {
    throw UnsupportedError('JS eval is only supported on Web platform');
  }
  
  /// 获取 JS 变量
  static dynamic getProperty(String name) {
    throw UnsupportedError('JS properties are only supported on Web platform');
  }
  
  /// 设置 JS 变量
  static void setProperty(String name, dynamic value) {
    throw UnsupportedError('JS properties are only supported on Web platform');
  }
  
  /// 调用 JS 方法
  static dynamic callMethod(String method, [List<dynamic>? args]) {
    throw UnsupportedError('JS methods are only supported on Web platform');
  }
}
