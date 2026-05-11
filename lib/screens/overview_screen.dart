import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models/course.dart';
import '../models/reminder.dart';
import '../providers/app_provider.dart';
import '../services/excel_parser_service.dart';
import 'course_display_screen.dart';



/// 总览页面 - 显示所有教室1-12节详细情况
class OverviewScreen extends StatefulWidget {
  const OverviewScreen({super.key});

  @override
  State<OverviewScreen> createState() => _OverviewScreenState();
}

class _OverviewScreenState extends State<OverviewScreen> {
  /// 是否已经初始化默认分页
  bool _hasInitializedDefaultPage = false;

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  /// GlobalKey for capturing the overview widget
  final GlobalKey _screenshotKey = GlobalKey();

  /// 当前显示的日期（默认为今天，但可以通过前一天/后一天切换）
  DateTime _selectedDate = DateTime.now();

  /// 是否显示搜索框
  bool _showSearchBox = false;

  /// 搜索控制器
  final TextEditingController _searchController = TextEditingController();

  /// 搜索焦点节点
  final FocusNode _searchFocusNode = FocusNode();

  /// 搜索结果列表
  List<_SearchResult> _searchResults = [];



  /// 切换到前一天
  void _goToPreviousDay() {
    setState(() {
      _selectedDate = _selectedDate.subtract(const Duration(days: 1));
      _searchResults = [];
    });
  }

  /// 切换到后一天
  void _goToNextDay() {
    setState(() {
      _selectedDate = _selectedDate.add(const Duration(days: 1));
      _searchResults = [];
    });
  }

  /// 执行搜索
  void _performSearch(String query) {
    if (query.isEmpty) {
      setState(() {
        _searchResults = [];
      });
      return;
    }

    final results = <_SearchResult>[];
    final lowerQuery = query.toLowerCase();
    final provider = context.read<AppProvider>();
    final weekday = ExcelParserService.getWeekdayName(_selectedDate);

    // 遍历所有教室和节次进行搜索
    for (final classroom in provider.classrooms) {
      for (int period = 1; period <= 12; period++) {
        final course = classroom.getCourseAtPeriod(weekday, period);
        if (course != null) {
          // 搜索课程名
          if (course.name.toLowerCase().contains(lowerQuery)) {
            results.add(_SearchResult(
              classroom: classroom,
              period: period,
              course: course,
              matchType: 'course',
            ));
          }
          // 搜索老师名
          else if (course.teacher != null && course.teacher!.toLowerCase().contains(lowerQuery)) {
            results.add(_SearchResult(
              classroom: classroom,
              period: period,
              course: course,
              matchType: 'teacher',
            ));
          }
        }
      }
    }

    setState(() {
      _searchResults = results;
    });
  }

  /// 切换课程类型筛选（使用 Provider）
  void _toggleCourseType(String type, AppProvider provider) {
    provider.toggleOverviewCourseType(type);
  }

  /// 判断课程是否匹配当前筛选条件
  bool _matchesCourseTypeFilter(Course course, AppProvider provider) {
    final selectedCourseTypes = provider.overviewCourseTypes;
    if (selectedCourseTypes.isEmpty) return true;

    final rawText = course.rawText ?? course.name;
    final isGraduate = rawText.startsWith('(研)') || rawText.startsWith('◇');
    final isBorrowed = rawText.startsWith('借用');
    final isUndergraduate = !isBorrowed && !isGraduate;

    if (selectedCourseTypes.contains('graduate') && isGraduate) return true;
    if (selectedCourseTypes.contains('undergraduate') && isUndergraduate) return true;
    if (selectedCourseTypes.contains('borrowed') && isBorrowed) return true;

    return false;
  }

