/// 应用配置
/// 
/// 通过设置 isWebMode = true 来编译Web版（无WiFi扫描功能）
/// 通过设置 isWebMode = false 来编译Android版（完整WiFi扫描功能）
class AppConfig {
  /// Web版标志 - 设为true时编译为Web版（iOS可用）
  /// 设为false时编译为Android版
  /// 
  /// 使用方式：
  /// flutter build web   -> Web版
  /// flutter build apk   -> Android版
  static const bool isWebMode = true;
}
