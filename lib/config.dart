/// 应用配置
///
/// 默认编译为 iOS/Android 版（isWebMode = false）
/// 如需编译 Web 版，请改为 isWebMode = true
///
/// 使用方式：
/// flutter build ios/apk   -> iOS/Android 版（默认，isWebMode = false）
/// flutter build web       -> Web 版（需手动设置 isWebMode = true）
class AppConfig {
  /// Web版标志
  /// - false (默认): iOS/Android 版，使用 file.path 读取文件
  /// - true: Web 版，使用 file.bytes 读取文件
  static const bool isWebMode = false;
}