  /// 显示教室筛选对话框
  void _showClassroomFilterDialog(List<Classroom> allClassrooms, AppProvider provider) {
    final tempSelected = Set<String>.from(provider.overviewSelectedClassrooms);
    if (tempSelected.isEmpty) {
      for (final c in allClassrooms) {
        tempSelected.add(c.name);
      }
    }

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final sortedClassrooms = _getSortedClassrooms(allClassrooms);

            return AlertDialog(
              title: Row(
                children: [
                  const Text('筛选教室'),
                  const Spacer(),
                  TextButton(
                    onPressed: () {
                      setDialogState(() {
                        tempSelected.clear();
                        for (final c in sortedClassrooms) {
                          tempSelected.add(c.name);
                        }
                      });
                    },
                    child: const Text('全选'),
                  ),
                  TextButton(
                    onPressed: () {
                      setDialogState(() {
                        tempSelected.clear();
                      });
                    },
                    child: const Text('清空'),
                  ),
                ],
              ),
              content: SizedBox(
                width: double.maxFinite,
                height: 400,
                child: ListView.builder(
                  itemCount: sortedClassrooms.length,
                  itemBuilder: (context, index) {
                    final classroom = sortedClassrooms[index];
                    return CheckboxListTile(
                      title: Text(classroom.name),
                      value: tempSelected.contains(classroom.name),
                      onChanged: (value) {
                        setDialogState(() {
                          if (value == true) {
                            tempSelected.add(classroom.name);
                          } else {
                            tempSelected.remove(classroom.name);
                          }
                        });
                      },
                      dense: true,
                    );
                  },
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () {
                    provider.setOverviewSelectedClassrooms(tempSelected);
                    Navigator.of(context).pop();
                  },
                  child: const Text('确定'),
                ),
              ],
            );
          },
        );
      },
    );
  }

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

  /// 下载总览页面为图片（跨平台方案）
  /// Web: 使用 JavaScript Canvas 绘制
  /// iOS/Android: 使用 RepaintBoundary 截图
  /// [filtered] - true: 只下载有课程的教室; false: 下载所有选中教室
  Future<void> _downloadOverviewImage({bool filtered = false}) async {
    try {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('正在生成截图...'), duration: Duration(seconds: 2)),
        );
      }

      // iOS：使用 RepaintBoundary 截图
      await _downloadOverviewImageMobile(filtered: filtered);
    } catch (e) {
      debugPrint('Download error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('下载失败: $e')),
        );
      }
    }
  }

  /// iOS平台：使用 RepaintBoundary 截图并保存到相册
  /// [filtered] - true: 只下载有课程的教室; false: 下载所有选中教室
  Future<void> _downloadOverviewImageMobile({bool filtered = false}) async {
    final provider = context.read<AppProvider>();
    final weekday = ExcelParserService.getWeekdayName(_selectedDate);

    // 获取当前显示的教室列表
    final pages = _getFilteredPages(provider.classrooms, provider);
    final selectedPages = provider.selectedOverviewPages;
    final allSelectedClassrooms = <Classroom>[];
    for (final page in pages) {
      if (selectedPages.contains(page.key)) {
        allSelectedClassrooms.addAll(page.value);
      }
    }
    final seen = <String>{};
    var classroomsToCapture = allSelectedClassrooms
        .where((c) => seen.add(c.name))
        .toList();

    // 应用教室筛选
    final selectedClassrooms = provider.overviewSelectedClassrooms;
    if (selectedClassrooms.isNotEmpty) {
      classroomsToCapture = classroomsToCapture
          .where((c) => selectedClassrooms.contains(c.name))
          .toList();
    }

    // 应用有课筛选
    if (filtered) {
      classroomsToCapture = classroomsToCapture.where((classroom) {
        return classroom.schedule.values.any((daySchedule) {
          return daySchedule.values.any((course) {
            if (course.weekday != weekday) return false;
            return _matchesCourseTypeFilter(course, provider);
          });
        });
      }).toList();
    }

    if (classroomsToCapture.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('没有符合条件的教室')),
        );
      }
      return;
    }

    // 使用临时Widget截图
    await _showMobileScreenshotPreviewWithClassrooms(
      classroomsToCapture,
      weekday,
      filtered,
    );
  }

  /// 显示移动端截图预览对话框
  void _showMobileScreenshotPreview(Uint8List imageBytes) {
    final weekday = ExcelParserService.getWeekdayName(DateTime.now());

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 标题栏
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withAlpha(26),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  const Icon(Icons.image, color: Colors.grey),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '今日总览 - $weekday',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  // 分享按钮
                  IconButton(
                    icon: const Icon(Icons.share),
                    tooltip: '分享图片',
                    onPressed: () => _shareImageBytes(imageBytes, '今日总览_$weekday.png'),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ),
            // 图片区域
            Flexible(
              child: Container(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.65,
                ),
                decoration: const BoxDecoration(
                  color: Colors.white,
                ),
                child: InteractiveViewer(
                  minScale: 0.5,
                  maxScale: 4.0,
                  child: Image.memory(
                    imageBytes,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
            ),
            // 底部提示
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withAlpha(26),
                    blurRadius: 4,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.touch_app,
                        size: 20,
                        color: Colors.grey.shade600,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '长按图片保存或截图分享',
                        style: TextStyle(
                          color: Colors.grey.shade700,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '提示：双指可缩放图片',
                    style: TextStyle(
                      color: Colors.grey.shade500,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 使用指定教室列表显示移动端截图预览
  Future<void> _showMobileScreenshotPreviewWithClassrooms(
    List<Classroom> classrooms,
    String weekday,
    bool filtered,
  ) async {
    final screenshotKey = GlobalKey();
    final now = _selectedDate;
    final absentMap = context.read<AppProvider>().absentClassrooms;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 标题栏
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withAlpha(26),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  const Icon(Icons.image, color: Colors.grey),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '今日总览 - $weekday${filtered ? "（有课教室）" : ""}',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ),
            // 截图区域
            Flexible(
              child: Container(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.65,
                ),
                decoration: const BoxDecoration(
                  color: Colors.white,
                ),
                child: SingleChildScrollView(
                  child: RepaintBoundary(
                    key: screenshotKey,
                    child: _buildScreenshotWidget(classrooms, weekday, now, absentMap),
                  ),
                ),
              ),
            ),
            // 底部按钮
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withAlpha(26),
                    blurRadius: 4,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ElevatedButton.icon(
                    onPressed: () async {
                      final boundary = screenshotKey.currentContext?.findRenderObject()
                          as RenderRepaintBoundary?;
                      if (boundary == null) return;

                      final image = await boundary.toImage(pixelRatio: 2.0);
                      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
                      if (byteData == null) return;

                      final imageBytes = byteData.buffer.asUint8List();
                      await _shareImageBytes(
                        imageBytes,
                        '今日总览_$weekday${filtered ? "_筛选" : ""}.png',
                      );
                    },
                    icon: const Icon(Icons.share),
                    label: const Text('分享'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 构建截图用的Widget - 参照参考图片布局
  Widget _buildScreenshotWidget(
    List<Classroom> classrooms,
    String weekday,
    DateTime now,
    Map<int, Set<String>> absentMap,
  ) {
    final sortedClassrooms = _getSortedClassrooms(classrooms);

    // 参照原图样式配置（紧凑布局）
    const double titleFontSize = 28;      // 标题字体
    const double headerFontSize = 14;     // 表头字体（减小避免换行）
    const double classroomFontSize = 16;  // 教室名字体
    const double cellHeight = 36;         // 单元格高度
    const double classroomColWidth = 60;  // 教室列宽度

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.all(12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 标题 - 参照图片顶部居中大字
          Text(
            '$weekday总览',
            style: const TextStyle(
              fontSize: titleFontSize,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 12),
          // 表头 - 参照图片：教室 + 1-12数字
          Container(
            padding: const EdgeInsets.symmetric(vertical: 6),
            decoration: BoxDecoration(
              color: Colors.grey.shade200,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(4),
                topRight: Radius.circular(4),
              ),
            ),
            child: Row(
              children: [
                // 教室列标题
                SizedBox(
                  width: classroomColWidth,
                  child: const Text(
                    '教室',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: headerFontSize,
                      fontWeight: FontWeight.bold,
                      color: Colors.black54,
                    ),
                  ),
                ),
                // 1-12节数字
                ...List.generate(12, (i) {
                  final period = i + 1;
                  return Expanded(
                    child: Center(
                      child: Text(
                        '$period',
                        style: const TextStyle(
                          fontSize: headerFontSize,
                          fontWeight: FontWeight.bold,
                          color: Colors.black54,
                        ),
                        overflow: TextOverflow.visible,
                        softWrap: false,
                      ),
                    ),
                  );
                }),
              ],
            ),
          ),
          // 教室列表
          ...sortedClassrooms.asMap().entries.map((entry) {
            final index = entry.key;
            final classroom = entry.value;
            final classroomNumber = classroom.name.replaceAll(RegExp(r'[^0-9]'), '');

            return Container(
              height: cellHeight,
              decoration: BoxDecoration(
                color: index % 2 == 0 ? Colors.grey.shade50 : Colors.white,
                border: Border(
                  bottom: BorderSide(color: Colors.grey.shade300),
                ),
              ),
              child: Row(
                children: [
                  // 教室编号
                  Container(
                    width: classroomColWidth,
                    alignment: Alignment.center,
                    child: Text(
                      classroomNumber,
                      style: const TextStyle(
                        fontSize: classroomFontSize,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                  ),
                  // 节次色块
                  ..._buildPeriodCellsForScreenshot(
                    classroom,
                    weekday,
                    now,
                    absentMap,
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  /// 为截图构建节次单元格 - 参照参考图片样式
  List<Widget> _buildPeriodCellsForScreenshot(
    Classroom classroom,
    String weekday,
    DateTime now,
    Map<int, Set<String>> absentMap,
  ) {
    // 分析课程连续块
    final courseBlocks = _analyzeCourseBlocks(classroom, weekday);
    final blockColors = <String, Color>{};

    return List.generate(12, (i) {
      final period = i + 1;
      final rawBlockId = courseBlocks[period];
      final blockId = rawBlockId != null ? _getActualBlockId(rawBlockId) : null;
      final firstPeriodOfBlock = rawBlockId != null
          ? _getFirstPeriodOfBlock(courseBlocks, rawBlockId)
          : period;

      // 判断是否有课
      final hasCourse = blockId != null && !blockId.startsWith('PERIOD5_INDEPENDENT_');

      // 判断是否为独立第5节
      final isIndependentPeriod5 = rawBlockId != null &&
          rawBlockId.startsWith('PERIOD5_INDEPENDENT_');

      Color cellColor;
      if (isIndependentPeriod5) {
        // 独立第5节使用深绿色
        cellColor = _period5Color;
      } else if (hasCourse && blockId != null) {
        // 为课程块分配颜色（使用起始节次对应的颜色）
        if (!blockColors.containsKey(blockId)) {
          blockColors[blockId] = _getPeriodColor(firstPeriodOfBlock);
        }
        cellColor = blockColors[blockId]!;
      } else {
        // 无课使用浅灰色
        cellColor = Colors.grey.shade300;
      }

      // 检查是否缺勤
      final reminderId = getReminderIdForPeriod(period);
      final isAbsent = hasCourse && reminderId != null &&
          absentMap[reminderId]?.contains(classroom.name) == true;

      // 根据背景亮度决定文字颜色
      final textColor = cellColor.computeLuminance() > 0.35
          ? Colors.black
          : Colors.white;

      return Expanded(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 1, vertical: 2),
          decoration: BoxDecoration(
            color: cellColor,
            borderRadius: BorderRadius.circular(1),
          ),
          child: isAbsent
              ? Center(
                  child: Text(
                    '缺',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: textColor,
                    ),
                  ),
                )
              : null,
        ),
      );
    });
  }

  /// 保存图片到相册（iOS/Android）
  Future<void> _saveImageToGallery(Uint8List imageBytes) async {
    try {
      // 使用分享功能让用户保存图片
      await _shareImageBytes(imageBytes, '今日总览截图.png');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('截图已生成，请选择保存方式')),
        );
      }
    } catch (e) {
      debugPrint('Error saving image: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存失败: $e')),
        );
      }
    }
  }

  /// 分享图片字节数据（iOS原生实现）
  Future<void> _shareImageBytes(Uint8List bytes, String filename) async {
    try {
      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/$filename');
      await file.writeAsBytes(bytes);
      await Share.shareXFiles(
        [XFile(file.path)],
        subject: filename,
      );
    } catch (e) {
      debugPrint('Share error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('分享失败: $e')),
        );
      }
    }
  }

  /// 获取经过筛选的教室列表（应用分页、教室筛选、课程类型筛选）
  List<Classroom> _getFilteredClassrooms(AppProvider provider) {
    // 获取当前显示的教室列表（应用分页筛选）
    final pages = _getFilteredPages(provider.classrooms, provider);
    final selectedPages = provider.selectedOverviewPages;
    final allSelectedClassrooms = <Classroom>[];
    for (final page in pages) {
      if (selectedPages.contains(page.key)) {
        allSelectedClassrooms.addAll(page.value);
      }
    }
    final seen = <String>{};
    var filteredClassrooms = allSelectedClassrooms
        .where((c) => seen.add(c.name))
        .toList();

    // 应用教室筛选
    final selectedClassrooms = provider.overviewSelectedClassrooms;
    if (selectedClassrooms.isNotEmpty) {
      filteredClassrooms = filteredClassrooms
          .where((c) => selectedClassrooms.contains(c.name))
          .toList();
    }

    return filteredClassrooms;
  }

  /// 分析第7、8节课程并复制到粘贴板
  /// 筛选第7、8节老师不同的课程，生成格式：
  /// "15：40 需要优先擦黑板的教室有：xxx、xxx、xxx"
  /// 对于7、8节老师相同、课程不同的情况，追加：
  /// "另外，xxx、xxx教室课程变化但老师不变，按老师要求擦黑板"
  void _copyBlackboardText(AppProvider provider) {
    final weekday = ExcelParserService.getWeekdayName(_selectedDate);
    // 使用筛选后的教室列表
    final classrooms = _getFilteredClassrooms(provider);

    // 筛选有第7、8节课程的教室
    final teacherDifferentClassrooms = <String>[]; // 老师不同的教室
    final courseDifferentClassrooms = <String>[];  // 课程不同但老师相同的教室

    for (final classroom in classrooms) {
      final period7Course = classroom.getCourseAtPeriod(weekday, 7);
      final period8Course = classroom.getCourseAtPeriod(weekday, 8);

      // 两个节次都有课才进行比较
      if (period7Course != null && period8Course != null) {
        final teacher7 = period7Course.teacher ?? '';
        final teacher8 = period8Course.teacher ?? '';
        final course7 = period7Course.name;
        final course8 = period8Course.name;

        // 老师不同
        if (teacher7 != teacher8) {
          final classroomNumber = classroom.name.replaceAll(RegExp(r'[^0-9]'), '');
          teacherDifferentClassrooms.add(classroomNumber);
        }
        // 老师相同但课程不同
        else if (teacher7 == teacher8 && course7 != course8) {
          final classroomNumber = classroom.name.replaceAll(RegExp(r'[^0-9]'), '');
          courseDifferentClassrooms.add(classroomNumber);
        }
      }
    }

    // 生成文本
    final buffer = StringBuffer();

    if (teacherDifferentClassrooms.isNotEmpty) {
      buffer.write('15：40 需要优先擦黑板的教室有：');
      buffer.write(teacherDifferentClassrooms.join('、'));
      buffer.write('。');
    }

    if (courseDifferentClassrooms.isNotEmpty) {
      if (buffer.isNotEmpty) {
        buffer.write('\n');
      }
      buffer.write('另外，');
      buffer.write(courseDifferentClassrooms.join('、'));
      buffer.write('教室课程变化但老师不变，按老师要求擦黑板。');
    }

    if (buffer.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('没有第7、8节老师不同或课程变化的教室')),
        );
      }
      return;
    }

    // 复制到粘贴板
    Clipboard.setData(ClipboardData(text: buffer.toString()));

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已复制到粘贴板')),
      );
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
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('今日总览'),
        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
        leading: IconButton(
          icon: const Icon(Icons.filter_alt_outlined),
          tooltip: '下载筛选图片（有课的教室）',
          onPressed: () => _downloadOverviewImage(filtered: true),
        ),
        actions: [
          // 搜索按钮
          IconButton(
            icon: Icon(_showSearchBox ? Icons.close : Icons.search),
            tooltip: '搜索课程/老师',
            onPressed: () {
              setState(() {
                _showSearchBox = !_showSearchBox;
                if (!_showSearchBox) {
                  _searchController.clear();
                  _searchResults = [];
                } else {
                  Future.delayed(const Duration(milliseconds: 100), () {
                    _searchFocusNode.requestFocus();
                  });
                }
              });
            },
          ),
          // 复制黑板提示按钮
          IconButton(
            icon: const Icon(Icons.content_copy),
            tooltip: '复制7、8节黑板提示',
            onPressed: () => _copyBlackboardText(context.read<AppProvider>()),
          ),
          // 前一天按钮
          IconButton(
            icon: const Icon(Icons.chevron_left),
            tooltip: '前一天',
            onPressed: _goToPreviousDay,
          ),
          // 后一天按钮
          IconButton(
            icon: const Icon(Icons.chevron_right),
            tooltip: '后一天',
            onPressed: _goToNextDay,
          ),
          // 下载全部按钮
          IconButton(
            icon: const Icon(Icons.download),
            tooltip: '下载全部图片',
            onPressed: () => _downloadOverviewImage(filtered: false),
          ),
        ],
      ),
      body: Consumer<AppProvider>(
        builder: (context, provider, _) {
          final now = _selectedDate;
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
          // 使用 addPostFrameCallback 避免在 build 过程中调用 notifyListeners
          if (!_hasInitializedDefaultPage) {
            _hasInitializedDefaultPage = true;
            if (provider.selectedOverviewPages.isEmpty) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                provider.toggleOverviewPage('2楼大');
              });
            }
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
          var currentPageClassrooms = allSelectedClassrooms
              .where((c) => seen.add(c.name))
              .toList();

          // 应用教室筛选
          final selectedClassrooms = provider.overviewSelectedClassrooms;
          if (selectedClassrooms.isNotEmpty) {
            currentPageClassrooms = currentPageClassrooms
                .where((c) => selectedClassrooms.contains(c.name))
                .toList();
          }

          return Column(
            children: [
              // 搜索框
              if (_showSearchBox)
                Container(
                  padding: const EdgeInsets.all(12),
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  child: TextField(
                    controller: _searchController,
                    focusNode: _searchFocusNode,
                    decoration: InputDecoration(
                      hintText: '搜索课程或老师...',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _searchController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                _searchController.clear();
                                setState(() {
                                  _searchResults = [];
                                });
                              },
                            )
                          : null,
                      border: const OutlineInputBorder(),
                      filled: true,
                      fillColor: Colors.white,
                    ),
                    onChanged: (value) {
                      _performSearch(value);
                    },
                  ),
                ),

              // 搜索结果
              if (_searchResults.isNotEmpty)
                Container(
                  height: 200,
                  color: Colors.yellow.shade50,
                  child: ListView.builder(
                    itemCount: _searchResults.length,
                    itemBuilder: (context, index) {
                      final result = _searchResults[index];
                      return ListTile(
                        dense: true,
                        leading: Icon(
                          result.matchType == 'teacher'
                              ? Icons.person
                              : Icons.book,
                          color: result.matchType == 'teacher'
                              ? Colors.blue
                              : Colors.green,
                        ),
                        title: Text(
                          '${result.classroom.name} - ${result.course.name}',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text(
                          '第${result.period}节 | ${result.course.teacher ?? "无老师"}',
                        ),
                        onTap: () {
                          // 关闭搜索框并清空结果
                          setState(() {
                            _showSearchBox = false;
                            _searchController.clear();
                            _searchResults = [];
                          });
                          // 跳转到课程详情页面
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => CourseDisplayScreen(classroom: result.classroom),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),

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
                          '$weekday (${_selectedDate.month}/${_selectedDate.day})',
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
                    const SizedBox(height: 4),
                    // 筛选栏标题 + 展开/收起按钮
                    InkWell(
                      onTap: () => provider.toggleOverviewFilterExpanded(),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            provider.isOverviewFilterExpanded ? Icons.expand_less : Icons.expand_more,
                            size: 20,
                            color: Colors.grey.shade600,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            provider.isOverviewFilterExpanded ? '收起筛选' : '展开筛选',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade600,
                            ),
                          ),
                          const SizedBox(width: 4),
                          // 显示当前筛选状态摘要
                          if (!provider.isOverviewFilterExpanded) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.purple.shade100,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                '${provider.selectedOverviewPages.length}个分页',
                                style: const TextStyle(fontSize: 11),
                              ),
                            ),
                            const SizedBox(width: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.blue.shade100,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                '${provider.overviewCourseTypes.length}种类型',
                                style: const TextStyle(fontSize: 11),
                              ),
                            ),
                            const SizedBox(width: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.orange.shade100,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                provider.overviewSelectedClassrooms.isEmpty ? '全部教室' : '${provider.overviewSelectedClassrooms.length}个教室',
                                style: const TextStyle(fontSize: 11),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    // 展开的筛选内容
                    if (provider.isOverviewFilterExpanded) ...[
                      const SizedBox(height: 8),
                      // 分页标签（多选）
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        alignment: WrapAlignment.center,
                        children: pages.asMap().entries.map((entry) {
                          final pageName = entry.value.key;
                          final isSelected = provider.isOverviewPageSelected(pageName);

                          return FilterChip(
                            label: Text(pageName, style: const TextStyle(fontSize: 11)),
                            selected: isSelected,
                            onSelected: (_) {
                              provider.toggleOverviewPage(pageName);
                            },
                            selectedColor: Theme.of(context).colorScheme.primaryContainer,
                            backgroundColor: Colors.grey.shade200,
                            checkmarkColor: Theme.of(context).colorScheme.primary,
                            padding: EdgeInsets.zero,
                            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          );
                        }).toList(),
                      ),
                      const Divider(height: 16),
                      // 课程类型筛选
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        alignment: WrapAlignment.center,
                        children: [
                          FilterChip(
                            label: const Text('研究生', style: TextStyle(fontSize: 11)),
                            selected: provider.overviewCourseTypes.contains('graduate'),
                            onSelected: (_) => _toggleCourseType('graduate', provider),
                            selectedColor: Colors.blue.shade100,
                            padding: EdgeInsets.zero,
                            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          FilterChip(
                            label: const Text('本科', style: TextStyle(fontSize: 11)),
                            selected: provider.overviewCourseTypes.contains('undergraduate'),
                            onSelected: (_) => _toggleCourseType('undergraduate', provider),
                            selectedColor: Colors.green.shade100,
                            padding: EdgeInsets.zero,
                            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          FilterChip(
                            label: const Text('借用', style: TextStyle(fontSize: 11)),
                            selected: provider.overviewCourseTypes.contains('borrowed'),
                            onSelected: (_) => _toggleCourseType('borrowed', provider),
                            selectedColor: Colors.orange.shade100,
                            padding: EdgeInsets.zero,
                            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          ActionChip(
                            label: Text(
                              provider.overviewSelectedClassrooms.isEmpty
                                  ? '教室'
                                  : '教室(${provider.overviewSelectedClassrooms.length})',
                              style: const TextStyle(fontSize: 11),
                            ),
                            avatar: const Icon(Icons.meeting_room, size: 14),
                            onPressed: () => _showClassroomFilterDialog(currentPageClassrooms, provider),
                            padding: EdgeInsets.zero,
                            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                        ],
                      ),
                    ],
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
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 2),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: Colors.grey.shade700,
          ),
        ),
      ],
    );
  }
}

/// 搜索结果数据类
class _SearchResult {
  final Classroom classroom;
  final int period;
  final Course course;
  final String matchType; // 'teacher' 或 'course'

  _SearchResult({
    required this.classroom,
    required this.period,
    required this.course,
    required this.matchType,
  });
}
