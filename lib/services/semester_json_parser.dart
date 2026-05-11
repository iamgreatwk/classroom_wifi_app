import 'dart:convert';
import 'dart:typed_data';
import '../models/course_with_week.dart';

/// 学期课表 JSON 解析服务
/// 适配新格式：{"title": "...", "classrooms": [{"room_name": "...", "schedule": [...]}]}
class SemesterJsonParser {
  /// 解析学期课表 JSON
  static List<SemesterClassroom> parseSemesterJson(Uint8List bytes) {
    final jsonString = utf8.decode(bytes);
    final data = json.decode(jsonString) as Map<String, dynamic>;

    // 收集所有教室数据
    final classroomMap = <String, _ClassroomData>{};

    // 获取 classrooms 数组
    final classrooms = data['classrooms'] as List?;
    if (classrooms == null) {
      print('[JSON解析] 未找到 classrooms 数组');
      return [];
    }

    print('[JSON解析] 教室数量: ${classrooms.length}');

    // 遍历每个教室
    for (final classroomJson in classrooms) {
      _parseClassroom(classroomJson as Map<String, dynamic>, classroomMap);
    }

    print('[JSON解析] 解析完成，教室数量: ${classroomMap.length}');
    for (final entry in classroomMap.entries) {
      final courseCount = entry.value.schedule.values
          .expand((m) => m.values)
          .expand((l) => l)
          .length;
      print('[JSON解析] 教室 ${entry.key}: $courseCount 条课程');
    }

    // 转换为 SemesterClassroom 列表
    return classroomMap.values.map((data) => data.toSemesterClassroom()).toList();
  }

  /// 解析单个教室
  static void _parseClassroom(
    Map<String, dynamic> json,
    Map<String, _ClassroomData> classroomMap,
  ) {
    // 教室名称使用 room_name 字段
    final classroomName = json['room_name'] as String? ?? '';
    if (classroomName.isEmpty) {
      print('[JSON解析] 教室名称为空，跳过');
      return;
    }

    // capacity 是字符串，需要转换
    final capacityStr = json['capacity'] as String?;
    final capacity = capacityStr != null ? int.tryParse(capacityStr) : null;

    // 获取或创建教室数据
    final classroom = classroomMap.putIfAbsent(
      classroomName,
      () => _ClassroomData(
        name: classroomName,
        capacity: capacity,
      ),
    );

    // 解析课程列表
    final schedule = json['schedule'] as List?;
    if (schedule == null || schedule.isEmpty) {
      print('[JSON解析] 教室 $classroomName 没有课程');
      return;
    }

    print('[JSON解析] 教室 $classroomName 有 ${schedule.length} 条课程记录');

    for (final courseJson in schedule) {
      _parseScheduleRecord(courseJson as Map<String, dynamic>, classroom);
    }
  }

  /// 解析课程记录
  static void _parseScheduleRecord(
    Map<String, dynamic> json,
    _ClassroomData classroom,
  ) {
    // 获取课程类型
    final type = json['type'] as String? ?? '本科';

    // 获取星期
    final weekday = json['day'] as String? ?? '星期一';

    // 获取节次范围
    final startPeriod = json['start_period'] as int? ?? json['period'] as int?;
    final endPeriod = json['end_period'] as int? ?? startPeriod;

    if (startPeriod == null || endPeriod == null) {
      print('[JSON解析] 无效节次: start=$startPeriod, end=$endPeriod');
      return;
    }

    // 获取周次列表
    final weeksList = json['weeks_list'] as List?;
    if (weeksList == null || weeksList.isEmpty) {
      // 部分记录可能没有 weeks_list（如系统占位数据），尝试从 weeks 解析
      final weeksStr = json['weeks'] as String? ?? '';
      if (weeksStr.isEmpty) {
        print('[JSON解析] 无周次信息，跳过');
        return;
      }
      // 尝试解析周次字符串
      final weekRange = _parseWeekRange(weeksStr);
      if (weekRange == null) {
        print('[JSON解析] 无法解析周次: $weeksStr');
        return;
      }
      // 为每个节次创建课程
      for (int period = startPeriod; period <= endPeriod; period++) {
        final course = _createCourse(
          json: json,
          type: type,
          weekday: weekday,
          period: period,
          startWeek: weekRange['startWeek']!,
          endWeek: weekRange['endWeek']!,
          classroomName: classroom.name,
        );
        classroom.addCourse(weekday, period, course);
      }
    } else {
      // 使用 weeks_list 中的周次信息
      final weeks = weeksList.map((w) => w as int).toList();
      if (weeks.isEmpty) {
        print('[JSON解析] weeks_list 为空');
        return;
      }
      final startWeek = weeks.reduce((a, b) => a < b ? a : b);
      final endWeek = weeks.reduce((a, b) => a > b ? a : b);

      // 为每个节次创建课程
      for (int period = startPeriod; period <= endPeriod; period++) {
        final course = _createCourse(
          json: json,
          type: type,
          weekday: weekday,
          period: period,
          startWeek: startWeek,
          endWeek: endWeek,
          classroomName: classroom.name,
          weeksList: weeks,
        );
        classroom.addCourse(weekday, period, course);
      }
    }
  }

