import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:provider/provider.dart';
import '../models/course.dart';
import '../models/reminder.dart';
import '../providers/app_provider.dart';
import '../services/excel_parser_service.dart';
import '../services/web_download_service.dart';
import '../services/screenshot_service.dart';
import 'course_display_screen.dart';
// Web 平台特定的导入
import 'package:flutter/foundation.dart';

// 条件导入：仅在 Web 平台导入 dart:js
import '../utils/conditional_import.dart';

/// 总览页面 - 显示所有教室1-12节详细情况
class OverviewScreen extends StatefulWidget {
  const OverviewScreen({super.key});

  @override
  State<OverviewScreen> createState() => _OverviewScreenState();
}

class _OverviewScreenState extends State<OverviewScreen> {
  /// 是否已经初始化默认分页
  bool _hasInitializedDefaultPage = false;
  
  /// GlobalKey for capturing the overview widget
  final GlobalKey _screenshotKey = GlobalKey();



  /// 获取按数字排序后的教室列表
  List<Classroom> _getSortedClassrooms(List<Classroom> classrooms) {
    return List<Classroom>.from(classrooms)..sort((a, b) {
      final aNumStr = a.name.replaceAll(RegExp(r'[^0-9]'), '');
      final bNumStr = b.name.replaceAll(RegExp(r'[^0-9]'), '');
      final aNum = int.tryParse(aNumStr) ?? 0;
      final bNum = int.tryParse(bNumStr) ?? 0;
      return aNum.compareTo(bNum);
    });
  }

  /// 根据分页配置过滤教室
  /// 只返回有实际教室数据的分页
  List<MapEntry<String, List<Classroom>>> _getFilteredPages(List<Classroom> allClassrooms, AppProvider provider) {
    final sortedClassrooms = _getSortedClassrooms(allClassrooms);
    final pages = <MapEntry<String, List<Classroom>>>[];

    for (final entry in AppProvider.pageConfigs.entries) {
      final pageName = entry.key;
      final allowedNumbers = entry.value;
      
      // 过滤出该分页中的教室
      final pageClassrooms = sortedClassrooms.where((c) {
        final numStr = c.name.replaceAll(RegExp(r'[^0-9]'), '');
        final num = int.tryParse(numStr) ?? 0;
        return allowedNumbers.contains(num);
      }).toList();

      // 只添加有教室的分页
      if (pageClassrooms.isNotEmpty) {
        pages.add(MapEntry(pageName, pageClassrooms));
      }
    }

    return pages;
  }

  /// 时间段颜色配置 - 每个节次位置使用固定颜色
  /// 同一连续课程使用该课程第一个节次位置对应的颜色
  static final Map<String, List<Color>> _timeBlockColorSets = {
    'morning': [    // 1-4节 上午 - 每个位置固定颜色
      Color(0xFF1565C0),  // 位置1 - 深蓝
      Color(0xFF00897B),  // 位置2 - 深青绿
      Color(0xFF6A1B9A),  // 位置3 - 深紫
      Color(0xFF0277BD),  // 位置4 - 深天蓝
    ],
    'afternoon': [  // 6-9节 下午 - 每个位置固定颜色
      Color(0xFFD84315),  // 位置6 - 深橙红
      Color(0xFFEF6C00),  // 位置7 - 深橙
      Color(0xFFF9A825),  // 位置8 - 深黄
      Color(0xFFC62828),  // 位置9 - 深红
    ],
    'evening': [    // 10-12节 晚上 - 每个位置固定颜色
      Color(0xFF6A1B9A),  // 位置10 - 深紫
      Color(0xFFAD1457),  // 位置11 - 深粉红
      Color(0xFF4527A0),  // 位置12 - 深深紫
    ],
  };

  /// 第5节专用颜色
  static const Color _period5Color = Color(0xFF2E7D32);  // 深绿色

  /// 当前上课节次的特殊颜色 - 使用更醒目的红色
  static const Color _currentPeriodColor = Color(0xFFD32F2F);

