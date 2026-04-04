import 'dart:async';
import 'dart:typed_data';
import 'dart:convert';
import 'dart:js' as js;

/// 总览页面 Excel 导出服务 - 使用 SheetJS 生成真正的 Excel 文件
class OverviewExcelService {
  
  /// 生成总览页面的 Excel 文件并下载
  static Future<bool> exportToExcel({
    required List<String> headers,
    required List<List<String>> rows,
    required List<ColorInfo> rowColors,
    required String fileName,
  }) async {
    try {
      final completer = Completer<bool>();
      
      // 创建回调
      js.context['__excelExportSuccess'] = js.allowInterop(() {
        completer.complete(true);
        _cleanupCallbacks();
      });
      
      js.context['__excelExportError'] = js.allowInterop((String error) {
        print('Excel export error: $error');
        completer.complete(false);
        _cleanupCallbacks();
      });

      // 构建颜色配置 JSON
      final colorsJson = rowColors.map((c) => {
        'index': c.index,
        'bgColor': c.bgColor,
      }).toList();

      // 执行 Excel 生成脚本
      js.context.callMethod('eval', ['''
        (function() {
          try {
            const headers = ${js.context['JSON'].callMethod('stringify', [headers])};
            const rows = ${js.context['JSON'].callMethod('stringify', [rows])};
            const rowColors = ${js.context['JSON'].callMethod('stringify', [colorsJson])};
            
            // 创建工作簿
            const wb = XLSX.utils.book_new();
            
            // 构建工作表数据
            const wsData = [headers];
            rows.forEach(row => wsData.push(row));
            
            // 创建工作表
            const ws = XLSX.utils.aoa_to_sheet(wsData);
            
            // 设置列宽
            const colWidths = headers.map(() => ({ wch: 15 }));
            ws['!cols'] = colWidths;
            
            // 设置行高
            const rowHeights = wsData.map(() => ({ hpt: 25 }));
            ws['!rows'] = rowHeights;
            
            // 应用样式（颜色）
            const range = XLSX.utils.decode_range(ws['!ref']);
            
            // 表头样式（第一行）
            for (let C = range.s.c; C <= range.e.c; ++C) {
              const cellRef = XLSX.utils.encode_cell({ r: 0, c: C });
              if (!ws[cellRef]) continue;
              ws[cellRef].s = {
                fill: { fgColor: { rgb: 'F5F5F5' } },
                font: { bold: true, sz: 11 },
                alignment: { horizontal: 'center', vertical: 'center' }
              };
            }
            
            // 数据行样式
            rowColors.forEach(colorInfo => {
              const rowIdx = colorInfo.index + 1; // +1 因为第一行是表头
              for (let C = 1; C <= range.e.c; ++C) { // 从第2列开始（跳过教室名）
                const cellRef = XLSX.utils.encode_cell({ r: rowIdx, c: C });
                if (!ws[cellRef]) continue;
                
                // 转换 hex 颜色为 Excel 格式（去掉 #）
                const bgColor = colorInfo.bgColor.replace('#', '');
                
                ws[cellRef].s = {
                  fill: { fgColor: { rgb: bgColor } },
                  font: { color: { rgb: 'FFFFFF' }, sz: 10 },
                  alignment: { horizontal: 'center', vertical: 'center', wrapText: true }
                };
              }
            });
            
            // 第一列（教室名）居中
            for (let R = 1; R <= range.e.r; ++R) {
              const cellRef = XLSX.utils.encode_cell({ r: R, c: 0 });
              if (!ws[cellRef]) continue;
              if (!ws[cellRef].s) ws[cellRef].s = {};
              ws[cellRef].s.alignment = { horizontal: 'center', vertical: 'center' };
            }
            
            // 将工作表添加到工作簿
            XLSX.utils.book_append_sheet(wb, ws, '今日总览');
            
            // 生成文件并下载
            const wbout = XLSX.write(wb, { bookType: 'xlsx', type: 'array' });
            const blob = new Blob([wbout], { type: 'application/octet-stream' });
            
            // 创建下载链接
            const url = URL.createObjectURL(blob);
            const a = document.createElement('a');
            a.href = url;
            a.download = '$fileName.xlsx';
            document.body.appendChild(a);
            a.click();
            document.body.removeChild(a);
            URL.revokeObjectURL(url);
            
            window.__excelExportSuccess();
          } catch (e) {
            window.__excelExportError('Excel generation error: ' + e.message);
          }
        })()
      ''']);

      // 超时处理
      Future.delayed(Duration(seconds: 15), () {
        if (!completer.isCompleted) {
          print('Excel export timeout');
          completer.complete(false);
          _cleanupCallbacks();
        }
      });

      return completer.future;
    } catch (e, stackTrace) {
      print('OverviewExcelService error: $e');
      print(stackTrace);
      return false;
    }
  }
  
  static void _cleanupCallbacks() {
    js.context.deleteProperty('__excelExportSuccess');
    js.context.deleteProperty('__excelExportError');
  }
}

/// 颜色信息类
class ColorInfo {
  final int index;
  final String bgColor;
  
  ColorInfo({
    required this.index,
    required this.bgColor,
  });
}
