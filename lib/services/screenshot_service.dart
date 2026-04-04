import 'dart:async';
import 'dart:js' as js;
import 'dart:typed_data';
import 'dart:convert';

/// 截图服务 - 使用 html2canvas 实现跨平台截图（支持 iOS Safari）
class ScreenshotService {
  /// 使用 html2canvas 捕获整个页面为图片
  /// 
  /// 返回 PNG 格式的图片字节数据
  static Future<Uint8List?> capturePage() async {
    try {
      // 检查全局函数是否存在
      if (!js.context.hasProperty('captureScreenshot')) {
        print('captureScreenshot function not available');
        return null;
      }

      final completer = Completer<Uint8List?>();

      // 调用全局截图函数
      js.context.callMethod('captureScreenshot').then((result) {
        // 将 base64 data URL 转换为 Uint8List
        final dataUrl = result.toString();
        final base64Data = dataUrl.split(',')[1];
        final bytes = base64Decode(base64Data);
        completer.complete(bytes);
      }).catchError((error) {
        print('captureScreenshot error: $error');
        completer.complete(null);
      });

      return completer.future;
    } catch (e) {
      print('ScreenshotService.capturePage error: $e');
      return null;
    }
  }
}