  /// 获取节次所属的时间段
  String _getTimeBlock(int period) {
    if (period >= 1 && period <= 4) return 'morning';
    if (period >= 6 && period <= 9) return 'afternoon';
    if (period >= 10 && period <= 12) return 'evening';
    return 'other'; // 第5节单独处理
  }

  /// 获取节次在时间段内的索引（0-based）
  int _getPeriodIndexInTimeBlock(int period) {
    if (period >= 1 && period <= 4) return period - 1;
    if (period >= 6 && period <= 9) return period - 6;
    if (period >= 10 && period <= 12) return period - 10;
    return 0; // 第5节返回0，但第5节独立时会使用专用颜色，不会走到这里
  }

  /// 获取节次对应的固定颜色（用于第5节与前后节合并时）
  Color _getPeriodColor(int period) {
    if (period >= 1 && period <= 4) {
      return _timeBlockColorSets['morning']![period - 1];
    }
    if (period >= 6 && period <= 9) {
      return _timeBlockColorSets['afternoon']![period - 6];
    }
    if (period >= 10 && period <= 12) {
      return _timeBlockColorSets['evening']![period - 10];
    }
    return _period5Color; // 第5节独立时的颜色
  }

  /// 分析教室的课程连续块
  /// 返回 Map<节次, 课程块ID>，同一连续课程的节次有相同的块ID
  /// 特殊处理第5节：如果和第4节或第6节是同一老师，合并到相邻的课程块
  /// 返回的Map中，独立的第5节会用特殊的值标记
  Map<int, String> _analyzeCourseBlocks(Classroom classroom, String weekday) {
    final blocks = <int, String>{};
    String? currentBlockId;
    String? lastCourseName;

    // 第一次遍历：初步分析课程块
    for (int period = 1; period <= 12; period++) {
      final course = classroom.getCourseAtPeriod(weekday, period);
      
      if (course != null) {
        // 如果课程名变化，开始新块
        if (course.name != lastCourseName) {
          currentBlockId = '${classroom.name}_${period}_${course.name}';
          lastCourseName = course.name;
        }
        blocks[period] = currentBlockId!;
      } else {
        currentBlockId = null;
        lastCourseName = null;
      }
    }

    // 第二次遍历：处理第5节的特殊情况
    final period5Course = classroom.getCourseAtPeriod(weekday, 5);
    if (period5Course != null) {
      final period4Course = classroom.getCourseAtPeriod(weekday, 4);
      final period6Course = classroom.getCourseAtPeriod(weekday, 6);
      
      // 如果第5节和第6节是同一老师，合并到后面的课程块
      if (period6Course != null && period6Course.name == period5Course.name) {
        // 找到第6节所属的课程块ID
        final block6Id = blocks[6];
        if (block6Id != null) {
          // 使用特殊标记，记录合并到第6节块
          blocks[5] = 'MERGED_TO_6_${block6Id}';
        }
      }
      // 否则如果第5节和第4节是同一老师，合并到前面的课程块
      else if (period4Course != null && period4Course.name == period5Course.name) {
        final block4Id = blocks[4];
        if (block4Id != null) {
          // 使用特殊标记，记录合并到第4节块
          blocks[5] = 'MERGED_TO_4_${block4Id}';
        }
      }
      // 否则第5节是独立的，使用特殊标记
      else {
        blocks[5] = 'PERIOD5_INDEPENDENT_${classroom.name}_${period5Course.name}';
      }
    }

    return blocks;
  }

  /// 获取课程块的起始节次
  /// 通过查找blocks中所有具有相同blockId的节次，返回最小的一个
  int _getFirstPeriodOfBlock(Map<int, String> blocks, String blockId) {
    // 如果是独立的第5节特殊标记，返回5
    if (blockId.startsWith('PERIOD5_INDEPENDENT_')) {
      return 5;
    }
    // 如果是合并到第6节的标记，返回6
    if (blockId.startsWith('MERGED_TO_6_')) {
      return 6;
    }
    // 如果是合并到第4节的标记，返回4
    if (blockId.startsWith('MERGED_TO_4_')) {
      return 4;
    }
    // 遍历所有节次，找到属于该课程块的最小节次
    int? firstPeriod;
    for (int period = 1; period <= 12; period++) {
      if (blocks[period] == blockId) {
        if (firstPeriod == null || period < firstPeriod) {
          firstPeriod = period;
        }
      }
    }
    return firstPeriod ?? 1;
  }

