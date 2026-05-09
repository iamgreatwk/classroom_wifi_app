/// 带周次信息的课程模型（用于学期课表）
class CourseWithWeek {
  final String name;
  final String? teacher;
  final String weekday;
  final int period;
  final int startWeek;
  final int endWeek;
  final String? rawText;
  final String classroom;
  final int? studentCount; // 上课人数

  CourseWithWeek({
    required this.name,
    this.teacher,
    required this.weekday,
    required this.period,
    required this.startWeek,
    required this.endWeek,
    this.rawText,
    required this.classroom,
    this.studentCount,
  });

  /// 获取显示名称
  String get displayName {
    if (teacher != null && teacher!.isNotEmpty) {
      return '$name - $teacher';
    }
    return name;
  }

  /// 获取周次显示文本
  String get weekDisplay {
    if (startWeek == endWeek) {
      return '第$startWeek周';
    }
    return '$startWeek-$endWeek周';
  }

  /// 是否是单周课程
  bool get isSingleWeek => startWeek == endWeek;

  /// 检查课程是否在指定周次有课
  bool hasClassInWeek(int week) {
    return week >= startWeek && week <= endWeek;
  }

  @override
  String toString() => '$displayName ($weekDisplay)';
}

/// 学期教室模型
class SemesterClassroom {
  final String name;
  /// 课程列表：{weekday: {period: [CourseWithWeek]}}
  final Map<String, Map<int, List<CourseWithWeek>>> schedule;
  final int? capacity;

  SemesterClassroom({
    required this.name,
    required this.schedule,
    this.capacity,
  });

  /// 获取指定星期和节次的所有课程
  List<CourseWithWeek> getCourses(String weekday, int period) {
    return schedule[weekday]?[period] ?? [];
  }

  /// 获取指定星期和节次在特定周的课程
  List<CourseWithWeek> getCoursesForWeek(String weekday, int period, int week) {
    final allCourses = getCourses(weekday, period);
    return allCourses.where((c) => c.hasClassInWeek(week)).toList();
  }

  /// 获取指定周的所有课程
  List<CourseWithWeek> getAllCoursesForWeek(int week) {
    final result = <CourseWithWeek>[];
    for (final daySchedule in schedule.values) {
      for (final periodCourses in daySchedule.values) {
        result.addAll(periodCourses.where((c) => c.hasClassInWeek(week)));
      }
    }
    return result;
  }

  /// 获取指定星期的所有课程（不分节次）
  List<CourseWithWeek> getCoursesForWeekday(String weekday) {
    final result = <CourseWithWeek>[];
    final daySchedule = schedule[weekday];
    if (daySchedule == null) return [];
    for (final periodCourses in daySchedule.values) {
      result.addAll(periodCourses);
    }
    return result;
  }

  /// 获取指定星期和节次的所有课程（别名，与 getCourses 相同）
  List<CourseWithWeek> getCoursesForPeriod(String weekday, int period) {
    return getCourses(weekday, period);
  }
}
