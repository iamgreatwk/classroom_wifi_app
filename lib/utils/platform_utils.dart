import 'package:flutter/foundation.dart';

// 条件导入 JS 桥接
export 'web/js_bridge_stub.dart'
    if (dart.library.js) 'web/js_bridge.dart';

/// 平台工具类
/// 处理 Web 和移动端的不同实现
class PlatformUtils {
  /// 判断是否为 Web 平台
  static bool get isWeb => kIsWeb;
  
  /// 判断是否为移动端（iOS/Android）
  static bool get isMobile => !kIsWeb;
}
