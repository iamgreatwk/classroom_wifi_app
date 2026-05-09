/// 平台工具类
/// iOS 专用实现
class PlatformUtils {
  /// 判断是否为 Web 平台（iOS 项目始终返回 false）
  static bool get isWeb => false;

  /// 判断是否为移动端（iOS 项目始终返回 true）
  static bool get isMobile => true;
}
