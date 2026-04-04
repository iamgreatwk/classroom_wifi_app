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
      // 等待 html2canvas 加载完成
      bool html2canvasLoaded = await _waitForHtml2Canvas(timeoutMs: 5000);
      if (!html2canvasLoaded) {
        print('html2canvas not loaded after timeout');
        return null;
      }

      final completer = Completer<Uint8List?>();

      // 创建成功回调函数
      js.context['__screenshotSuccess'] = js.allowInterop((String dataUrl) {
        try {
          final base64Data = dataUrl.split(',')[1];
          final bytes = base64Decode(base64Data);
          completer.complete(bytes);
        } catch (e) {
          print('Error decoding base64: $e');
          completer.complete(null);
        }
        // 清理回调
        js.context.deleteProperty('__screenshotSuccess');
        js.context.deleteProperty('__screenshotError');
      });

      // 创建错误回调函数
      js.context['__screenshotError'] = js.allowInterop((String error) {
        print('Screenshot JS error: $error');
        completer.complete(null);
        // 清理回调
        js.context.deleteProperty('__screenshotSuccess');
        js.context.deleteProperty('__screenshotError');
      });

      // 执行截图脚本
      js.context.callMethod('eval', ['''
        (function() {
          try {
            if (typeof html2canvas === 'undefined') {
              window.__screenshotError('html2canvas is undefined');
              return;
            }
            
            html2canvas(document.body, {
              scale: 2,
              useCORS: true,
              allowTaint: true,
              backgroundColor: '#ffffff',
              logging: true,
              width: window.innerWidth,
              height: window.innerHeight
            }).then(function(canvas) {
              try {
                var dataUrl = canvas.toDataURL('image/png');
                window.__screenshotSuccess(dataUrl);
              } catch (e) {
                window.__screenshotError('toDataURL error: ' + e.message);
              }
            }).catch(function(err) {
              window.__screenshotError('html2canvas error: ' + err.message);
            });
          } catch (e) {
            window.__screenshotError('JS execution error: ' + e.message);
          }
        })()
      ''']);

      // 设置超时
      Future.delayed(Duration(seconds: 10), () {
        if (!completer.isCompleted) {
          print('Screenshot timeout');
          completer.complete(null);
          js.context.deleteProperty('__screenshotSuccess');
          js.context.deleteProperty('__screenshotError');
        }
      });

      return completer.future;
    } catch (e, stackTrace) {
      print('ScreenshotService.capturePage error: $e');
      print('Stack trace: $stackTrace');
      return null;
    }
  }

  /// 等待 html2canvas 加载
  static Future<bool> _waitForHtml2Canvas({required int timeoutMs}) async {
    final startTime = DateTime.now();
    while (DateTime.now().difference(startTime).inMilliseconds < timeoutMs) {
      try {
        final hasHtml2Canvas = js.context.callMethod('eval', ['typeof html2canvas !== "undefined"']);
        if (hasHtml2Canvas == true) {
          return true;
        }
      } catch (e) {
        // 忽略错误
      }
      await Future.delayed(Duration(milliseconds: 100));
    }
    return false;
  }
}