  /// 检查第5节是否是独立的（没有和前后节合并）
  bool _isPeriod5Independent(String blockId) {
    return blockId.startsWith('PERIOD5_INDEPENDENT_');
  }

  /// 获取课程块的实际ID（去除合并标记前缀）
  String _getActualBlockId(String blockId) {
    if (blockId.startsWith('MERGED_TO_6_')) {
      return blockId.substring('MERGED_TO_6_'.length);
    }
    if (blockId.startsWith('MERGED_TO_4_')) {
      return blockId.substring('MERGED_TO_4_'.length);
    }
    return blockId;
  }

  /// 构建节次色块列表
  List<Widget> _buildPeriodCells(
    BuildContext context,
    Classroom classroom,
    String weekday,
    DateTime now,
    Map<int, Set<String>> absentMap,
    AppProvider provider,
  ) {
    final allPeriods = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12];
    final courseBlocks = _analyzeCourseBlocks(classroom, weekday);
    final currentPeriod = ExcelParserService.getCurrentPeriod(now);
    
    // 为每个课程块分配颜色
    final blockColors = <String, Color>{};
    final colorIndices = <String, int>{
      'morning': 0,
      'afternoon': 0,
      'evening': 0,
    };

    return allPeriods.map((period) {
      final hasCourse = classroom.hasCourseInPeriods(weekday, [period]);
      final reminderId = getReminderIdForPeriod(period);
      final isDirectAbsent = hasCourse && reminderId != null &&
          absentMap[reminderId]?.contains(classroom.name) == true;
      final isContinuousAbsent = hasCourse && _isPeriodAbsent(
        period,
        classroom.name,
        weekday,
        absentMap,
        provider,
      );
      final isAbsent = isDirectAbsent || isContinuousAbsent;

      Color cellColor;
      bool showAbsentLabel = false;
      
      if (hasCourse) {
        final rawBlockId = courseBlocks[period];
        // 获取实际的blockId（去除合并标记前缀）
        final blockId = rawBlockId != null ? _getActualBlockId(rawBlockId) : null;
        // 获取课程块的起始节次
        final firstPeriodOfBlock = rawBlockId != null 
            ? _getFirstPeriodOfBlock(courseBlocks, rawBlockId) 
            : period;
        
        // 第5节如果是独立的一节课，才使用专用深绿色
        // 如果第5节属于连续课程块（和前后节是同一老师），使用课程块的颜色
        if (period == 5 && rawBlockId != null && _isPeriod5Independent(rawBlockId)) {
          cellColor = _period5Color;
        } else if (blockId != null) {
          // 为课程块分配颜色：使用课程块第一个节次位置对应的固定颜色
          // 这样任意连续课程块都会用起始节的颜色
          if (!blockColors.containsKey(blockId)) {
            blockColors[blockId] = _getPeriodColor(firstPeriodOfBlock);
          }
          cellColor = blockColors[blockId]!;
        } else {
          // 其他特殊情况使用灰色
          cellColor = Colors.grey.shade400;
        }
        // 缺勤时在对应色块显示"缺"字，但不改变颜色
        if (isAbsent) {
          showAbsentLabel = true;
        }
      } else {
        cellColor = Colors.grey.shade300;
      }

      // 根据背景颜色亮度决定"缺"字颜色
      final absentTextColor = cellColor.computeLuminance() > 0.35
          ? Colors.black
          : Colors.white;

      return Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 1),
          child: Container(
            height: 24,
            decoration: BoxDecoration(
              color: cellColor,
              borderRadius: BorderRadius.circular(3),
            ),
            child: showAbsentLabel
                ? Center(
                    child: Text(
                      '缺',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: absentTextColor,
                      ),
                    ),
                  )
                : null,
          ),
        ),
      );
    }).toList();
  }

  /// 节次对应的缺勤确认提醒ID
  static int? getReminderIdForPeriod(int period) {
    for (final config in FixedReminderConfig.all) {
      if (config.isAttendanceCheck && config.periods != null) {
        if (config.periods!.contains(period)) {
          return config.id;
        }
      }
    }
    return null;
  }

  /// 检查指定教室在指定节次是否应标记为缺勤
  bool _isPeriodAbsent(
    int period,
    String classroomName,
    String weekday,
    Map<int, Set<String>> absentMap,
    AppProvider provider,
  ) {
    final classroom = provider.classrooms.firstWhere(
      (c) => c.name == classroomName,
      orElse: () => provider.classrooms.first,
    );
    
    final currentCourse = classroom.getCourseAtPeriod(weekday, period);
    if (currentCourse == null) return false;

    for (final config in FixedReminderConfig.all) {
      if (!config.isAttendanceCheck || config.periods == null) continue;

      final absentClassrooms = absentMap[config.id] ?? {};
      if (!absentClassrooms.contains(classroomName)) continue;

      for (final absentPeriod in config.periods!) {
        if (classroom.getCourseAtPeriod(weekday, absentPeriod) != null) {
          final absentCourse = classroom.getCourseAtPeriod(weekday, absentPeriod);
          if (absentCourse != null && absentCourse.name == currentCourse.name) {
            return true;
          }
        }
      }
    }
    return false;
  }

  /// 下载总览页面为 Excel 文件（最可靠的跨平台方案）
  /// 使用 JavaScript Canvas 直接绘制表格截图（绕过 Flutter 渲染层）
  Future<void> _downloadOverviewImage() async {
    try {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('正在生成截图...'), duration: Duration(seconds: 2)),
        );
      }
      
      // 获取数据
      final provider = context.read<AppProvider>();
      final allClassrooms = provider.classrooms;
      
      if (allClassrooms.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('没有课表数据')),
          );
        }
        return;
      }
      
      final pages = _getFilteredPages(allClassrooms, provider);
      final selectedPages = provider.selectedOverviewPages;
      final now = DateTime.now();
      final weekday = ExcelParserService.getWeekdayName(now);
      
      // 合并选中的教室
      final Set<Classroom> uniqueClassrooms = {};
      for (final pageName in selectedPages) {
        final pageEntry = pages.firstWhere(
          (p) => p.key == pageName,
          orElse: () => MapEntry(pageName, []),
        );
        uniqueClassrooms.addAll(pageEntry.value);
      }
      
      final sortedClassrooms = _getSortedClassrooms(uniqueClassrooms.toList());
      final absentMap = provider.absentClassrooms;
      
      // 构建表头
      final headers = ['教室', '1-2', '3-4', '5', '6-7', '8-9', '10-12'];
      
      // 构建数据行
      final rows = <List<String>>[];
      final rowColors = <Map<String, dynamic>>[];
      
      for (final classroom in sortedClassrooms) {
        final row = <String>[];
        
        for (final periodGroup in [1, 2, 3, 4, 5, 6, 7]) {
          if (periodGroup == 1) {
            row.add(classroom.name);
          } else {
            final periods = _getPeriodsForGroup(periodGroup);
            final courses = <String>[];
            final teacherSet = <String>{};
            
            for (final period in periods) {
              final course = classroom.getCourseAtPeriod(weekday, period);
              if (course != null) {
                courses.add(course.name);
                if (course.teacher != null && course.teacher!.isNotEmpty) {
                  teacherSet.add(course.teacher!);
                }
              }
            }
            
            if (courses.isEmpty) {
              row.add('');
            } else {
              final uniqueCourses = courses.toSet().toList();
              final displayText = uniqueCourses.length > 1
                  ? uniqueCourses.take(2).join('\n')
                  : uniqueCourses.first;
              row.add(displayText);
            }
          }
        }
        
        rows.add(row);
        
        // 检查是否有缺勤标记
        final hasAbsence = absentMap.entries.any((entry) {
          final parts = entry.key.toString().split('_');
          if (parts.length >= 2) {
            final absenceWeekday = parts[0];
            final absenceClassroom = parts.sublist(1).join('_');
            return absenceWeekday == weekday &&
                   absenceClassroom == classroom.name &&
                   (entry.value as List).isNotEmpty;
          }
          return false;
        });
        
        rowColors.add({
          'classroomName': classroom.name,
          'hasAbsence': hasAbsence,
        });
      }
      
      // 调用 JavaScript 绘制截图
      final success = await _captureWithJS(headers, rows, rowColors, weekday);
      
      if (success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('截图已下载')),
        );
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('截图失败，请重试')),
        );
      }
    } catch (e) {
      debugPrint('Download error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('下载失败: $e')),
        );
      }
    }
  }
  
  /// 获取节次组对应的节次列表
  List<int> _getPeriodsForGroup(int group) {
    switch (group) {
      case 2: return [1, 2];
      case 3: return [3, 4];
      case 4: return [5];
      case 5: return [6, 7];
      case 6: return [8, 9];
      case 7: return [10, 11, 12];
      default: return [];
    }
  }
  
  /// 使用 JavaScript Canvas 绘制并下载截图（仅 Web 平台）
  Future<bool> _captureWithJS(
    List<String> headers,
    List<List<String>> rows,
    List<Map<String, dynamic>> rowColors,
    String weekday,
  ) async {
    // 仅 Web 平台支持
    if (!kIsWeb) {
      debugPrint('_captureWithJS is only supported on Web platform');
      return false;
    }
    
    try {
      final completer = Completer<bool>();
      
      // 准备颜色配置
      final colorsJson = rowColors.map((c) {
        return {
          'name': c['classroomName'],
          'hasAbsence': c['hasAbsence'],
        };
      }).toList();
      
      // JavaScript 回调
      js.context['__screenshotSuccess'] = js.allowInterop((String dataUrl) {
        completer.complete(true);
        js.context.deleteProperty('__screenshotSuccess');
        js.context.deleteProperty('__screenshotError');
      });
      
      js.context['__screenshotError'] = js.allowInterop((String error) {
        debugPrint('Screenshot JS error: $error');
        completer.complete(false);
        js.context.deleteProperty('__screenshotSuccess');
        js.context.deleteProperty('__screenshotError');
      });
      
      // 执行 Canvas 绘制
      js.context.callMethod('eval', ['''
        (function() {
          try {
            const headers = ${js.context['JSON'].callMethod('stringify', [headers])};
            const rows = ${js.context['JSON'].callMethod('stringify', [rows])};
            const colorsJson = ${js.context['JSON'].callMethod('stringify', [colorsJson])};
            
            // 尺寸配置
            const classroomColWidth = 80;
            const periodColWidth = 120;
            const headerHeight = 50;
            const rowHeight = 36;
            const padding = 20;
            const cornerRadius = 4;
            
            const canvasWidth = classroomColWidth + periodColWidth * 5 + padding * 2;
            const canvasHeight = headerHeight + rows.length * rowHeight + padding * 2 + 60;
            
            const canvas = document.createElement('canvas');
            canvas.width = canvasWidth;
            canvas.height = canvasHeight;
            const ctx = canvas.getContext('2d');
            
            // 白色背景
            ctx.fillStyle = '#ffffff';
            ctx.fillRect(0, 0, canvas.width, canvas.height);
            
            // 标题
            ctx.fillStyle = '#1a1a1a';
            ctx.font = 'bold 20px Arial, sans-serif';
            ctx.textAlign = 'center';
            ctx.fillText('${weekday}总览', canvasWidth / 2, padding + 25);
            
            let y = padding + 50;
            
            // 表头背景
            ctx.fillStyle = '#e8e8e8';
            ctx.beginPath();
            ctx.roundRect(padding, y, canvasWidth - padding * 2, headerHeight, [cornerRadius, cornerRadius, 0, 0]);
            ctx.fill();
            
            // 表头文字
            ctx.fillStyle = '#333333';
            ctx.font = 'bold 14px Arial, sans-serif';
            ctx.textAlign = 'center';
            
            let x = padding;
            const colWidths = [classroomColWidth, periodColWidth, periodColWidth, periodColWidth, periodColWidth, periodColWidth];
            
            headers.forEach((header, i) => {
              const colWidth = colWidths[Math.min(i, colWidths.length - 1)];
              ctx.fillText(header, x + colWidth / 2, y + headerHeight / 2 + 5);
              x += colWidth;
            });
            
            y += headerHeight;
            
            // 数据行
            rows.forEach((row, rowIndex) => {
              const colorInfo = colorsJson[rowIndex];
              const hasAbsence = colorInfo && colorInfo.hasAbsence;
              
              // 行背景（交替色）
              ctx.fillStyle = rowIndex % 2 === 0 ? '#fafafa' : '#ffffff';
              ctx.fillRect(padding, y, canvasWidth - padding * 2, rowHeight);
              
              // 缺勤标记行特殊背景
              if (hasAbsence) {
                ctx.fillStyle = 'rgba(255, 0, 0, 0.15)';
                ctx.fillRect(padding, y, canvasWidth - padding * 2, rowHeight);
              }
              
              x = padding;
              
              row.forEach((cell, colIndex) => {
                const colWidth = colWidths[Math.min(colIndex, colWidths.length - 1)];
                
                // 单元格边框
                ctx.strokeStyle = '#e0e0e0';
                ctx.lineWidth = 0.5;
                ctx.beginPath();
                ctx.moveTo(x, y);
                ctx.lineTo(x, y + rowHeight);
                ctx.stroke();
                
                // 单元格文字
                if (cell && cell.length > 0) {
                  ctx.fillStyle = colIndex === 0 ? '#333333' : '#1a1a1a';
                  ctx.font = colIndex === 0 ? 'bold 12px Arial, sans-serif' : '12px Arial, sans-serif';
                  ctx.textAlign = 'center';
                  
                  // 处理多行文本
                  const lines = cell.split('\\n');
                  const lineHeight = 14;
                  const startY = y + rowHeight / 2 - (lines.length - 1) * lineHeight / 2;
                  
                  lines.forEach((line, lineIndex) => {
                    // 文字截断
                    let displayText = line;
                    const maxWidth = colWidth - 10;
                    if (ctx.measureText(displayText).width > maxWidth) {
                      while (ctx.measureText(displayText + '..').width > maxWidth && displayText.length > 0) {
                        displayText = displayText.slice(0, -1);
                      }
                      displayText += '..';
                    }
                    ctx.fillText(displayText, x + colWidth / 2, startY + lineIndex * lineHeight + 4);
                  });
                }
                
                x += colWidth;
              });
              
              // 右侧边框
              ctx.strokeStyle = '#e0e0e0';
              ctx.lineWidth = 0.5;
              ctx.beginPath();
              ctx.moveTo(x, y);
              ctx.lineTo(x, y + rowHeight);
              ctx.stroke();
              
              // 底部边框
              ctx.beginPath();
              ctx.moveTo(padding, y + rowHeight);
              ctx.lineTo(padding + classroomColWidth + periodColWidth * 5, y + rowHeight);
              ctx.stroke();
              
              y += rowHeight;
            });
            
            // 底部边框
            ctx.strokeStyle = '#cccccc';
            ctx.lineWidth = 1;
            ctx.beginPath();
            ctx.moveTo(padding, y);
            ctx.lineTo(padding + classroomColWidth + periodColWidth * 5, y);
            ctx.stroke();
            
            // 下载图片
            const dataUrl = canvas.toDataURL('image/png');
            const link = document.createElement('a');
            const timestamp = Date.now();
            link.download = '总览_' + timestamp + '.png';
            link.href = dataUrl;
            link.click();
            
            window.__screenshotSuccess(dataUrl);
          } catch (e) {
            window.__screenshotError(e.message || e.toString());
          }
        })()
      ''']);
      
      // 超时处理
      Future.delayed(const Duration(seconds: 15), () {
        if (!completer.isCompleted) {
          completer.complete(false);
          js.context.deleteProperty('__screenshotSuccess');
          js.context.deleteProperty('__screenshotError');
        }
      });
      
      return completer.future;
    } catch (e) {
      debugPrint('_captureWithJS error: $e');
      return false;
    }
  }
  
  /// 检测是否为 iOS Safari
  bool _isIOSSafari() {
    try {
      final userAgent = js.context['navigator']['userAgent'].toString().toLowerCase();
      final vendor = js.context['navigator']['vendor']?.toString().toLowerCase() ?? '';
      
      // 检测 iOS 设备（iPhone 或 iPad）
      final isIOS = userAgent.contains('iphone') || userAgent.contains('ipad') || userAgent.contains('ipod');
      // 检测 Safari（不是 Chrome 或其他浏览器）
      final isSafari = vendor.contains('apple') && !userAgent.contains('crios') && !userAgent.contains('fxios');
      
      return isIOS || isSafari;
    } catch (e) {
      return false;
    }
  }
  
  /// 获取节次对应的颜色 Hex
  String _getColorHexForPeriod(int period) {
    final color = _getPeriodColor(period);
    return '#${color.value.toRadixString(16).substring(2).toUpperCase()}';
  }
  
  /// 使用 RepaintBoundary 捕获 Widget 为 PNG 图片
  Future<Uint8List?> _captureWidgetToImage() async {
    try {
      // 查找 RenderRepaintBoundary
      final RenderRepaintBoundary? boundary = 
          _screenshotKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      
      if (boundary == null) {
        debugPrint('RenderRepaintBoundary not found - key: $_screenshotKey, context: ${_screenshotKey.currentContext}');
        return null;
      }
      
      // 确保渲染完成
      if (!boundary.hasSize || boundary.size.isEmpty) {
        debugPrint('Boundary has no size or is empty');
        return null;
      }
      
      debugPrint('Capturing image with size: ${boundary.size}');
      
      // 捕获为图片
      final ui.Image image = await boundary.toImage(pixelRatio: 2.0);
      
      // 转换为 PNG 字节
      final ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      
      if (byteData == null) {
        debugPrint('Failed to convert image to byte data');
        return null;
      }
      
      debugPrint('Image captured successfully, size: ${byteData.lengthInBytes} bytes');
      return byteData.buffer.asUint8List();
    } catch (e, stackTrace) {
      debugPrint('Error capturing widget: $e');
      debugPrint('Stack trace: $stackTrace');
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('今日总览'),
        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
        actions: [
          IconButton(
            icon: const Icon(Icons.download),
            tooltip: '下载为图片',
            onPressed: _downloadOverviewImage,
          ),
        ],
      ),
      body: Consumer<AppProvider>(
        builder: (context, provider, _) {
          final now = DateTime.now();
          final weekday = ExcelParserService.getWeekdayName(now);
          final allPeriods = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12];
          final absentMap = provider.absentClassrooms;

          if (provider.classrooms.isEmpty) {
            return const Center(child: Text('暂无教室数据，请先在提醒页面导入课表'));
          }

          // 获取过滤后的分页
          final pages = _getFilteredPages(provider.classrooms, provider);
          
          if (pages.isEmpty) {
            return const Center(child: Text('暂无匹配的教室数据'));
          }

          // 初始化分页选择（仅在首次加载时，确保有默认值）
          if (!_hasInitializedDefaultPage) {
            // 如果 Provider 中没有选中任何分页，设置默认值
            if (provider.selectedOverviewPages.isEmpty) {
              provider.toggleOverviewPage('2楼大');
            }
            _hasInitializedDefaultPage = true;
          }

          // 获取所有选中分页中的教室（合并并按编号排序）
          final selectedPages = provider.selectedOverviewPages;
          final allSelectedClassrooms = <Classroom>[];
          for (final page in pages) {
            if (selectedPages.contains(page.key)) {
              allSelectedClassrooms.addAll(page.value);
            }
          }
          // 去重并按编号排序
          final seen = <String>{};
          final currentPageClassrooms = allSelectedClassrooms
              .where((c) => seen.add(c.name))
              .toList();

          return Column(
            children: [
              // 分页选择器（不在截图范围内）
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: Column(
                  children: [
                    // 星期和图例
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          weekday,
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(width: 8),
                        _LegendItem(color: Color(0xFF1565C0), label: '1-4节'),
                        const SizedBox(width: 6),
                        _LegendItem(color: Color(0xFF2E7D32), label: '第5节'),
                        const SizedBox(width: 6),
                        _LegendItem(color: Color(0xFFD84315), label: '6-9节'),
                        const SizedBox(width: 6),
                        _LegendItem(color: Color(0xFF6A1B9A), label: '10-12节'),
                        const SizedBox(width: 6),
                        _LegendItem(color: Colors.grey.shade300, label: '无课'),
                      ],
                    ),
                    const SizedBox(height: 8),
                    // 分页标签（多选）
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: pages.asMap().entries.map((entry) {
                          final pageName = entry.value.key;
                          final isSelected = provider.isOverviewPageSelected(pageName);
                          
                          return Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: FilterChip(
                              label: Text(pageName),
                              selected: isSelected,
                              onSelected: (_) {
                                provider.toggleOverviewPage(pageName);
                              },
                              selectedColor: Theme.of(context).colorScheme.primaryContainer,
                              backgroundColor: Colors.grey.shade200,
                              checkmarkColor: Theme.of(context).colorScheme.primary,
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ],
                ),
              ),
              // 截图区域：包含节次标题和教室列表
              Expanded(
                child: RepaintBoundary(
                  key: _screenshotKey,
                  child: Column(
                    children: [
                      // 节次标题行（显示当前上课节次）
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        color: Colors.grey.shade100,
                        child: Row(
                          children: [
                            const SizedBox(width: 52),
                            ...List.generate(12, (i) {
                              final period = i + 1;
                              final isCurrentPeriod = period == ExcelParserService.getCurrentPeriod(now);
                              return Expanded(
                                child: Center(
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                    decoration: isCurrentPeriod
                                        ? BoxDecoration(
                                            color: _currentPeriodColor,
                                            borderRadius: BorderRadius.circular(4),
                                          )
                                        : null,
                                    child: Text(
                                      '$period',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: isCurrentPeriod ? FontWeight.bold : FontWeight.normal,
                                        color: isCurrentPeriod ? Colors.white : Colors.grey.shade700,
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            }),
                          ],
                        ),
                      ),
                      // 当前分页的教室列表
                      Expanded(
                        child: ListView.builder(
                          itemCount: currentPageClassrooms.length,
                          itemBuilder: (context, index) {
                            final classroom = currentPageClassrooms[index];
                            final classroomNumber = classroom.name.replaceAll(RegExp(r'[^0-9]'), '');

                            return Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                border: Border(
                                  bottom: BorderSide(color: Colors.grey.shade200),
                                ),
                              ),
                              child: Row(
                                children: [
                                  GestureDetector(
                                    onTap: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => CourseDisplayScreen(classroom: classroom),
                                        ),
                                      );
                                    },
                                    child: SizedBox(
                                      width: 52,
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            classroomNumber,
                                            style: TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.bold,
                                              color: Theme.of(context).colorScheme.primary,
                                              decoration: TextDecoration.underline,
                                              decorationColor: Theme.of(context).colorScheme.primary,
                                            ),
                                            textAlign: TextAlign.center,
                                          ),
                                          if (classroom.capacity != null)
                                            Text(
                                              '${classroom.capacity}',
                                              style: TextStyle(
                                                fontSize: 10,
                                                color: Colors.grey.shade500,
                                              ),
                                              textAlign: TextAlign.center,
                                            ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  ..._buildPeriodCells(
                                    context,
                                    classroom,
                                    weekday,
                                    now,
                                    absentMap,
                                    provider,
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// 图例项
class _LegendItem extends StatelessWidget {
  final Color color;
  final String label;

  const _LegendItem({
    required this.color,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey.shade700,
          ),
        ),
      ],
    );
  }
}
