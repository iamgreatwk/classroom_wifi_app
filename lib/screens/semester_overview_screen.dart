import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:provider/provider.dart';
import '../models/course_with_week.dart';
import '../providers/app_provider.dart';
import '../services/web_download_service.dart';
// Web 平台特定的导入
import 'package:flutter/foundation.dart';

// 条件导入：仅在 Web 平台导入 dart:js
import '../utils/conditional_import.dart';

/// 学期总览页面 - 显示整学期课表，支持按周次筛选
/// 采用表格布局，颜色区分不同课程
class SemesterOverviewScreen extends StatefulWidget {
  const SemesterOverviewScreen({super.key});

  @override
  State<SemesterOverviewScreen> createState() => _SemesterOverviewScreenState();
}

class _SemesterOverviewScreenState extends State<SemesterOverviewScreen> {
  /// 当前显示的星期（0=周日，1=周一，...，6=周六）
  int _selectedWeekday = DateTime.now().weekday % 7;

  /// 课程类型筛选
  Set<String> _selectedCourseTypes = {'graduate', 'undergraduate', 'borrowed'};

  /// 教室筛选
  Set<String> _selectedClassrooms = {};

  /// 分页筛选（2楼大、2楼小、3楼大等）
  Set<String> _selectedPages = {'2楼大'};

  /// 单周/连续周筛选
  /// 'single' = 单周, 'continuous' = 连续周
  Set<String> _selectedWeekTypes = {'single', 'continuous'};

  /// 是否显示搜索框
  bool _showSearchBox = false;

  /// 搜索控制器
  final TextEditingController _searchController = TextEditingController();

  /// 搜索焦点节点
  final FocusNode _searchFocusNode = FocusNode();

  /// 搜索结果列表
  List<_SearchResult> _searchResults = [];

  /// GlobalKey for capturing the overview widget
  final GlobalKey _screenshotKey = GlobalKey();

  /// 是否正在截图中
  bool _isCapturing = false;

  /// 是否展开筛选区域
  bool _isFilterExpanded = true;

  static const List<String> _weekdays = [
    '星期日',
    '星期一',
    '星期二',
    '星期三',
    '星期四',
    '星期五',
    '星期六',
  ];

  /// 分页配置
  static const Map<String, List<int>> _pageConfigs = {
    '1楼': [113, 114],
    '2楼小': [204, 205, 206, 207, 208, 209, 210, 211, 212, 213, 214, 215, 216, 217],
    '2楼大': [218, 219, 220, 221, 222, 223, 224, 225, 226, 227, 228, 229, 230, 231, 232, 233, 234],
    '3楼小': [301, 302, 303, 304, 305, 308, 309, 310, 311, 312, 313, 314, 315],
    '3楼大': [316, 317, 318, 319, 320, 321, 322, 323, 324, 325, 326, 327, 328, 329, 330, 331, 332, 333],
    '4楼小': [401, 402, 403, 404, 405, 407, 409, 410, 411, 412, 413, 414, 415],
    '4楼大': [416, 417, 418, 419, 420, 421, 422, 423, 424, 425, 426, 427, 428, 429, 430, 431, 432, 433],
    '5楼语音室': [501, 502, 503, 504, 505, 512, 513, 514, 515, 516, 517, 518],
    '5楼多媒体': [507, 508, 509, 510, 511, 524, 525, 526, 527, 528, 529],
  };

  /// 时间段颜色配置 - 每个节次位置使用固定颜色
  static final Map<String, List<Color>> _timeBlockColorSets = {
    'morning': [    // 1-4节 上午
      Color(0xFF1565C0),  // 位置1 - 深蓝
      Color(0xFF00897B),  // 位置2 - 深青绿
      Color(0xFF6A1B9A),  // 位置3 - 深紫
      Color(0xFF0277BD),  // 位置4 - 深天蓝
    ],
    'afternoon': [  // 6-9节 下午
      Color(0xFFC62828),  // 位置6 - 深红
      Color(0xFF1565C0),  // 位置7 - 深蓝
      Color(0xFF2E7D32),  // 位置8 - 深绿
      Color(0xFFEF6C00),  // 位置9 - 深橙
    ],
    'evening': [    // 10-12节 晚上
      Color(0xFF6A1B9A),  // 位置10 - 深紫
      Color(0xFFAD1457),  // 位置11 - 深粉红
      Color(0xFF4527A0),  // 位置12 - 深深紫
    ],
  };

  /// 第5节专用颜色
  static const Color _period5Color = Color(0xFF2E7D32);  // 深绿色

  /// 单周课程边框颜色（改为黑色）
  static const Color _singleWeekBorderColor = Color(0xFF000000);  // 黑色

  /// 角标颜色
  static const Color _leftBadgeColor = Color(0xFFFF9800);  // 橙色 - 与上周不同
  static const Color _rightBadgeColor = Color(0xFFF44336);  // 红色 - 单周课程

