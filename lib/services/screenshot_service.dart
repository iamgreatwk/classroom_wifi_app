import 'dart:async';
import 'dart:js' as js;
import 'dart:typed_data';

/// 截图服务 - 使用 html2canvas 实现跨平台截图（支持 iOS Safari）
class ScreenshotService {
  /// 使用 html2canvas 捕获 Flutter Canvas 为图片
  /// 
  /// 通过查找 flutter 的 canvas 元素并截图
  /// 返回 PNG 格式的图片字节数据
  static Future<Uint8List?> captureFlutterCanvas() async {
    try {
      // 检查 html2canvas 是否可用
      if (!js.context.hasProperty('html2canvas')) {
        print('html2canvas not available');
        return null;
      }

      final completer = Completer<Uint8List?>();

      // 调用 html2canvas 截图整个 body，但只取主要内容区域
      js.context.callMethod('eval', ['''
        (function() {
          // 找到 flutter 的 canvas 元素
          var canvasElements = document.querySelectorAll('canvas');
          var targetCanvas = null;
          
          // 找最大的 canvas（通常是 Flutter 的主渲染 canvas）
          for (var i = 0; i < canvasElements.length; i++) {
            var canvas = canvasElements[i];
            if (canvas.width > 100 && canvas.height > 100) {
              if (!targetCanvas || (canvas.width > targetCanvas.width)) {
                targetCanvas = canvas;
              }
            }
          }
          
          if (!targetCanvas) {
            return Promise.reject('No suitable canvas found');
          }
          
          // 直接转换 canvas 为 data URL
          return Promise.resolve(targetCanvas.toDataURL('image/png'));
        })()
      ''']).then((result) {
        // 将 base64 data URL 转换为 Uint8List
        final dataUrl = result.toString();
        final base64Data = dataUrl.split(',')[1];
        final bytes = _base64Decode(base64Data);
        completer.complete(bytes);
      }).catchError((error) {
        print('html2canvas error: \$error');
        completer.complete(null);
      });

      return completer.future;
    } catch (e) {
      print('ScreenshotService.captureFlutterCanvas error: \$e');
      return null;
    }
  }
  
  /// 使用 html2canvas 捕获指定元素为图片
  /// 
  /// [selector] - CSS 选择器，用于选择要截图的元素
  /// 返回 PNG 格式的图片字节数据
  static Future<Uint8List?> captureElement(String selector) async {
    try {
      // 检查 html2canvas 是否可用
      if (!js.context.hasProperty('html2canvas')) {
        print('html2canvas not available');
        return null;
      }

      final completer = Completer<Uint8List?>();

      // 调用 html2canvas
      js.context.callMethod('eval', ['''
        (function() {
          var element = document.querySelector('$selector');
          if (!element) {
            return Promise.reject('Element not found: $selector');
          }
          
          return html2canvas(element, {
            scale: 2,
            useCORS: true,
            allowTaint: true,
            backgroundColor: '#ffffff',
            logging: false
          }).then(function(canvas) {
            return canvas.toDataURL('image/png');
          });
        })()
      ''']).then((result) {
        // 将 base64 data URL 转换为 Uint8List
        final dataUrl = result.toString();
        final base64Data = dataUrl.split(',')[1];
        final bytes = _base64Decode(base64Data);
        completer.complete(bytes);
      }).catchError((error) {
        print('html2canvas error: \$error');
        completer.complete(null);
      });

      return completer.future;
    } catch (e) {
      print('ScreenshotService.captureElement error: \$e');
      return null;
    }
  }

  /// 捕获整个页面为图片
  static Future<Uint8List?> capturePage() async {
    return captureElement('body');
  }

  /// 将 base64 字符串解码为 Uint8List
  static Uint8List _base64Decode(String base64String) {
    // 处理 URL-safe base64
    String normalized = base64String
        .replaceAll('-', '+')
        .replaceAll('_', '/');
    
    // 添加填充
    while (normalized.length % 4 != 0) {
      normalized += '=';
    }

    // 手动解码 base64
    final List<int> bytes = [];
    final String base64Chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
    
    for (int i = 0; i < normalized.length; i += 4) {
      final c1 = base64Chars.indexOf(normalized[i]);
      final c2 = base64Chars.indexOf(normalized[i + 1]);
      final c3 = normalized[i + 2] == '=' ? -1 : base64Chars.indexOf(normalized[i + 2]);
      final c4 = normalized[i + 3] == '=' ? -1 : base64Chars.indexOf(normalized[i + 3]);

      bytes.add((c1 << 2) | (c2 >> 4));
      if (c3 != -1) {
        bytes.add(((c2 & 0x0F) << 4) | (c3 >> 2));
      }
      if (c4 != -1) {
        bytes.add(((c3 & 0x03) << 6) | c4);
      }
    }

    return Uint8List.fromList(bytes);
  }
}
