import 'dart:async';
import 'dart:js' as js;
import 'dart:typed_data';
import 'dart:convert';

/// 使用原生 Canvas API 截图服务 - 不依赖 html2canvas，iOS 兼容性好
class CanvasScreenshotService {
  
  /// 使用 Canvas API 绘制表格并导出图片
  static Future<Uint8List?> captureTable({
    required List<String> headers,
    required List<List<String>> rows,
    required List<ColorInfo> rowColors,
  }) async {
    try {
      final completer = Completer<Uint8List?>();
      
      // 创建回调
      js.context['__canvasScreenshotSuccess'] = js.allowInterop((String dataUrl) {
        try {
          final base64Data = dataUrl.split(',')[1];
          final bytes = base64Decode(base64Data);
          completer.complete(bytes);
        } catch (e) {
          print('Error decoding base64: $e');
          completer.complete(null);
        }
        _cleanupCallbacks();
      });
      
      js.context['__canvasScreenshotError'] = js.allowInterop((String error) {
        print('Canvas screenshot error: $error');
        completer.complete(null);
        _cleanupCallbacks();
      });

      // 构建颜色配置 JSON
      final colorsJson = rowColors.map((c) => {
        'index': c.index,
        'bgColor': c.bgColor,
        'textColor': c.textColor,
      }).toList();

      // 执行 Canvas 绘制脚本
      js.context.callMethod('eval', ['''
        (function() {
          try {
            const headers = ${js.context['JSON'].callMethod('stringify', [headers])};
            const rows = ${js.context['JSON'].callMethod('stringify', [rows])};
            const rowColors = ${js.context['JSON'].callMethod('stringify', [colorsJson])};
            
            // 创建 canvas
            const canvas = document.createElement('canvas');
            const ctx = canvas.getContext('2d');
            
            // 设置画布尺寸
            const cellWidth = 100;
            const cellHeight = 40;
            const headerHeight = 50;
            const padding = 10;
            
            canvas.width = headers.length * cellWidth + padding * 2;
            canvas.height = headerHeight + rows.length * cellHeight + padding * 2;
            
            // 白色背景
            ctx.fillStyle = '#ffffff';
            ctx.fillRect(0, 0, canvas.width, canvas.height);
            
            // 绘制标题
            ctx.fillStyle = '#333333';
            ctx.font = 'bold 16px Arial, sans-serif';
            ctx.textAlign = 'center';
            ctx.textBaseline = 'middle';
            
            // 绘制表头背景
            ctx.fillStyle = '#f5f5f5';
            ctx.fillRect(padding, padding, canvas.width - padding * 2, headerHeight);
            
            // 绘制表头文字
            ctx.fillStyle = '#333333';
            headers.forEach((header, i) => {
              const x = padding + i * cellWidth + cellWidth / 2;
              const y = padding + headerHeight / 2;
              ctx.fillText(header, x, y);
            });
            
            // 绘制数据行
            rows.forEach((row, rowIndex) => {
              const y = padding + headerHeight + rowIndex * cellHeight;
              
              // 查找该行的颜色配置
              const colorConfig = rowColors.find(c => c.index === rowIndex);
              
              row.forEach((cell, colIndex) => {
                const x = padding + colIndex * cellWidth;
                
                // 单元格背景
                if (colorConfig && colIndex > 0) { // 跳过第一列（教室名）
                  ctx.fillStyle = colorConfig.bgColor;
                } else {
                  ctx.fillStyle = '#ffffff';
                }
                ctx.fillRect(x, y, cellWidth, cellHeight);
                
                // 单元格边框
                ctx.strokeStyle = '#e0e0e0';
                ctx.lineWidth = 1;
                ctx.strokeRect(x, y, cellWidth, cellHeight);
                
                // 单元格文字
                if (colorConfig && colIndex > 0) {
                  ctx.fillStyle = colorConfig.textColor;
                } else {
                  ctx.fillStyle = '#333333';
                }
                ctx.font = '12px Arial, sans-serif';
                
                // 文字截断处理
                let text = cell;
                if (ctx.measureText(text).width > cellWidth - 8) {
                  while (ctx.measureText(text + '...').width > cellWidth - 8 && text.length > 0) {
                    text = text.slice(0, -1);
                  }
                  text += '...';
                }
                
                ctx.fillText(text, x + cellWidth / 2, y + cellHeight / 2);
              });
            });
            
            // 导出为 PNG
            const dataUrl = canvas.toDataURL('image/png');
            window.__canvasScreenshotSuccess(dataUrl);
          } catch (e) {
            window.__canvasScreenshotError('Canvas error: ' + e.message);
          }
        })()
      ''']);

      // 超时处理
      Future.delayed(Duration(seconds: 10), () {
        if (!completer.isCompleted) {
          print('Canvas screenshot timeout');
          completer.complete(null);
          _cleanupCallbacks();
        }
      });

      return completer.future;
    } catch (e, stackTrace) {
      print('CanvasScreenshotService error: $e');
      print(stackTrace);
      return null;
    }
  }
  
  static void _cleanupCallbacks() {
    js.context.deleteProperty('__canvasScreenshotSuccess');
    js.context.deleteProperty('__canvasScreenshotError');
  }
}

/// 颜色信息类
class ColorInfo {
  final int index;
  final String bgColor;
  final String textColor;
  
  ColorInfo({
    required this.index,
    required this.bgColor,
    required this.textColor,
  });
}