  /// 获取实际显示周次
  /// 周日（day_index=0）显示 currentWeek+1 的数据，因为周日是一周第一天
  int _getDisplayWeek(int currentWeek, int dayIndex) {
    if (dayIndex == 0) {
      // 周日显示下一周的数据
      return currentWeek + 1;
    }
    return currentWeek;
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  /// 判断教室是否属于某个分页
  bool _isClassroomInPage(String classroomName, String pageName) {
    final allowedNumbers = _pageConfigs[pageName];
    if (allowedNumbers == null) return false;
    final numStr = classroomName.replaceAll(RegExp(r'[^0-9]'), '');
    final num = int.tryParse(numStr);
    return num != null && allowedNumbers.contains(num);
  }

  /// 获取有教室数据的分页列表
  List<String> _getAvailablePages(List<SemesterClassroom> classrooms) {
    final availablePages = <String>[];
    for (final pageName in _pageConfigs.keys) {
      final hasClassroomInPage = classrooms.any((c) => _isClassroomInPage(c.name, pageName));
      if (hasClassroomInPage) {
        availablePages.add(pageName);
      }
    }
    return availablePages;
  }

  /// 判断课程是否为研究生课程
  bool _isGraduateCourse(CourseWithWeek course) {
    final rawText = course.rawText ?? '';
    return rawText.startsWith('(研)') || rawText.startsWith('◇');
  }

  /// 判断课程是否为借用课程
  bool _isBorrowedCourse(CourseWithWeek course) {
    final rawText = course.rawText ?? '';
    return rawText.startsWith('借用');
  }

  /// 判断课程是否匹配当前筛选条件
  bool _matchesCourseTypeFilter(CourseWithWeek course) {
    if (_selectedCourseTypes.isEmpty) return true;

    final isGraduate = _isGraduateCourse(course);
    final isBorrowed = _isBorrowedCourse(course);
    final isUndergraduate = !isBorrowed && !isGraduate;

    if (_selectedCourseTypes.contains('graduate') && isGraduate) return true;
    if (_selectedCourseTypes.contains('undergraduate') && isUndergraduate)
      return true;
    if (_selectedCourseTypes.contains('borrowed') && isBorrowed) return true;

    return false;
  }

  /// 判断课程是否匹配周次类型筛选
  bool _matchesWeekTypeFilter(CourseWithWeek course) {
    if (_selectedWeekTypes.isEmpty) return true;
    if (_selectedWeekTypes.length == 2) return true;
    if (_selectedWeekTypes.contains('single') && course.isSingleWeek) return true;
    if (_selectedWeekTypes.contains('continuous') && !course.isSingleWeek)
      return true;
    return false;
  }

  /// 切换课程类型筛选
  void _toggleCourseType(String type) {
    setState(() {
      if (_selectedCourseTypes.contains(type)) {
        if (_selectedCourseTypes.length > 1) {
          _selectedCourseTypes.remove(type);
        }
      } else {
        _selectedCourseTypes.add(type);
      }
    });
  }

  /// 切换分页筛选
  void _togglePage(String pageName) {
    setState(() {
      if (_selectedPages.contains(pageName)) {
        if (_selectedPages.length > 1) {
          _selectedPages.remove(pageName);
        }
      } else {
        _selectedPages.add(pageName);
      }
    });
  }

  /// 切换周次类型筛选
  void _toggleWeekType(String type) {
    setState(() {
      if (_selectedWeekTypes.contains(type)) {
        if (_selectedWeekTypes.length > 1) {
          _selectedWeekTypes.remove(type);
        }
      } else {
        _selectedWeekTypes.add(type);
      }
    });
  }

  /// 获取按数字排序后的教室列表
  List<SemesterClassroom> _getSortedClassrooms(
      List<SemesterClassroom> classrooms) {
    return List<SemesterClassroom>.from(classrooms)
      ..sort((a, b) {
        final aNumStr = a.name.replaceAll(RegExp(r'[^0-9]'), '');
        final bNumStr = b.name.replaceAll(RegExp(r'[^0-9]'), '');
        final aNum = int.tryParse(aNumStr) ?? 0;
        final bNum = int.tryParse(bNumStr) ?? 0;
        return aNum.compareTo(bNum);
      });
  }

  /// 应用分页筛选
  List<SemesterClassroom> _applyPageFilter(
      List<SemesterClassroom> classrooms) {
    if (_selectedPages.isEmpty) return classrooms;
    return classrooms.where((c) {
      return _selectedPages.any((page) => _isClassroomInPage(c.name, page));
    }).toList();
  }

  /// 应用教室筛选
  List<SemesterClassroom> _applyClassroomFilter(
      List<SemesterClassroom> classrooms) {
    if (_selectedClassrooms.isEmpty) {
      return classrooms;
    }
    return classrooms.where((c) => _selectedClassrooms.contains(c.name)).toList();
  }

  /// 筛选：只保留在当前周和选中类型下有课的教室
  List<SemesterClassroom> _filterClassroomsWithCourses(
    List<SemesterClassroom> classrooms,
    int currentWeek,
    String weekday,
  ) {
    return classrooms.where((classroom) {
      for (int period = 1; period <= 12; period++) {
        final courses = classroom.getCourses(weekday, period);
        for (final course in courses) {
          if (course.hasClassInWeek(currentWeek) &&
              _matchesCourseTypeFilter(course) &&
              _matchesWeekTypeFilter(course)) {
            return true;
          }
        }
      }
      return false;
    }).toList();
  }

  /// 筛选：保留在选中课程类型下有课程的教室（不管当前周是否有课）
  List<SemesterClassroom> _filterClassroomsByCourseType(
    List<SemesterClassroom> classrooms,
    String weekday,
  ) {
    return classrooms.where((classroom) {
      for (int period = 1; period <= 12; period++) {
        final courses = classroom.getCourses(weekday, period);
        for (final course in courses) {
          if (_matchesCourseTypeFilter(course) &&
              _matchesWeekTypeFilter(course)) {
            return true;
          }
        }
      }
      return false;
    }).toList();
  }

  /// 获取节次对应的颜色
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
    return _period5Color; // 第5节
  }

