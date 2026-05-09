/// 提醒类型
enum ReminderType {
  /// 固定提醒（根据课表自动触发）
  fixed,
  
  /// 自定义提醒（用户自定义）
  custom,
}

/// 固定提醒配置
class FixedReminderConfig {
  final int id;
  final String name; // 提醒名称
  final int hour; // 小时
  final int minute; // 分钟
  final String description; // 描述
  final bool isAttendanceCheck; // 是否是确认缺勤提醒
  final bool isTeacherDiff; // 是否是老师不同提醒
  final bool isCourseCheck; // 是否是有课教室检查提醒（特殊逻辑）
  final List<int>? periods; // 对应的节次范围（如 [1, 2] 表示第1-2节）
  final List<int>? prevPeriods; // 前序节次范围（如 [1, 2] 表示检查1、2节是否有课）
  final int? relatedReminderId; // 关联的缺勤确认提醒ID（如8:45确认缺勤对应id:2）

  const FixedReminderConfig({
    required this.id,
    required this.name,
    required this.hour,
    required this.minute,
    required this.description,
    this.isAttendanceCheck = false,
    this.isTeacherDiff = false,
    this.isCourseCheck = false,
    this.periods,
    this.prevPeriods,
    this.relatedReminderId,
  });

  /// 所有固定提醒列表
  static const List<FixedReminderConfig> all = [
    FixedReminderConfig(
      id: 1,
      name: '7:30 今日1、2节有课教室',
      hour: 7,
      minute: 30,
      description: '提醒今日第1、2节有课的教室',
      periods: [1, 2],
    ),
    FixedReminderConfig(
      id: 2,
      name: '8:45 确认1、2节缺勤',
      hour: 8,
      minute: 45,
      description: '点击确认1、2节没来上课的教室',
      isAttendanceCheck: true,
      periods: [1, 2],
    ),
    FixedReminderConfig(
      id: 3,
      name: '9:40 3、4节有课教室',
      hour: 9,
      minute: 40,
      description: '显示8:45确认缺勤的教室 + 1、2节无课但3、4节有课的教室',
      isCourseCheck: true,
      periods: [3, 4],
      prevPeriods: [1, 2],
      relatedReminderId: 2, // 关联8:45确认缺勤(id:2)
    ),
    FixedReminderConfig(
      id: 4,
      name: '10:10 2、3节老师不同',
      hour: 10,
      minute: 10,
      description: '显示番禺教学大楼第2、3节老师不同的教室',
      isTeacherDiff: true,
      periods: [2, 3],
    ),
    FixedReminderConfig(
      id: 5,
      name: '10:45 确认3、4节缺勤',
      hour: 10,
      minute: 45,
      description: '点击确认3、4节没来上课的教室',
      isAttendanceCheck: true,
      periods: [3, 4],
    ),
    FixedReminderConfig(
      id: 6,
      name: '12:10 关闭所有教室',
      hour: 12,
      minute: 10,
      description: '提醒关闭所有教室',
    ),
    FixedReminderConfig(
      id: 7,
      name: '13:10 今日6、7节有课教室',
      hour: 13,
      minute: 10,
      description: '提醒今日第6、7节有课的教室',
      periods: [6, 7],
    ),
    FixedReminderConfig(
      id: 8,
      name: '14:15 确认6、7节缺勤',
      hour: 14,
      minute: 15,
      description: '点击确认6、7节没来上课的教室',
      isAttendanceCheck: true,
      periods: [6, 7],
    ),
    FixedReminderConfig(
      id: 9,
      name: '15:10 8、9节有课教室',
      hour: 15,
      minute: 10,
      description: '显示14:15确认缺勤的教室 + 6、7节无课但8、9节有课的教室',
      isCourseCheck: true,
      periods: [8, 9],
      prevPeriods: [6, 7],
      relatedReminderId: 8, // 关联14:15确认缺勤(id:8)
    ),
    // 新增：15:40 7、8节老师不同
    FixedReminderConfig(
      id: 14,
      name: '15:40 7、8节老师不同',
      hour: 15,
      minute: 40,
      description: '显示番禺教学大楼第7、8节老师不同的教室',
      isTeacherDiff: true,
      periods: [7, 8],
    ),
    // 新增：16:05 确认8、9节缺勤
    FixedReminderConfig(
      id: 15,
      name: '16:05 确认8、9节缺勤',
      hour: 16,
      minute: 5,
      description: '点击确认8、9节没来上课的教室',
      isAttendanceCheck: true,
      periods: [8, 9],
    ),
    FixedReminderConfig(
      id: 11,
      name: '17:40 今日10-12节有课教室',
      hour: 17,
      minute: 40,
      description: '提醒今日第10、11、12节有课的教室',
      periods: [10, 11, 12],
    ),
    FixedReminderConfig(
      id: 12,
      name: '18:45 确认10-12节缺勤',
      hour: 18,
      minute: 45,
      description: '点击确认10、11、12节没来上课的教室',
      isAttendanceCheck: true,
      periods: [10, 11, 12],
    ),
    FixedReminderConfig(
      id: 13,
      name: '21:05 关闭所有教室',
      hour: 21,
      minute: 5,
      description: '提醒关闭所有教室',
    ),
  ];
}

/// 自定义提醒
class CustomReminder {
  final String id;
  final String content; // 提醒内容
  final int hour; // 小时
  final int minute; // 分钟
  final int? year; // 年份（可选，有值表示单次提醒）
  final int? month; // 月份
  final int? day; // 日期
  bool isEnabled; // 是否启用

  CustomReminder({
    required this.id,
    required this.content,
    required this.hour,
    required this.minute,
    this.year,
    this.month,
    this.day,
    this.isEnabled = true,
  });

  /// 是否是单次提醒（有指定日期）
  bool get isOneTime => year != null && month != null && day != null;

  /// 获取提醒日期字符串
  String? get dateString {
    if (isOneTime) {
      return '${year!}-${month!.toString().padLeft(2, '0')}-${day!.toString().padLeft(2, '0')}';
    }
    return null;
  }

  /// 获取提醒时间字符串
  String get timeString {
    return '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'content': content,
    'hour': hour,
    'minute': minute,
    'year': year,
    'month': month,
    'day': day,
    'isEnabled': isEnabled,
  };

  factory CustomReminder.fromJson(Map<String, dynamic> json) => CustomReminder(
    id: json['id'] as String,
    content: json['content'] as String,
    hour: json['hour'] as int,
    minute: json['minute'] as int,
    year: json['year'] as int?,
    month: json['month'] as int?,
    day: json['day'] as int?,
    isEnabled: json['isEnabled'] as bool? ?? true,
  );
}

/// 已关闭教室记录
class ClosedClassroom {
  final String classroomName;
  final DateTime closedAt;
  final int period; // 在哪个时段关闭的

  ClosedClassroom({
    required this.classroomName,
    required this.closedAt,
    required this.period,
  });
}
