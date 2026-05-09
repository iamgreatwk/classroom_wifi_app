import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models/course_with_week.dart';
import '../providers/app_provider.dart';

// 删除的 Web 相关代码包括：
// - _downloadWithCanvas 方法
// - _captureWithJS 方法
// - _showScreenshotPreview 方法
// - _getColorHex 方法
// - _SemesterScreenshotPreviewDialog 类
// - _NativeImageView 类



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

  /// 分析第7、8节课程并复制到粘贴板
  /// 筛选第7、8节老师不同的课程，生成格式：
  /// "15：40 需要优先擦黑板的教室有：xxx、xxx、xxx"
  /// 对于7、8节老师相同、课程不同的情况，追加：
  /// "另外，xxx、xxx教室课程变化但老师不变，按老师要求擦黑板"
  void _copyBlackboardText(AppProvider provider) {
    final currentWeekday = _weekdays[_selectedWeekday];
    final baseWeek = provider.selectedWeek;
    final currentWeek = _getDisplayWeek(baseWeek, _selectedWeekday);
    final classrooms = provider.semesterClassrooms;
    final selectedPages = provider.semesterSelectedPages;
    final selectedClassrooms = provider.semesterSelectedClassrooms;

    // 筛选有第7、8节课程的教室
    final teacherDifferentClassrooms = <String>[]; // 老师不同的教室
    final courseDifferentClassrooms = <String>[];  // 课程不同但老师相同的教室

    for (final classroom in classrooms) {
      // 应用分页筛选
      final isInSelectedPage = selectedPages.any(
        (page) => _isClassroomInPage(classroom.name, page),
      );
      if (!isInSelectedPage) continue;

      // 应用教室筛选
      if (selectedClassrooms.isNotEmpty &&
          !selectedClassrooms.contains(classroom.name)) {
        continue;
      }

      // 获取第7、8节的课程（考虑当前周次）
      final period7Courses = classroom.getCourses(currentWeekday, 7);
      final period8Courses = classroom.getCourses(currentWeekday, 8);

      // 找出在当前周有效的课程
      CourseWithWeek? activePeriod7Course;
      CourseWithWeek? activePeriod8Course;

      for (final course in period7Courses) {
        if (course.hasClassInWeek(currentWeek) &&
            _matchesCourseTypeFilter(course, provider) &&
            _matchesWeekTypeFilter(course, provider)) {
          activePeriod7Course = course;
          break;
        }
      }

      for (final course in period8Courses) {
        if (course.hasClassInWeek(currentWeek) &&
            _matchesCourseTypeFilter(course, provider) &&
            _matchesWeekTypeFilter(course, provider)) {
          activePeriod8Course = course;
          break;
        }
      }

      // 两个节次都有课才进行比较
      if (activePeriod7Course != null && activePeriod8Course != null) {
        final teacher7 = activePeriod7Course.teacher ?? '';
        final teacher8 = activePeriod8Course.teacher ?? '';
        final course7 = activePeriod7Course.name;
        final course8 = activePeriod8Course.name;

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

  /// 获取节次对应的固定颜色
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

  /// 获取课程对应的颜色（根据节次）
  Color _getCourseColor(CourseWithWeek course, int period) {
    return _getPeriodColor(period);
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
  bool _matchesCourseTypeFilter(CourseWithWeek course, AppProvider provider) {
    final selectedCourseTypes = provider.semesterCourseTypes;
    if (selectedCourseTypes.isEmpty) return true;

    final isGraduate = _isGraduateCourse(course);
    final isBorrowed = _isBorrowedCourse(course);
    final isUndergraduate = !isBorrowed && !isGraduate;

    if (selectedCourseTypes.contains('graduate') && isGraduate) return true;
    if (selectedCourseTypes.contains('undergraduate') && isUndergraduate)
      return true;
    if (selectedCourseTypes.contains('borrowed') && isBorrowed) return true;

    return false;
  }

  /// 判断课程是否匹配周次类型筛选
  bool _matchesWeekTypeFilter(CourseWithWeek course, AppProvider provider) {
    final selectedWeekTypes = provider.semesterSelectedWeekTypes;
    if (selectedWeekTypes.isEmpty) return true;
    if (selectedWeekTypes.length == 2) return true;
    if (selectedWeekTypes.contains('single') && course.isSingleWeek) return true;
    if (selectedWeekTypes.contains('continuous') && !course.isSingleWeek)
      return true;
    return false;
  }

  /// 切换课程类型筛选（使用 Provider）
  void _toggleCourseType(String type, AppProvider provider) {
    provider.toggleSemesterCourseType(type);
  }

  /// 切换分页筛选（使用 Provider）
  void _togglePage(String pageName, AppProvider provider) {
    provider.toggleSemesterPage(pageName);
  }

  /// 切换周次类型筛选（使用 Provider）
  void _toggleWeekType(String type, AppProvider provider) {
    provider.toggleSemesterWeekType(type);
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
      List<SemesterClassroom> classrooms, AppProvider provider) {
    final selectedPages = provider.semesterSelectedPages;
    if (selectedPages.isEmpty) return classrooms;
    return classrooms.where((c) {
      return selectedPages.any((page) => _isClassroomInPage(c.name, page));
    }).toList();
  }

  /// 应用教室筛选
  List<SemesterClassroom> _applyClassroomFilter(
      List<SemesterClassroom> classrooms, AppProvider provider) {
    final selectedClassrooms = provider.semesterSelectedClassrooms;
    if (selectedClassrooms.isEmpty) {
      return classrooms;
    }
    return classrooms.where((c) => selectedClassrooms.contains(c.name)).toList();
  }

  /// 筛选：只保留在当前周和选中类型下有课的教室
  List<SemesterClassroom> _filterClassroomsWithCourses(
    List<SemesterClassroom> classrooms,
    int currentWeek,
    String weekday,
    AppProvider provider,
  ) {
    return classrooms.where((classroom) {
      for (int period = 1; period <= 12; period++) {
        final courses = classroom.getCourses(weekday, period);
        for (final course in courses) {
          if (course.hasClassInWeek(currentWeek) &&
              _matchesCourseTypeFilter(course, provider) &&
              _matchesWeekTypeFilter(course, provider)) {
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
    AppProvider provider,
  ) {
    return classrooms.where((classroom) {
      for (int period = 1; period <= 12; period++) {
        final courses = classroom.getCourses(weekday, period);
        for (final course in courses) {
          if (_matchesCourseTypeFilter(course, provider) &&
              _matchesWeekTypeFilter(course, provider)) {
            return true;
          }
        }
      }
      return false;
    }).toList();
  }

  /// 显示教室筛选对话框
  void _showClassroomFilterDialog(List<SemesterClassroom> allClassrooms, AppProvider provider) {
    final tempSelected = Set<String>.from(provider.semesterSelectedClassrooms);
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
                    provider.setSemesterSelectedClassrooms(tempSelected);
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
    AppProvider provider,
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
            _matchesCourseTypeFilter(course, provider) &&
            _matchesWeekTypeFilter(course, provider)) {
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
    final selectedPages = provider.semesterSelectedPages;
    final selectedClassrooms = provider.semesterSelectedClassrooms;

    // 遍历所有星期和周次进行搜索
    for (int week = 1; week <= 18; week++) {
      for (final day in _weekdays) {
        for (final classroom in classrooms) {
          // 筛选：检查教室是否在选中的分页中
          final isInSelectedPage = selectedPages.any(
            (page) => _isClassroomInPage(classroom.name, page),
          );
          if (!isInSelectedPage) continue;

          // 筛选：检查教室是否在勾选的教室列表中
          if (selectedClassrooms.isNotEmpty &&
              !selectedClassrooms.contains(classroom.name)) {
            continue;
          }

          for (int period = 1; period <= 12; period++) {
            final courses = classroom.getCourses(day, period);
            for (final course in courses) {
              if (!course.hasClassInWeek(week)) continue;
              if (!_matchesCourseTypeFilter(course, provider)) continue;
              if (!_matchesWeekTypeFilter(course, provider)) continue;

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
    final selectedPages = provider.semesterSelectedPages;
    final selectedClassrooms = provider.semesterSelectedClassrooms;

    // 遍历所有数据汇总（不筛选周数，显示整个学期）
    for (int week = 1; week <= 18; week++) {
      for (final day in _weekdays) {
        for (final classroom in classrooms) {
          // 应用筛选条件（分页、教室、课程类型、周次类型）
          final isInSelectedPage = selectedPages.any(
            (page) => _isClassroomInPage(classroom.name, page),
          );
          if (!isInSelectedPage) continue;
          if (selectedClassrooms.isNotEmpty &&
              !selectedClassrooms.contains(classroom.name)) {
            continue;
          }

          for (int period = 1; period <= 12; period++) {
            final courses = classroom.getCourses(day, period);
            for (final course in courses) {
              // 汇总不筛选周数，显示整个学期的课程
              if (!_matchesCourseTypeFilter(course, provider)) continue;
              if (!_matchesWeekTypeFilter(course, provider)) continue;

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
    final provider = context.read<AppProvider>();

    for (int period = 1; period <= 12; period++) {
      final courses = classroom.getCourses(weekday, period);
      CourseWithWeek? activeCourse;
      for (final course in courses) {
        if (course.hasClassInWeek(currentWeek) &&
            _matchesCourseTypeFilter(course, provider) &&
            _matchesWeekTypeFilter(course, provider)) {
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
    final provider = context.read<AppProvider>();
    final courseBlocks = _analyzeCourseBlocks(classroom, weekday, currentWeek, provider);
    final lastWeekCourseBlocks = currentWeek > 1
        ? _analyzeCourseBlocks(classroom, weekday, currentWeek - 1, provider)
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

      // iOS: 使用 RepaintBoundary 截图
      await _downloadWithRepaintBoundary();
    } catch (e) {
      debugPrint('Download error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('生成图片失败: $e')),
        );
      }
    }
  }

  /// 下载筛选后的总览图片（仅包含有课的教室）
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

      // iOS: 使用 RepaintBoundary 截图
      await _downloadWithRepaintBoundary(filtered: true);
    } catch (e) {
      debugPrint('Download error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('生成图片失败: $e')),
        );
      }
    }
  }

  /// iOS/Android: 使用 RepaintBoundary 截图
  /// [filtered] - true: 只下载在当前筛选类型和周次下有课程的教室; false: 下载所有选中教室（包括无课的）
  Future<void> _downloadWithRepaintBoundary({bool filtered = false}) async {
    try {
      final provider = context.read<AppProvider>();
      final baseWeek = provider.selectedWeek;
      final currentWeekday = _weekdays[_selectedWeekday];
      final currentWeek = _getDisplayWeek(baseWeek, _selectedWeekday);

      // 获取要截图的教室列表
      List<SemesterClassroom> classroomsToCapture;

      // 先获取所有分页和教室筛选后的列表
      final allClassrooms = provider.semesterClassrooms;
      final pageFiltered = _applyPageFilter(allClassrooms, provider);
      final classroomFiltered = _applyClassroomFilter(pageFiltered, provider);

      if (filtered) {
        // 左侧按钮：只下载在当前周和选中类型下有课程的教室
        classroomsToCapture = classroomFiltered.where((classroom) {
          for (int period = 1; period <= 12; period++) {
            final courses = classroom.getCourses(currentWeekday, period);
            for (final course in courses) {
              if (course.hasClassInWeek(currentWeek) &&
                  _matchesCourseTypeFilter(course, provider) &&
                  _matchesWeekTypeFilter(course, provider)) {
                return true;
              }
            }
          }
          return false;
        }).toList();
      } else {
        // 右侧按钮：下载所有分页中的教室（不受教室筛选影响，包括无课的）
        classroomsToCapture = pageFiltered;
      }

      if (classroomsToCapture.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('没有符合条件的教室')),
          );
        }
        return;
      }

      // 显示截图预览对话框（使用临时构建的Widget）
      if (mounted) {
        await _showMobileScreenshotPreviewWithClassrooms(
          classroomsToCapture,
          currentWeekday,
          currentWeek,
        );
      }
    } catch (e) {
      debugPrint('RepaintBoundary capture error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('截图失败: $e')),
        );
      }
    }
  }

  /// 使用指定教室列表显示移动端截图预览
  Future<void> _showMobileScreenshotPreviewWithClassrooms(
    List<SemesterClassroom> classrooms,
    String currentWeekday,
    int currentWeek,
  ) async {
    // 构建截图Widget
    final screenshotWidget = _buildScreenshotWidget(
      classrooms,
      currentWeekday,
      currentWeek,
    );

    // 创建一个临时GlobalKey来截图
    final screenshotKey = GlobalKey();

    // 显示对话框并截图
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
                      '学期总览 - $currentWeekday 第$currentWeek周',
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
            // 截图区域 - 可滚动查看所有教室
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
                    child: screenshotWidget,
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
                      final imageBytes = await _captureWidgetToImageWithKey(screenshotKey);
                      if (imageBytes != null) {
                        await _shareImageBytes(
                          imageBytes,
                          '学期总览_${currentWeekday}_第${currentWeek}周.png',
                        );
                      }
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

  /// 使用指定的GlobalKey截图
  Future<Uint8List?> _captureWidgetToImageWithKey(GlobalKey key) async {
    try {
      final RenderRepaintBoundary? boundary =
          key.currentContext?.findRenderObject() as RenderRepaintBoundary?;

      if (boundary == null) {
        debugPrint('RenderRepaintBoundary not found');
        return null;
      }

      if (!boundary.hasSize || boundary.size.isEmpty) {
        debugPrint('Boundary has no size');
        return null;
      }

      final ui.Image image = await boundary.toImage(pixelRatio: 2.0);
      final ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);

      if (byteData == null) {
        debugPrint('Failed to convert image to byte data');
        return null;
      }

      return byteData.buffer.asUint8List();
    } catch (e, stackTrace) {
      debugPrint('Error capturing widget: $e');
      debugPrint(stackTrace.toString());
      return null;
    }
  }

  /// 构建截图用的Widget - 参照参考图片样式（老年人友好，紧凑布局）
  Widget _buildScreenshotWidget(
    List<SemesterClassroom> classrooms,
    String currentWeekday,
    int currentWeek,
  ) {
    final sortedClassrooms = _getSortedClassrooms(classrooms);

    // 参照原图样式配置
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
            '$currentWeekday总览 - 第$currentWeek周',
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
                    context,
                    classroom,
                    currentWeekday,
                    currentWeek,
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
    BuildContext context,
    SemesterClassroom classroom,
    String weekday,
    int currentWeek,
  ) {
    // 分析课程块，确保同一连续课程使用相同颜色
    final provider = context.read<AppProvider>();
    final courseBlocks = _analyzeCourseBlocks(classroom, weekday, currentWeek, provider);
    final blockColors = <String, Color>{};

    return List.generate(12, (i) {
      final period = i + 1;
      final blockInfo = courseBlocks[period];

      Color cellColor;
      if (blockInfo == null) {
        // 无课使用浅灰色
        cellColor = Colors.grey.shade300;
      } else {
        final blockId = blockInfo['blockId'] as String;
        final firstPeriod = blockInfo['firstPeriod'] as int;

        if (!blockColors.containsKey(blockId)) {
          blockColors[blockId] = _getPeriodColor(firstPeriod);
        }
        cellColor = blockColors[blockId]!;
      }

      return Expanded(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 1, vertical: 2),
          decoration: BoxDecoration(
            color: cellColor,
            borderRadius: BorderRadius.circular(1),
          ),
        ),
      );
    });
  }

  /// 显示移动端截图预览对话框
  void _showMobileScreenshotPreview(Uint8List imageBytes) {
    final currentWeekday = _weekdays[_selectedWeekday];
    final provider = context.read<AppProvider>();
    final currentWeek = _getDisplayWeek(provider.selectedWeek, _selectedWeekday);

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
                      '学期总览 - $currentWeekday 第$currentWeek周',
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
                    onPressed: () => _shareImageBytes(
                      imageBytes,
                      '学期总览_${currentWeekday}_第${currentWeek}周.png',
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

  /// 使用 RepaintBoundary 捕获 Widget 为 PNG 图片
  Future<Uint8List?> _captureWidgetToImage() async {
    try {
      final RenderRepaintBoundary? boundary =
          _screenshotKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;

      if (boundary == null) {
        debugPrint('RenderRepaintBoundary not found');
        return null;
      }

      if (!boundary.hasSize || boundary.size.isEmpty) {
        debugPrint('Boundary has no size');
        return null;
      }

      final ui.Image image = await boundary.toImage(pixelRatio: 2.0);
      final ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);

      if (byteData == null) {
        debugPrint('Failed to convert image to byte data');
        return null;
      }

      return byteData.buffer.asUint8List();
    } catch (e, stackTrace) {
      debugPrint('Error capturing widget: $e');
      debugPrint(stackTrace.toString());
      return null;
    }
  }

  /// 保存图片到相册或分享
  Future<void> _saveImageToGallery(Uint8List imageBytes, String filename) async {
    // 简化处理：提示用户截图成功，实际保存需要 share_plus 或 photo_manager 插件
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('图片已生成 (${(imageBytes.length / 1024).toStringAsFixed(1)} KB)，请使用系统分享保存')),
      );
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

  // Web 相关代码已删除：
  // - _downloadWithCanvas 方法
  // - _captureWithJS 方法
  // - _getColorHex 方法
  // - _showScreenshotPreview 方法
  // - _SemesterScreenshotPreviewDialog 类
  // - _NativeImageView 类

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
          // 复制黑板提示按钮
          IconButton(
            icon: const Icon(Icons.content_copy),
            tooltip: '复制7、8节黑板提示',
            onPressed: () => _copyBlackboardText(context.read<AppProvider>()),
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

          // 如果当前选中的分页不在可用列表中，重置为默认值（使用 Provider 方法）
          if (availablePages.isNotEmpty) {
            provider.resetSemesterPages(availablePages);
          }

          // 应用分页筛选
          final pageFilteredClassrooms = _applyPageFilter(allClassrooms, provider);

          // 应用教室筛选（不再筛选掉没有当前周课程的教室，让下载按钮能显示正确的教室）
          final displayClassrooms = _applyClassroomFilter(pageFilteredClassrooms, provider);

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
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(7, (index) {
                      final isSelected = _selectedWeekday == index;
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: InkWell(
                          onTap: () => setState(() => _selectedWeekday = index),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? Theme.of(context).colorScheme.primary
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Text(
                              _weekdays[index].replaceAll('星期', '周'),
                              style: TextStyle(
                                fontSize: 13,
                                color: isSelected ? Colors.white : null,
                                fontWeight:
                                    isSelected ? FontWeight.bold : null,
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
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
                      onTap: () => provider.toggleSemesterFilterExpanded(),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            provider.isSemesterFilterExpanded ? Icons.expand_less : Icons.expand_more,
                            size: 20,
                            color: Colors.grey.shade600,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            provider.isSemesterFilterExpanded ? '收起筛选' : '展开筛选',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade600,
                            ),
                          ),
                          const SizedBox(width: 4),
                          // 显示当前筛选状态摘要
                          if (!provider.isSemesterFilterExpanded) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.purple.shade100,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                '${provider.semesterSelectedPages.length}个分页',
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
                                '${provider.semesterCourseTypes.length}种类型',
                                style: const TextStyle(fontSize: 11),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    // 展开的筛选内容
                    if (provider.isSemesterFilterExpanded) ...[
                      const SizedBox(height: 8),
                      // 第一行：分页筛选（只显示有数据的分页）
                      Wrap(
                        spacing: 8,
                        alignment: WrapAlignment.center,
                        children: availablePages.map((pageName) {
                          return FilterChip(
                            label: Text(pageName),
                            selected: provider.semesterSelectedPages.contains(pageName),
                            onSelected: (_) => _togglePage(pageName, provider),
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
                            selected: provider.semesterCourseTypes.contains('graduate'),
                            onSelected: (_) => _toggleCourseType('graduate', provider),
                            selectedColor: Colors.blue.shade100,
                          ),
                          FilterChip(
                            label: const Text('本科'),
                            selected:
                                provider.semesterCourseTypes.contains('undergraduate'),
                            onSelected: (_) => _toggleCourseType('undergraduate', provider),
                            selectedColor: Colors.green.shade100,
                          ),
                          FilterChip(
                            label: const Text('借用'),
                            selected: provider.semesterCourseTypes.contains('borrowed'),
                            onSelected: (_) => _toggleCourseType('borrowed', provider),
                            selectedColor: Colors.orange.shade100,
                          ),
                          FilterChip(
                            label: const Text('单周'),
                            selected: provider.semesterSelectedWeekTypes.contains('single'),
                            onSelected: (_) => _toggleWeekType('single', provider),
                            selectedColor: Colors.red.shade100,
                          ),
                          FilterChip(
                            label: const Text('连续周'),
                            selected: provider.semesterSelectedWeekTypes.contains('continuous'),
                            onSelected: (_) => _toggleWeekType('continuous', provider),
                            selectedColor: Colors.teal.shade100,
                          ),
                          ActionChip(
                            label: Text(
                              provider.semesterSelectedClassrooms.isEmpty
                                  ? '教室'
                                  : '教室(${provider.semesterSelectedClassrooms.length})',
                            ),
                            avatar: const Icon(Icons.meeting_room, size: 18),
                            onPressed: () =>
                                _showClassroomFilterDialog(allClassrooms, provider),
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
