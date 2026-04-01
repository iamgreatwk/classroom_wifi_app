/// 课程信息模型
class Course {
  final String name;
  final String? teacher; // 教师姓名（可选）
  final String weekday; // 星期几
  final int period; // 第几节

  Course({
    required this.name,
    this.teacher,
    required this.weekday,
    required this.period,
  });

  /// 获取显示名称（包含教师信息）
  String get displayName {
    if (teacher != null && teacher!.isNotEmpty) {
      return '$name - $teacher';
    }
    return name;
  }

  @override
  String toString() => displayName;
}

/// 教室模型
class Classroom {
  final String name;
  final Map<String, Map<int, Course>> schedule; // {weekday: {period: Course}}
  final int? capacity; // 教室容量（座位数）

  Classroom({
    required this.name,
    required this.schedule,
    this.capacity,
  });

  /// 获取某一天的课程
  List<Course> getCoursesForDay(String weekday) {
    final daySchedule = schedule[weekday];
    if (daySchedule == null) return [];
    
    final courses = <Course>[];
    for (var i = 1; i <= 12; i++) {
      final course = daySchedule[i];
      if (course != null) {
        courses.add(course);
      }
    }
    return courses;
  }

  /// 获取当前正在进行的课程
  Course? getCurrentCourse(String weekday, int currentPeriod) {
    final daySchedule = schedule[weekday];
    if (daySchedule == null) return null;
    
    // 找到当前节次或最近的下一节课
    for (var i = currentPeriod; i <= 12; i++) {
      final course = daySchedule[i];
      if (course != null) {
        return course;
      }
    }
    return null;
  }

  /// 获取指定节次的课程
  Course? getCourseAtPeriod(String weekday, int period) {
    return schedule[weekday]?[period];
  }

  /// 检查在指定节次范围内是否有课
  bool hasCourseInPeriods(String weekday, List<int> periods) {
    final daySchedule = schedule[weekday];
    if (daySchedule == null) return false;
    for (final period in periods) {
      if (daySchedule.containsKey(period)) {
        return true;
      }
    }
    return false;
  }

  /// 获取指定节次范围内的第一门课程
  Course? getFirstCourseInPeriods(String weekday, List<int> periods) {
    final daySchedule = schedule[weekday];
    if (daySchedule == null) return null;
    for (final period in periods) {
      final course = daySchedule[period];
      if (course != null) {
        return course;
      }
    }
    return null;
  }
}

/// WiFi与教室的对应关系
class WifiClassroomMapping {
  final String bssid; // WiFi的BSSID（MAC地址）
  String ssid; // WiFi名称 (SSID)
  String classroomName;
  int? lastRssi; // 最近检测到的信号强度

  WifiClassroomMapping({
    required this.bssid,
    this.ssid = '',
    required this.classroomName,
    this.lastRssi,
  });

  /// 获取显示名称（优先使用SSID，如果没有则显示BSSID）
  String get displayName => ssid.isNotEmpty ? ssid : bssid;

  Map<String, dynamic> toJson() => {
    'bssid': bssid,
    'ssid': ssid,
    'classroomName': classroomName,
  };

  factory WifiClassroomMapping.fromJson(Map<String, dynamic> json) {
    return WifiClassroomMapping(
      bssid: json['bssid'] as String,
      ssid: json['ssid'] as String? ?? '',
      classroomName: json['classroomName'] as String,
    );
  }
}