  /// 显示教室筛选对话框
  void _showClassroomFilterDialog(List<SemesterClassroom> allClassrooms) {
    final tempSelected = Set<String>.from(_selectedClassrooms);
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
                    setState(() {
                      _selectedClassrooms = tempSelected;
                    });
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

  /// 分析教室的课程连续块（考虑周次）
  Map<int, Map<String, dynamic>> _analyzeCourseBlocks(
    SemesterClassroom classroom,
    String weekday,
    int currentWeek,
  ) {
    final blocks = <int, Map<String, dynamic>>{};
    String? currentBlockId;
    String? lastCourseKey;
    int? firstPeriodOfBlock;

    for (int period = 1; period <= 12; period++) {
      final courses = classroom.getCourses(weekday, period);
      CourseWithWeek? activeCourse;
      for (final course in courses) {
        if (course.hasClassInWeek(currentWeek) &&
            _matchesCourseTypeFilter(course) &&
            _matchesWeekTypeFilter(course)) {
          activeCourse = course;
          break;
        }
      }

      if (activeCourse != null) {
        final courseKey =
            '${activeCourse.name}_${activeCourse.teacher ?? ''}_${activeCourse.startWeek}_${activeCourse.endWeek}';
        if (courseKey != lastCourseKey) {
          currentBlockId = '${classroom.name}_${period}_$courseKey';
          firstPeriodOfBlock = period;
          lastCourseKey = courseKey;
        }
        blocks[period] = {
          'blockId': currentBlockId,
          'firstPeriod': firstPeriodOfBlock,
          'course': activeCourse,
        };
      } else {
        currentBlockId = null;
        lastCourseKey = null;
        firstPeriodOfBlock = null;
      }
    }

    return blocks;
  }

  /// 执行搜索（搜索所有周的课表）
  void _performSearch(String query, List<SemesterClassroom> classrooms) {
    if (query.isEmpty) {
      setState(() {
        _searchResults = [];
      });
      return;
    }

    final results = <_SearchResult>[];
    final lowerQuery = query.toLowerCase();

    // 获取当前选中的周次
    final provider = context.read<AppProvider>();
    final selectedWeek = provider.selectedWeek;

    // 遍历所有星期和周次进行搜索
    for (int week = 1; week <= 18; week++) {
      for (final day in _weekdays) {
        for (final classroom in classrooms) {
          // 筛选：检查教室是否在选中的分页中
          final isInSelectedPage = _selectedPages.any(
            (page) => _isClassroomInPage(classroom.name, page),
          );
          if (!isInSelectedPage) continue;

          // 筛选：检查教室是否在勾选的教室列表中
          if (_selectedClassrooms.isNotEmpty &&
              !_selectedClassrooms.contains(classroom.name)) {
            continue;
          }

          for (int period = 1; period <= 12; period++) {
            final courses = classroom.getCourses(day, period);
            for (final course in courses) {
              if (!course.hasClassInWeek(week)) continue;
              if (!_matchesCourseTypeFilter(course)) continue;
              if (!_matchesWeekTypeFilter(course)) continue;

              // 搜索课程名
              if (course.name.toLowerCase().contains(lowerQuery)) {
                results.add(_SearchResult(
                  classroom: classroom,
                  weekday: day,
                  period: period,
                  course: course,
                  week: week,
                  matchType: 'course',
                ));
              }
              // 搜索老师名
              else if (course.teacher != null &&
                  course.teacher!.toLowerCase().contains(lowerQuery)) {
                results.add(_SearchResult(
                  classroom: classroom,
                  weekday: day,
                  period: period,
                  course: course,
                  week: week,
                  matchType: 'teacher',
                ));
              }
            }
          }
        }
      }
    }

    // 排序：选定周 → 选定周之后的周 → 选定周之前的周
    // 同一周内：选定星期 → 选定星期之后的星期 → 选定星期之前的星期
    final selectedWeekdayIndex = _selectedWeekday;
    results.sort((a, b) {
      // 首先按周次排序
      final aIsSelected = a.week == selectedWeek;
      final bIsSelected = b.week == selectedWeek;

      if (aIsSelected && !bIsSelected) return -1;
      if (!aIsSelected && bIsSelected) return 1;

      final aAfterSelected = a.week > selectedWeek;
      final bAfterSelected = b.week > selectedWeek;

      if (aAfterSelected && !bAfterSelected) return -1;
      if (!aAfterSelected && bAfterSelected) return 1;

      // 同一周，按星期排序：选定星期 → 之后 → 之前
      final aWeekdayIndex = _weekdays.indexOf(a.weekday);
      final bWeekdayIndex = _weekdays.indexOf(b.weekday);

      final aIsSelectedDay = aWeekdayIndex == selectedWeekdayIndex;
      final bIsSelectedDay = bWeekdayIndex == selectedWeekdayIndex;

      if (aIsSelectedDay && !bIsSelectedDay) return -1;
      if (!aIsSelectedDay && bIsSelectedDay) return 1;

      final aAfterDay = aWeekdayIndex > selectedWeekdayIndex;
      final bAfterDay = bWeekdayIndex > selectedWeekdayIndex;

      if (aAfterDay && !bAfterDay) return -1;
      if (!aAfterDay && bAfterDay) return 1;

      // 同组内按星期排序
      if (aWeekdayIndex != bWeekdayIndex) {
        return aWeekdayIndex.compareTo(bWeekdayIndex);
      }

      // 最后按节次排序
      return a.period.compareTo(b.period);
    });

    setState(() {
      _searchResults = results;
    });
  }

  /// 显示汇总输入对话框
  void _showSummaryDialog() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('汇总课程/老师'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: '输入课程名称或老师姓名',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final query = controller.text.trim();
              if (query.isNotEmpty) {
                Navigator.of(context).pop();
                _showSummaryResultDialog(query);
              }
            },
            child: const Text('汇总'),
          ),
        ],
      ),
    );
  }

  /// 计算并显示汇总结果
  void _showSummaryResultDialog(String query) {
    final lowerQuery = query.toLowerCase();
    final results = <_SummaryItem>[];

    // 获取教室数据
    final provider = context.read<AppProvider>();
    final classrooms = provider.semesterClassrooms;

    // 遍历所有数据汇总（不筛选周数，显示整个学期）
    for (int week = 1; week <= 18; week++) {
      for (final day in _weekdays) {
        for (final classroom in classrooms) {
          // 应用筛选条件（分页、教室、课程类型、周次类型）
          final isInSelectedPage = _selectedPages.any(
            (page) => _isClassroomInPage(classroom.name, page),
          );
          if (!isInSelectedPage) continue;
          if (_selectedClassrooms.isNotEmpty &&
              !_selectedClassrooms.contains(classroom.name)) {
            continue;
          }

          for (int period = 1; period <= 12; period++) {
            final courses = classroom.getCourses(day, period);
            for (final course in courses) {
              // 汇总不筛选周数，显示整个学期的课程
              if (!_matchesCourseTypeFilter(course)) continue;
              if (!_matchesWeekTypeFilter(course)) continue;

              // 精确匹配课程名或老师名（非模糊匹配）
              final matchesCourse = course.name.toLowerCase() == lowerQuery;
              final matchesTeacher = course.teacher != null &&
                  course.teacher!.toLowerCase() == lowerQuery;

              if (matchesCourse || matchesTeacher) {
                results.add(_SummaryItem(
                  course: course,
                  classroom: classroom.name,
                  weekday: day,
                  period: period,
                  week: week,
                  isTeacherQuery: matchesTeacher && !matchesCourse,
                ));
              }
            }
          }
        }
      }
    }

    // 按课程、教室、星期、节次排序
    results.sort((a, b) {
      final courseCompare = a.course.name.compareTo(b.course.name);
      if (courseCompare != 0) return courseCompare;
      final roomCompare = a.classroom.compareTo(b.classroom);
      if (roomCompare != 0) return roomCompare;
      final dayCompare = _weekdays.indexOf(a.weekday).compareTo(_weekdays.indexOf(b.weekday));
      if (dayCompare != 0) return dayCompare;
      return a.period.compareTo(b.period);
    });

    // 去重：相同课程+教室+星期+节次只保留一条（合并周次）
    final uniqueResults = <_SummaryItem>[];
    final seen = <String>{};
    for (final item in results) {
      final key = '${item.course.name}_${item.classroom}_${item.weekday}_${item.period}';
      if (!seen.contains(key)) {
        seen.add(key);
        uniqueResults.add(item);
      }
    }

    if (uniqueResults.isEmpty) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('汇总结果'),
          content: Text('未找到与 "$query" 相关的课程'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('确定'),
            ),
          ],
        ),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 500, maxHeight: 700),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 标题栏
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '"$query" 汇总',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            '共 ${uniqueResults.length} 条记录',
                            style: TextStyle(
                              fontSize: 14,
                              color: Theme.of(context).colorScheme.onPrimaryContainer.withOpacity(0.8),
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
              // 内容区域
              Flexible(
                child: ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: uniqueResults.length,
                  itemBuilder: (context, index) {
                    final item = uniqueResults[index];
                    final periodColor = _getPeriodColor(item.period);
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        dense: true,
                        leading: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: periodColor,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Center(
                            child: Text(
                              '第${item.period}节',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ),
                        title: Text(
                          item.course.name,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('${item.classroom} | ${item.weekday}'),
                            if (item.course.teacher != null && item.course.teacher!.isNotEmpty)
                              Text('老师: ${item.course.teacher}'),
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: item.course.isSingleWeek
                                        ? _singleWeekBorderColor.withOpacity(0.2)
                                        : periodColor.withOpacity(0.2),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    item.course.isSingleWeek
                                        ? '单周 ${item.course.weekDisplay}'
                                        : '连续 ${item.course.weekDisplay}',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: item.course.isSingleWeek
                                          ? _singleWeekBorderColor
                                          : periodColor,
                                    ),
                                  ),
                                ),
                                if (item.course.studentCount != null) ...[
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.grey.shade200,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      '${item.course.studentCount}人',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.grey.shade700,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                        isThreeLine: true,
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 显示教室课程详情对话框
  void _showClassroomDetailDialog(
    SemesterClassroom classroom,
    String weekday,
    int currentWeek,
  ) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400, maxHeight: 600),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 标题栏
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            classroom.name,
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).colorScheme.onPrimaryContainer,
                            ),
                          ),
                          Text(
                            '$weekday 第$currentWeek周',
                            style: TextStyle(
                              fontSize: 14,
                              color: Theme.of(context).colorScheme.onPrimaryContainer.withOpacity(0.8),
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
              // 内容区域
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: _buildClassroomSchedule(classroom, weekday, currentWeek),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 构建教室课程表详情
  Widget _buildClassroomSchedule(
    SemesterClassroom classroom,
    String weekday,
    int currentWeek,
  ) {
    final List<Widget> periodCards = [];

    for (int period = 1; period <= 12; period++) {
      final courses = classroom.getCourses(weekday, period);
      CourseWithWeek? activeCourse;
      for (final course in courses) {
        if (course.hasClassInWeek(currentWeek) &&
            _matchesCourseTypeFilter(course) &&
            _matchesWeekTypeFilter(course)) {
          activeCourse = course;
          break;
        }
      }

      periodCards.add(
        Card(
          margin: const EdgeInsets.only(bottom: 8),
          color: activeCourse != null ? null : Colors.grey[100],
          child: InkWell(
            onTap: activeCourse != null
                ? () => _showCourseDetailDialog(activeCourse!, period, weekday, classroom.name)
                : null,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  // 节次
                  Container(
                    width: 50,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      color: activeCourse != null
                          ? _getPeriodColor(period)
                          : Colors.grey,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      children: [
                        Text(
                          '第$period',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          '节',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.8),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  // 课程信息
                  Expanded(
                    child: activeCourse != null
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                activeCourse.displayName,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: activeCourse.isSingleWeek
                                          ? _singleWeekBorderColor.withOpacity(0.2)
                                          : _getPeriodColor(period).withOpacity(0.2),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      activeCourse.isSingleWeek
                                          ? '单周 ${activeCourse.weekDisplay}'
                                          : '连续 ${activeCourse.weekDisplay}',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: activeCourse.isSingleWeek
                                            ? _singleWeekBorderColor
                                            : _getPeriodColor(period),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          )
                        : Text(
                            '无课',
                            style: TextStyle(color: Colors.grey[500]),
                          ),
                  ),
                  if (activeCourse != null)
                    const Icon(Icons.chevron_right, color: Colors.grey),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: periodCards,
    );
  }

  /// 显示课程详情弹窗
  void _showCourseDetailDialog(
    CourseWithWeek course,
    int period,
    String weekday,
    String classroomName,
  ) {
    // 获取节次对应的颜色
    final periodColor = _getPeriodColor(period);

    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400, maxHeight: 600),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 标题栏 - 使用节次颜色
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: periodColor,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '课程详情',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          Text(
                            '$classroomName - $weekday 第$period节',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.white.withOpacity(0.9),
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
              // 内容区域
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 结构化信息 - 使用节次颜色
                      _buildInfoCard(
                        title: '课程信息',
                        icon: Icons.book,
                        items: [
                          _InfoItem('课程名称', course.name),
                          if (course.teacher != null && course.teacher!.isNotEmpty)
                            _InfoItem('授课老师', course.teacher!),
                          _InfoItem('上课时间', '$weekday 第$period节'),
                          _InfoItem('周次安排', course.isSingleWeek
                              ? '单周 ${course.weekDisplay}'
                              : '连续周 ${course.weekDisplay}'),
                          _InfoItem('上课地点', classroomName),
                          if (course.studentCount != null)
                            _InfoItem('上课人数', '${course.studentCount}人'),
                        ],
                        accentColor: periodColor,
                        isSingleWeek: course.isSingleWeek,
                      ),
                      const SizedBox(height: 16),
                      // 原始数据
                      _buildInfoCard(
                        title: '原始数据',
                        icon: Icons.raw_on,
                        items: [
                          _InfoItem('课程原始文本', course.rawText ?? course.displayName),
                          if (course.teacher != null && course.teacher!.isNotEmpty)
                            _InfoItem('老师原始文本', course.teacher!),
                        ],
                        isRaw: true,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 构建信息卡片
  Widget _buildInfoCard({
    required String title,
    required IconData icon,
    required List<_InfoItem> items,
    bool isRaw = false,
    Color? accentColor,
    bool isSingleWeek = false,
  }) {
    // 根据是否传入强调色来决定卡片样式
    final borderColor = isRaw
        ? Colors.orange.shade200
        : (accentColor != null
            ? accentColor.withOpacity(0.5)
            : Colors.grey.shade300);
    final bgColor = isRaw
        ? Colors.orange.shade50
        : (accentColor != null
            ? accentColor.withOpacity(0.05)
            : Colors.grey.shade50);
    final iconColor = isRaw
        ? Colors.orange
        : (accentColor ?? Theme.of(context).colorScheme.primary);
    final titleColor = isRaw
        ? Colors.orange.shade800
        : (accentColor ?? Colors.black87);

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: borderColor,
          width: isSingleWeek ? 2 : 1, // 单周课程用更粗的边框
        ),
      ),
      color: bgColor,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  icon,
                  size: 20,
                  color: iconColor,
                ),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: titleColor,
                  ),
                ),
                if (isSingleWeek) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: _singleWeekBorderColor.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '单周',
                      style: TextStyle(
                        fontSize: 10,
                        color: _singleWeekBorderColor,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const Divider(height: 24),
            ...items.map((item) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.label,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    item.value,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            )),
          ],
        ),
      ),
    );
  }

  /// 构建节次色块列表
  List<Widget> _buildPeriodCells(
    BuildContext context,
    SemesterClassroom classroom,
    String weekday,
    int currentWeek,
  ) {
    final allPeriods = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12];
    final courseBlocks = _analyzeCourseBlocks(classroom, weekday, currentWeek);
    final lastWeekCourseBlocks = currentWeek > 1
        ? _analyzeCourseBlocks(classroom, weekday, currentWeek - 1)
        : <int, Map<String, dynamic>>{};
    final blockColors = <String, Color>{};

    return allPeriods.map((period) {
      final blockInfo = courseBlocks[period];
      final hasCourse = blockInfo != null;
      final course = hasCourse ? blockInfo['course'] as CourseWithWeek : null;
      final isSingleWeek = course?.isSingleWeek ?? false;

      // 检查与上周是否不同
      final lastWeekBlockInfo = lastWeekCourseBlocks[period];
      final lastWeekCourse = lastWeekBlockInfo != null
          ? lastWeekBlockInfo['course'] as CourseWithWeek
          : null;
      final isDifferentFromLastWeek = hasCourse && (
        lastWeekCourse == null ||
        course!.name != lastWeekCourse.name ||
        course.teacher != lastWeekCourse.teacher
      );

      Color cellColor;

      if (hasCourse) {
        final blockId = blockInfo['blockId'] as String;
        if (!blockColors.containsKey(blockId)) {
          final baseColor = _getPeriodColor(blockInfo['firstPeriod'] as int);
          blockColors[blockId] = baseColor;
        }
        cellColor = blockColors[blockId]!;
      } else {
        cellColor = Colors.grey.shade200;
      }

      return Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 1),
          child: Stack(
            children: [
              Container(
                height: 32,
                decoration: BoxDecoration(
                  color: cellColor,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              // 左角标：与上周不同
              if (isDifferentFromLastWeek)
                Positioned(
                  left: 0,
                  top: 0,
                  child: CustomPaint(
                    size: const Size(10, 10),
                    painter: _TrianglePainter(
                      color: _leftBadgeColor,
                      direction: TriangleDirection.topLeft,
                    ),
                  ),
                ),
              // 右角标：单周课程
              if (isSingleWeek)
                Positioned(
                  right: 0,
                  top: 0,
                  child: CustomPaint(
                    size: const Size(10, 10),
                    painter: _TrianglePainter(
                      color: _rightBadgeColor,
                      direction: TriangleDirection.topRight,
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    }).toList();
  }

  /// 下载总览页面为图片
  Future<void> _downloadOverviewImage() async {
    try {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('正在生成图片...'), duration: Duration(seconds: 2)),
        );
      }

      final provider = context.read<AppProvider>();
      if (!provider.hasSemesterData) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('没有学期课表数据')),
          );
        }
        return;
      }

      // 使用 Canvas 绘制
      await _downloadWithCanvas();
    } catch (e) {
      debugPrint('Download error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('生成图片失败: $e')),
        );
      }
    }
  }

  /// 下载筛选后的总览图片
  Future<void> _downloadFilteredOverviewImage() async {
    try {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('正在生成图片...'), duration: Duration(seconds: 2)),
        );
      }

      final provider = context.read<AppProvider>();
      if (!provider.hasSemesterData) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('没有学期课表数据')),
          );
        }
        return;
      }

      // 使用 Canvas 绘制
      await _downloadWithCanvas(filtered: true);
    } catch (e) {
      debugPrint('Download error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('生成图片失败: $e')),
        );
      }
    }
  }

  /// 使用 Canvas 绘制图片
  /// [filtered] - true: 只下载在当前筛选类型下有课程的教室; false: 下载所有选中教室（包括无课的）
  Future<void> _downloadWithCanvas({bool filtered = false}) async {
    try {
      // 使用 watch 确保获取最新的 provider 状态
      final provider = Provider.of<AppProvider>(context, listen: false);
      final allClassrooms = provider.semesterClassrooms;
      final baseWeek = provider.selectedWeek;
      final currentWeekday = _weekdays[_selectedWeekday];
      // 周日显示下一周的数据（周日是一周第一天）
      final currentWeek = _getDisplayWeek(baseWeek, _selectedWeekday);

      // ignore: avoid_print
      print('[下载调试] 当前周次: $currentWeek, 当前星期: $currentWeekday');
      // ignore: avoid_print
      print('[下载调试] 选中分页: $_selectedPages');
      // ignore: avoid_print
      print('[下载调试] 选中教室: $_selectedClassrooms');
      // ignore: avoid_print
      print('[下载调试] 课程类型: $_selectedCourseTypes, 周次类型: $_selectedWeekTypes');

      // 获取页面实际显示宽度
      final screenWidth = MediaQuery.of(context).size.width;
      const scaleFactor = 2.5;

      // 应用分页筛选
      final pageFilteredClassrooms = _applyPageFilter(allClassrooms);

      // 根据 filtered 参数决定是否只保留有当前周课程的教室
      final List<SemesterClassroom> classroomsToDownload;
      if (filtered) {
        // 左侧按钮：只下载有当前周课程的教室
        classroomsToDownload = _filterClassroomsWithCourses(
          pageFilteredClassrooms,
          currentWeek,
          currentWeekday,
        );
      } else {
        // 右侧按钮：下载所有选中分页的教室（包括无课的）
        classroomsToDownload = pageFilteredClassrooms;
      }

      // 应用教室筛选
      final displayClassrooms = _applyClassroomFilter(classroomsToDownload);

      // 排序
      final sortedClassrooms = _getSortedClassrooms(displayClassrooms);

      // ignore: avoid_print
      print('[下载调试] 总教室数: ${allClassrooms.length}, 分页筛选后: ${pageFilteredClassrooms.length}');
      // ignore: avoid_print
      print('[下载调试] 教室筛选后: ${displayClassrooms.length}, 最终显示: ${sortedClassrooms.length}');
      // ignore: avoid_print
      print('[下载调试] 最终教室列表: ${sortedClassrooms.map((c) => c.name).toList()}');

      if (sortedClassrooms.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('没有符合条件的教室')),
          );
        }
        return;
      }

      final headers = ['教室', '1', '2', '3', '4', '5', '6', '7', '8', '9', '10', '11', '12'];
      final rows = <List<Map<String, dynamic>>>[];

      for (final classroom in sortedClassrooms) {
        final row = <Map<String, dynamic>>[];

        // 教室名称（只显示编号）
        final classroomNumber = classroom.name.replaceAll(RegExp(r'[^0-9]'), '');
        row.add({
          'text': classroomNumber,
          'color': null,
          'isClassroom': true,
        });

        // 分析课程块
        final courseBlocks = _analyzeCourseBlocks(classroom, currentWeekday, currentWeek);
        final blockColors = <String, Color>{};

        // 每个节次
        for (int period = 1; period <= 12; period++) {
          final courses = classroom.getCourses(currentWeekday, period);
          CourseWithWeek? activeCourse;
          for (final course in courses) {
            if (course.hasClassInWeek(currentWeek) &&
                _matchesCourseTypeFilter(course) &&
                _matchesWeekTypeFilter(course)) {
              activeCourse = course;
              break;
            }
          }

          Color? cellColor;
          bool isSingleWeek = false;

          if (activeCourse != null) {
            final blockInfo = courseBlocks[period];
            if (blockInfo != null) {
              final blockId = blockInfo['blockId'] as String;
              final firstPeriod = blockInfo['firstPeriod'] as int;

              if (!blockColors.containsKey(blockId)) {
                blockColors[blockId] = _getPeriodColor(firstPeriod);
              }
              cellColor = blockColors[blockId]!;
              isSingleWeek = activeCourse.isSingleWeek;
            }
          } else {
            cellColor = Colors.grey.shade300;
          }

          row.add({
            'text': '',
            'color': cellColor != null ? _getColorHex(cellColor) : null,
            'isClassroom': false,
            'isSingleWeek': isSingleWeek,
          });
        }

        rows.add(row);
      }

      final dataUrl = await _captureWithJS(headers, rows, currentWeekday, currentWeek, screenWidth, scaleFactor);

      if (dataUrl != null && mounted) {
        _showScreenshotPreview(dataUrl, currentWeekday, currentWeek);
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('截图失败')),
        );
      }
    } catch (e) {
      debugPrint('Canvas error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('截图失败: $e')),
        );
      }
    }
  }

  /// 使用 JavaScript Canvas 绘制截图，返回 data URL
  Future<String?> _captureWithJS(
    List<String> headers,
    List<List<Map<String, dynamic>>> rows,
    String weekday,
    int week,
    double screenWidth,
    double scaleFactor,
  ) async {
    try {
      // 在 Dart 中将数据转换为纯 JSON 字符串
      final headersJson = jsonEncode(headers);
      final rowsJson = jsonEncode(rows);

      // 执行 Canvas 绘制和下载（仅 Web 平台）
      if (!kIsWeb) return;
      
      js.context.callMethod('eval', ['''
        (function() {
          try {
            const headers = JSON.parse('$headersJson');
            const rows = JSON.parse('$rowsJson');
            const screenWidth = $screenWidth;
            const scale = $scaleFactor;
            const week = $week;

            // 尺寸配置 - 适配老人使用：大字体、大间距
            const pageHorizontalPadding = 8;
            const classroomColWidth = Math.floor(60 * scale);  // 教室列，按系数放大
            const numPeriods = headers.length - 1; // 12个节次

            // 可用宽度 = 屏幕宽度 - 左右padding - 教室列宽度
            const availableWidth = screenWidth - pageHorizontalPadding * 2 - classroomColWidth;
            // 每个节次列的宽度 = 可用宽度 / 12，按系数放大
            const periodColWidth = Math.floor(availableWidth / numPeriods * scale);

            // 大字体、大行高，适合老人阅读
            const headerHeight = Math.floor(36 * scale);   // 表头高度
            const rowHeight = Math.floor(32 * scale);      // 数据行高度（更大间距）
            const padding = Math.floor(16 * scale);        // 内边距
            const titleHeight = Math.floor(48 * scale);    // 标题高度

            const canvasWidth = classroomColWidth + periodColWidth * numPeriods + padding * 2;
            const canvasHeight = padding + titleHeight + headerHeight + rows.length * rowHeight + padding;

            const canvas = document.createElement('canvas');
            canvas.width = canvasWidth;
            canvas.height = canvasHeight;

            if (!canvas.getContext) {
              window.__screenshotError = 'getContext not supported';
              return;
            }
            const ctx = canvas.getContext('2d');
            if (!ctx) {
              window.__screenshotError = 'Failed to get 2d context';
              return;
            }

            // 白色背景
            ctx.fillStyle = '#ffffff';
            ctx.fillRect(0, 0, canvas.width, canvas.height);

            // 标题 - 大字体
            ctx.fillStyle = '#1a1a1a';
            ctx.font = 'bold ' + Math.floor(22 * scale) + 'px Arial, sans-serif';
            ctx.textAlign = 'center';
            ctx.fillText('学期总览 - $weekday 第' + week + '周', canvasWidth / 2, padding + Math.floor(30 * scale));

            let y = padding + titleHeight;

            // 表头背景
            ctx.fillStyle = '#e8e8e8';
            ctx.fillRect(padding, y, canvasWidth - padding * 2, headerHeight);

            // 表头文字 - 大字体
            ctx.fillStyle = '#333333';
            ctx.font = 'bold ' + Math.floor(14 * scale) + 'px Arial, sans-serif';
            ctx.textAlign = 'center';

            let x = padding;
            headers.forEach((header, i) => {
              const colWidth = i === 0 ? classroomColWidth : periodColWidth;
              ctx.fillText(header, x + colWidth / 2, y + headerHeight / 2 + Math.floor(5 * scale));
              x += colWidth;
            });

            y += headerHeight;

            // 数据行
            rows.forEach((row, rowIndex) => {
              // 行背景（交替色）
              ctx.fillStyle = rowIndex % 2 === 0 ? '#fafafa' : '#ffffff';
              ctx.fillRect(padding, y, canvasWidth - padding * 2, rowHeight);

              x = padding;

              row.forEach((cell, colIndex) => {
                const colWidth = colIndex === 0 ? classroomColWidth : periodColWidth;
                const cellText = cell.text || '';
                const cellColor = cell.color;
                const isClassroom = cell.isClassroom;
                const isSingleWeek = cell.isSingleWeek;

                // 绘制色块背景
                if (cellColor && cellColor !== '#000000' && cellColor !== 'null' && cellColor !== 'undefined') {
                  ctx.fillStyle = cellColor;
                  const blockPadding = Math.floor(1 * scale);
                  ctx.fillRect(
                    x + blockPadding,
                    y + blockPadding,
                    colWidth - blockPadding * 2,
                    rowHeight - blockPadding * 2
                  );
                }

                // 单元格边框
                ctx.strokeStyle = '#e0e0e0';
                ctx.lineWidth = scale;
                ctx.strokeRect(x, y, colWidth, rowHeight);

                // 单元格文字
                if (cellText && cellText.length > 0) {
                  // 根据背景颜色决定文字颜色
                  let textColor = '#ffffff';
                  if (!cellColor) {
                    textColor = '#333333';
                  } else {
                    // 浅色背景用深色字
                    const hex = cellColor.replace('#', '');
                    const r = parseInt(hex.substr(0, 2), 16);
                    const g = parseInt(hex.substr(2, 2), 16);
                    const b = parseInt(hex.substr(4, 2), 16);
                    const luminance = (0.299 * r + 0.587 * g + 0.114 * b) / 255;
                    textColor = luminance > 0.5 ? '#333333' : '#ffffff';
                  }

                  ctx.fillStyle = textColor;
                  // 教室列用更大字体，课程格用中等字体
                  const fontSize = isClassroom ? Math.floor(13 * scale) : Math.floor(11 * scale);
                  ctx.font = isClassroom ? 'bold ' + fontSize + 'px Arial, sans-serif' : fontSize + 'px Arial, sans-serif';
                  ctx.textAlign = 'center';

                  // 文字截断
                  let displayText = cellText;
                  const maxWidth = colWidth - Math.floor(8 * scale);
                  if (ctx.measureText(displayText).width > maxWidth) {
                    while (ctx.measureText(displayText + '..').width > maxWidth && displayText.length > 0) {
                      displayText = displayText.slice(0, -1);
                    }
                    displayText += '..';
                  }
                  ctx.fillText(displayText, x + colWidth / 2, y + rowHeight / 2 + Math.floor(4 * scale));
                }

                x += colWidth;
              });

              y += rowHeight;
            });

            // 存储到全局变量
            const dataUrl = canvas.toDataURL('image/png');
            if (!dataUrl || dataUrl.length < 100) {
              window.__screenshotError = 'toDataURL failed';
              return;
            }
            window.__screenshotResult = dataUrl;
          } catch (e) {
            window.__screenshotError = String(e);
          }
        })()
      ''']);

      // 轮询等待结果
      for (int i = 0; i < 30; i++) {
        await Future.delayed(const Duration(milliseconds: 100));

        final error = js.context['__screenshotError'];
        if (error != null && error.toString().isNotEmpty) {
          debugPrint('Screenshot error: $error');
          js.context['__screenshotError'] = null;
          js.context['__screenshotResult'] = null;
          return null;
        }

        final result = js.context['__screenshotResult'];
        if (result != null && result.toString().isNotEmpty) {
          final dataUrl = result.toString();
          debugPrint('Screenshot success, length: \${dataUrl.length}');
          js.context['__screenshotResult'] = null;
          js.context['__screenshotError'] = null;
          return dataUrl;
        }
      }

      debugPrint('Screenshot timeout');
      return null;
    } catch (e) {
      debugPrint('_captureWithJS error: $e');
      return null;
    }
  }

  /// 将 Color 转换为 Hex 字符串
  String _getColorHex(Color color) {
    // 使用value属性获取ARGB值，然后提取RGB
    final value = color.value;
    final r = (value >> 16) & 0xFF;
    final g = (value >> 8) & 0xFF;
    final b = value & 0xFF;
    return '#${r.toRadixString(16).padLeft(2, '0')}${g.toRadixString(16).padLeft(2, '0')}${b.toRadixString(16).padLeft(2, '0')}'.toUpperCase();
  }

  /// 显示截图预览对话框
  void _showScreenshotPreview(String dataUrl, String weekday, int week) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => _SemesterScreenshotPreviewDialog(
        dataUrl: dataUrl,
        weekday: weekday,
        week: week,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('学期总览'),
        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
        leading: IconButton(
          icon: const Icon(Icons.filter_alt_outlined),
          tooltip: '下载筛选图片（当前类型有课的教室）',
          onPressed: _isCapturing ? null : _downloadFilteredOverviewImage,
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
          // 汇总按钮
          IconButton(
            icon: const Icon(Icons.summarize),
            tooltip: '汇总课程/老师',
            onPressed: _showSummaryDialog,
          ),
          // 周次选择器
          Consumer<AppProvider>(
            builder: (context, provider, _) {
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: DropdownButton<int>(
                  value: provider.selectedWeek,
                  hint: const Text('选择周次'),
                  items: List.generate(18, (index) {
                    final week = index + 1;
                    return DropdownMenuItem(
                      value: week,
                      child: Text('第$week周'),
                    );
                  }),
                  onChanged: (value) {
                    if (value != null) {
                      provider.setSelectedWeek(value);
                      setState(() {
                        _searchResults = [];
                      });
                    }
                  },
                  dropdownColor: Theme.of(context).colorScheme.surface,
                ),
              );
            },
          ),
          // 下载全部按钮
          IconButton(
            icon: const Icon(Icons.download),
            tooltip: '下载全部图片',
            onPressed: _isCapturing ? null : _downloadOverviewImage,
          ),
        ],
      ),
      body: Consumer<AppProvider>(
        builder: (context, provider, _) {
          if (!provider.hasSemesterData) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.calendar_today_outlined,
                      size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text('暂无学期课表数据',
                      style: TextStyle(fontSize: 18, color: Colors.grey)),
                  SizedBox(height: 8),
                  Text('请在查看页面导入整学期课表',
                      style: TextStyle(color: Colors.grey)),
                ],
              ),
            );
          }

          final allClassrooms = provider.semesterClassrooms;
          final baseWeek = provider.selectedWeek;
          final currentWeekday = _weekdays[_selectedWeekday];
          // 周日显示下一周的数据（周日是一周第一天）
          final currentWeek = _getDisplayWeek(baseWeek, _selectedWeekday);

          // 获取有数据的分页列表
          final availablePages = _getAvailablePages(allClassrooms);

          // 如果当前选中的分页不在可用列表中，重置为默认值
          if (availablePages.isNotEmpty) {
            final validSelections = _selectedPages.where((p) => availablePages.contains(p)).toSet();
            if (validSelections.isEmpty) {
              // 如果没有有效的选中分页，默认选中第一个可用分页
              _selectedPages = {availablePages.first};
            } else if (validSelections.length != _selectedPages.length) {
              // 如果有些选中的分页已不可用，更新为有效的分页
              _selectedPages = validSelections;
            }
          }

          // 应用分页筛选
          final pageFilteredClassrooms = _applyPageFilter(allClassrooms);

          // 应用教室筛选（不再筛选掉没有当前周课程的教室，让下载按钮能显示正确的教室）
          final displayClassrooms = _applyClassroomFilter(pageFilteredClassrooms);

          // 排序
          final sortedClassrooms = _getSortedClassrooms(displayClassrooms);

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
                      hintText: '搜索课程或老师（跨周搜索）...',
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
                      _performSearch(value, allClassrooms);
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
                          '${result.weekday} 第${result.period}节 | 第${result.week}周 | ${result.course.teacher ?? "无老师"}',
                        ),
                        onTap: () {
                          // 关闭搜索框
                          setState(() {
                            _selectedWeekday = _weekdays.indexOf(result.weekday);
                            _showSearchBox = false;
                            _searchController.clear();
                            _searchResults = [];
                          });
                          // 切换到对应周次
                          provider.setSelectedWeek(result.week);
                          // 显示课程详情对话框
                          _showCourseDetailDialog(
                            result.course,
                            result.period,
                            result.weekday,
                            result.classroom.name,
                          );
                        },
                      );
                    },
                  ),
                ),

              // 星期选择器
              Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: List.generate(7, (index) {
                    final isSelected = _selectedWeekday == index;
                    return InkWell(
                      onTap: () => setState(() => _selectedWeekday = index),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? Theme.of(context).colorScheme.primary
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          _weekdays[index].replaceAll('星期', '周'),
                          style: TextStyle(
                            color: isSelected ? Colors.white : null,
                            fontWeight:
                                isSelected ? FontWeight.bold : null,
                          ),
                        ),
                      ),
                    );
                  }),
                ),
              ),

              // 筛选栏
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: Column(
                  children: [
                    // 筛选栏标题 + 折叠按钮
                    InkWell(
                      onTap: () => setState(() => _isFilterExpanded = !_isFilterExpanded),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            _isFilterExpanded ? Icons.expand_less : Icons.expand_more,
                            size: 20,
                            color: Colors.grey.shade600,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _isFilterExpanded ? '收起筛选' : '展开筛选',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade600,
                            ),
                          ),
                          const SizedBox(width: 4),
                          // 显示当前筛选状态摘要
                          if (!_isFilterExpanded) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.purple.shade100,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                '${_selectedPages.length}个分页',
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
                                '${_selectedCourseTypes.length}种类型',
                                style: const TextStyle(fontSize: 11),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    // 展开的筛选内容
                    if (_isFilterExpanded) ...[
                      const SizedBox(height: 8),
                      // 第一行：分页筛选（只显示有数据的分页）
                      Wrap(
                        spacing: 8,
                        alignment: WrapAlignment.center,
                        children: availablePages.map((pageName) {
                          return FilterChip(
                            label: Text(pageName),
                            selected: _selectedPages.contains(pageName),
                            onSelected: (_) => _togglePage(pageName),
                            selectedColor: Colors.purple.shade100,
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 8),
                      // 第二行：课程类型 + 周次类型 + 教室筛选
                      Wrap(
                        spacing: 8,
                        alignment: WrapAlignment.center,
                        children: [
                          FilterChip(
                            label: const Text('研究生'),
                            selected: _selectedCourseTypes.contains('graduate'),
                            onSelected: (_) => _toggleCourseType('graduate'),
                            selectedColor: Colors.blue.shade100,
                          ),
                          FilterChip(
                            label: const Text('本科'),
                            selected:
                                _selectedCourseTypes.contains('undergraduate'),
                            onSelected: (_) => _toggleCourseType('undergraduate'),
                            selectedColor: Colors.green.shade100,
                          ),
                          FilterChip(
                            label: const Text('借用'),
                            selected: _selectedCourseTypes.contains('borrowed'),
                            onSelected: (_) => _toggleCourseType('borrowed'),
                            selectedColor: Colors.orange.shade100,
                          ),
                          FilterChip(
                            label: const Text('单周'),
                            selected: _selectedWeekTypes.contains('single'),
                            onSelected: (_) => _toggleWeekType('single'),
                            selectedColor: Colors.red.shade100,
                          ),
                          FilterChip(
                            label: const Text('连续周'),
                            selected: _selectedWeekTypes.contains('continuous'),
                            onSelected: (_) => _toggleWeekType('continuous'),
                            selectedColor: Colors.teal.shade100,
                          ),
                          ActionChip(
                            label: Text(
                              _selectedClassrooms.isEmpty
                                  ? '教室'
                                  : '教室(${_selectedClassrooms.length})',
                            ),
                            avatar: const Icon(Icons.meeting_room, size: 18),
                            onPressed: () =>
                                _showClassroomFilterDialog(allClassrooms),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),

              // 课表表头（节次）
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                color: Colors.grey.shade100,
                child: Row(
                  children: [
                    const SizedBox(width: 60),
                    ...List.generate(12, (i) {
                      final period = i + 1;
                      return Expanded(
                        child: Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 4, vertical: 2),
                            decoration: BoxDecoration(
                              color: _getPeriodColor(period),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              '$period',
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                  ],
                ),
              ),

              // 教室列表
              Expanded(
                child: sortedClassrooms.isEmpty
                    ? const Center(
                        child: Text(
                          '没有符合条件的教室',
                          style: TextStyle(color: Colors.grey),
                        ),
                      )
                    : RepaintBoundary(
                        key: _screenshotKey,
                        child: ListView.builder(
                          padding: const EdgeInsets.all(8),
                          itemCount: sortedClassrooms.length,
                          itemBuilder: (context, index) {
                            final classroom = sortedClassrooms[index];
                            final classroomNumber = classroom.name
                                .replaceAll(RegExp(r'[^0-9]'), '');

                            return Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                border: Border(
                                  bottom:
                                      BorderSide(color: Colors.grey.shade200),
                                ),
                              ),
                              child: Row(
                                children: [
                                  GestureDetector(
                                    onTap: () => _showClassroomDetailDialog(
                                      classroom,
                                      currentWeekday,
                                      currentWeek,
                                    ),
                                    child: SizedBox(
                                      width: 60,
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            classroomNumber,
                                            style: TextStyle(
                                              fontSize: 15,
                                              fontWeight: FontWeight.bold,
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .primary,
                                              decoration:
                                                  TextDecoration.underline,
                                              decorationColor:
                                                  Theme.of(context)
                                                      .colorScheme
                                                      .primary,
                                            ),
                                            textAlign: TextAlign.center,
                                          ),
                                          if (classroom.capacity != null)
                                            Text(
                                              '${classroom.capacity}人',
                                              style: TextStyle(
                                                fontSize: 11,
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
                                    currentWeekday,
                                    currentWeek,
                                  ),
                                ],
                              ),
                            );
                          },
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

/// 信息项数据类
class _InfoItem {
  final String label;
  final String value;

  _InfoItem(this.label, this.value);
}

/// 搜索结果数据类
class _SearchResult {
  final SemesterClassroom classroom;
  final String weekday;
  final int period;
  final int week;
  final CourseWithWeek course;
  final String matchType; // 'teacher' 或 'course'

  _SearchResult({
    required this.classroom,
    required this.weekday,
    required this.period,
    required this.week,
    required this.course,
    required this.matchType,
  });
}

/// 汇总结果数据类
class _SummaryItem {
  final CourseWithWeek course;
  final String classroom;
  final String weekday;
  final int period;
  final int week;
  final bool isTeacherQuery;

  _SummaryItem({
    required this.course,
    required this.classroom,
    required this.weekday,
    required this.period,
    required this.week,
    required this.isTeacherQuery,
  });
}

/// 学期总览截图预览对话框
class _SemesterScreenshotPreviewDialog extends StatefulWidget {
  final String dataUrl;
  final String weekday;
  final int week;

  const _SemesterScreenshotPreviewDialog({
    required this.dataUrl,
    required this.weekday,
    required this.week,
  });

  @override
  State<_SemesterScreenshotPreviewDialog> createState() => _SemesterScreenshotPreviewDialogState();
}

class _SemesterScreenshotPreviewDialogState extends State<_SemesterScreenshotPreviewDialog> {
  bool _isSharing = false;

  Future<void> _shareImage() async {
    setState(() => _isSharing = true);
    try {
      final dataUrlEscaped = widget.dataUrl.replaceAll("'", "\\'");
      final filename = '学期总览_${widget.weekday}_第${widget.week}周.png';
      final title = '学期总览 ${widget.weekday} 第${widget.week}周';

      // iOS Safari 上使用 Web Share API
      final script = '''
        (async function() {
          const ua = navigator.userAgent.toLowerCase();
          const isIOS = /iphone|ipad|ipod/.test(ua);
          const isSafari = /safari/.test(ua) && !/chrome/.test(ua) && !/edge/.test(ua);

          // 如果支持 Web Share API，尝试分享
          if (navigator.share && isIOS) {
            try {
              // 将 dataUrl 转换为 blob
              const response = await fetch('$dataUrlEscaped');
              const blob = await response.blob();
              const file = new File([blob], '$filename', { type: 'image/png' });

              if (navigator.canShare && navigator.canShare({ files: [file] })) {
                await navigator.share({
                  files: [file],
                  title: '$title',
                });
                window.flutterShareResult = 'shared';
              } else {
                // 不支持分享文件，回退到下载
                downloadImage();
                window.flutterShareResult = 'downloaded';
              }
            } catch (e) {
              if (e.name !== 'AbortError') {
                downloadImage();
                window.flutterShareResult = 'downloaded';
              }
            }
          } else {
            // 非 iOS Safari 或不支持分享，直接下载
            downloadImage();
            window.flutterShareResult = 'downloaded';
          }

          function downloadImage() {
            const link = document.createElement('a');
            link.href = '$dataUrlEscaped';
            link.download = '$filename';
            link.style.display = 'none';
            document.body.appendChild(link);
            link.click();
            document.body.removeChild(link);
          }
        })();
      ''';

      js.context.callMethod('eval', [script]);

      // 等待结果
      await Future.delayed(const Duration(milliseconds: 1000));

      final result = js.context['flutterShareResult'] as String?;

      if (mounted && result != null) {
        switch (result) {
          case 'shared':
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('分享成功！')),
            );
            break;
          case 'downloaded':
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('图片已开始下载')),
            );
            break;
        }
        js.context['flutterShareResult'] = null;
      }
    } catch (e) {
      debugPrint('Share error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('分享失败，请尝试长按图片保存')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSharing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
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
                Text(
                  '学期总览 - ${widget.weekday} 第${widget.week}周',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                // 分享按钮
                IconButton(
                  icon: _isSharing
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.share),
                  tooltip: '分享图片',
                  onPressed: _isSharing ? null : _shareImage,
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
              child: _NativeImageView(dataUrl: widget.dataUrl),
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
    );
  }
}

/// 使用原生 HTML img 标签显示图片，使浏览器长按可弹出保存菜单
class _NativeImageView extends StatefulWidget {
  final String dataUrl;
  const _NativeImageView({required this.dataUrl});

  @override
  State<_NativeImageView> createState() => _NativeImageViewState();
}

class _NativeImageViewState extends State<_NativeImageView> {
  late String _viewId;

  @override
  void initState() {
    super.initState();
    _viewId = 'native-img-${widget.dataUrl.hashCode}-${DateTime.now().millisecondsSinceEpoch}';
    _registerView();
  }

  @override
  void didUpdateWidget(_NativeImageView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.dataUrl != widget.dataUrl) {
      // dataUrl 变化了，重新注册视图
      _viewId = 'native-img-${widget.dataUrl.hashCode}-${DateTime.now().millisecondsSinceEpoch}';
      _registerView();
    }
  }

  void _registerView() {
    // 注册原生 HTML img 元素
    final dataUrlEscaped = widget.dataUrl.replaceAll("'", "\\'");
    js.context.callMethod('eval', ['''
      (function() {
        if (typeof window._flutterImgRegistry === "undefined") {
          window._flutterImgRegistry = {};
        }
        window._flutterImgRegistry["$_viewId"] = "$dataUrlEscaped";
      })();
    ''']);

    // ignore: undefined_prefixed_name
    ui.platformViewRegistry.registerViewFactory(_viewId, (int viewId) {
      final img = html.ImageElement()
        ..src = widget.dataUrl
        ..style.width = '100%'
        ..style.height = '100%'
        ..style.objectFit = 'contain'
        ..style.display = 'block'
        ..draggable = false;
      return img;
    });
  }

  @override
  Widget build(BuildContext context) {
    return HtmlElementView(viewType: _viewId);
  }
}

/// 三角形方向
enum TriangleDirection {
  topLeft,
  topRight,
}

/// 三角形角标绘制器
class _TrianglePainter extends CustomPainter {
  final Color color;
  final TriangleDirection direction;

  _TrianglePainter({
    required this.color,
    required this.direction,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final path = Path();

    if (direction == TriangleDirection.topLeft) {
      // 左上角三角形
      path
        ..moveTo(0, 0)
        ..lineTo(size.width, 0)
        ..lineTo(0, size.height)
        ..close();
    } else {
      // 右上角三角形
      path
        ..moveTo(0, 0)
        ..lineTo(size.width, 0)
        ..lineTo(size.width, size.height)
        ..close();
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