  /// 创建 CourseWithWeek 对象
  static CourseWithWeek _createCourse({
    required Map<String, dynamic> json,
    required String type,
    required String weekday,
    required int period,
    required int startWeek,
    required int endWeek,
    required String classroomName,
    List<int>? weeksList,
  }) {
    // 获取课程名称
    String courseName;
    String? teacher;

    switch (type) {
      case '本科':
        courseName = json['name'] as String? ?? '未知课程';
        teacher = json['teacher'] as String?;
        break;
      case '研究生':
        // 研究生有两种子格式
        courseName = json['name'] as String? ?? json['activity'] as String? ?? '未知课程';
        teacher = json['teacher'] as String?;
        break;
      case '借用':
        final activity = json['activity'] as String? ?? '';
        teacher = json['teacher'] as String? ?? '';
        courseName = activity.isNotEmpty ? '借用: $activity' : '借用';
        break;
      default:
        courseName = json['name'] as String? ?? '未知课程';
        teacher = json['teacher'] as String?;
    }

    // 获取 raw 字段
    final rawText = json['raw'] as String?;

    // 获取上课人数
    final studentCount = json['student_count'] as int?;

    return CourseWithWeek(
      name: courseName,
      teacher: teacher,
      weekday: weekday,
      period: period,
      startWeek: startWeek,
      endWeek: endWeek,
      rawText: rawText,
      classroom: classroomName,
      studentCount: studentCount,
      weeksList: weeksList,
    );
  }

  /// 解析周次范围（备用方法，当 weeks_list 不存在时使用）
  /// 支持格式："1-17周"、"第5周"、"5-10周"
  static Map<String, int>? _parseWeekRange(String weeksStr) {
    // 匹配 "1-17周" 或 "5-10周"
    final rangeMatch = RegExp(r'(\d+)\s*-\s*(\d+)周?').firstMatch(weeksStr);
    if (rangeMatch != null) {
      return {
        'startWeek': int.parse(rangeMatch.group(1)!),
        'endWeek': int.parse(rangeMatch.group(2)!),
      };
    }

    // 匹配 "第5周" 或 "第 5 周"
    final singleMatch = RegExp(r'第\s*(\d+)\s*周').firstMatch(weeksStr);
    if (singleMatch != null) {
      final week = int.parse(singleMatch.group(1)!);
      return {
        'startWeek': week,
        'endWeek': week,
      };
    }

    // 尝试直接匹配数字
    final numberMatch = RegExp(r'(\d+)').firstMatch(weeksStr);
    if (numberMatch != null) {
      final week = int.parse(numberMatch.group(1)!);
      return {
        'startWeek': week,
        'endWeek': week,
      };
    }

    return null;
  }
}

/// 临时教室数据结构
class _ClassroomData {
  final String name;
  final int? capacity;
  final Map<String, Map<int, List<CourseWithWeek>>> schedule = {};

  _ClassroomData({required this.name, this.capacity}) {
    // 初始化星期和节次
    final weekdays = ['星期日', '星期一', '星期二', '星期三', '星期四', '星期五', '星期六'];
    for (final day in weekdays) {
      schedule[day] = {};
      for (int period = 1; period <= 13; period++) {
        schedule[day]![period] = [];
      }
    }
  }

  void addCourse(String weekday, int period, CourseWithWeek course) {
    if (schedule.containsKey(weekday) && schedule[weekday]!.containsKey(period)) {
      schedule[weekday]![period]!.add(course);
    }
  }

  SemesterClassroom toSemesterClassroom() {
    return SemesterClassroom(
      name: name,
      schedule: schedule,
      capacity: capacity,
    );
  }
}
