import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/course.dart';
import '../models/course_with_week.dart';
import '../models/reminder.dart';

/// 设置存储服务
/// 使用 SharedPreferences（Web 底层是 localStorage）
class StorageService {
  static const String _wifiMappingsKey = 'wifi_classroom_mappings';
  static const String _classroomsKey = 'classrooms_data';
  static const String _lastExcelPathKey = 'last_excel_path';
  static const String _enabledFixedRemindersKey = 'enabled_fixed_reminders';
  static const String _customRemindersKey = 'custom_reminders';
  static const String _absentClassroomsKey = 'absent_classrooms';
  static const String _semesterClassroomsKey = 'semester_classrooms_data';

  static final StorageService _instance = StorageService._internal();
  factory StorageService() => _instance;
  StorageService._internal();

  SharedPreferences? _prefs;

  /// 初始化
  Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  /// 保存WiFi与教室的对应关系
  Future<bool> saveWifiMappings(List<WifiClassroomMapping> mappings) async {
    await init();
    final jsonList = mappings.map((m) => m.toJson()).toList();
    return await _prefs!.setString(_wifiMappingsKey, jsonEncode(jsonList));
  }

  /// 获取WiFi与教室的对应关系
  Future<List<WifiClassroomMapping>> getWifiMappings() async {
    await init();
    final jsonStr = _prefs!.getString(_wifiMappingsKey);
    if (jsonStr == null || jsonStr.isEmpty) return [];

    try {
      final jsonList = jsonDecode(jsonStr) as List;
      return jsonList
          .map((json) => WifiClassroomMapping.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (e) {
      return [];
    }
  }

  /// 保存教室数据（用于离线使用）
  Future<bool> saveClassrooms(List<Classroom> classrooms) async {
    await init();
    final jsonList = classrooms.map((c) => {
      'name': c.name,
      'capacity': c.capacity,
      'schedule': c.schedule.map((key, value) => MapEntry(
        key,
        value.map((periodKey, course) => MapEntry(
          periodKey.toString(),
          {'name': course.name, 'teacher': course.teacher, 'weekday': course.weekday, 'period': course.period}
        ))
      )),
    }).toList();
    return await _prefs!.setString(_classroomsKey, jsonEncode(jsonList));
  }

  /// 获取保存的教室数据
  Future<List<Classroom>> getClassrooms() async {
    await init();
    final jsonStr = _prefs!.getString(_classroomsKey);
    if (jsonStr == null || jsonStr.isEmpty) return [];

    try {
      final jsonList = jsonDecode(jsonStr) as List;
      return jsonList.map((json) {
        final scheduleJson = json['schedule'] as Map<String, dynamic>;
        final schedule = <String, Map<int, Course>>{};

        scheduleJson.forEach((weekday, periods) {
          final periodMap = <int, Course>{};
          (periods as Map<String, dynamic>).forEach((period, course) {
            periodMap[int.parse(period)] = Course(
              name: course['name'],
              teacher: course['teacher'],
              weekday: course['weekday'],
              period: course['period'],
            );
          });
          if (periodMap.isNotEmpty) {
            schedule[weekday] = periodMap;
          }
        });

        return Classroom(
          name: json['name'],
          schedule: schedule,
          capacity: json['capacity'] as int?,
        );
      }).toList();
    } catch (e) {
      return [];
    }
  }

  /// 保存最后使用的Excel文件路径
  Future<bool> saveLastExcelPath(String path) async {
    await init();
    return await _prefs!.setString(_lastExcelPathKey, path);
  }

  /// 获取最后使用的Excel文件路径
  Future<String?> getLastExcelPath() async {
    await init();
    return _prefs!.getString(_lastExcelPathKey);
  }

  /// 清除所有数据
  Future<bool> clearAll() async {
    await init();
    return await _prefs!.clear();
  }

  /// 保存启用的固定提醒ID集合
  Future<bool> saveEnabledFixedReminders(Set<int> enabledIds) async {
    await init();
    final list = enabledIds.toList();
    return await _prefs!.setStringList(_enabledFixedRemindersKey, list.map((e) => e.toString()).toList());
  }

  /// 获取启用的固定提醒ID集合
  Future<Set<int>> getEnabledFixedReminders() async {
    await init();
    final list = _prefs!.getStringList(_enabledFixedRemindersKey);
    if (list == null || list.isEmpty) {
      // 默认全部禁用
      return {};
    }
    return list.map((e) => int.parse(e)).toSet();
  }

  /// 保存自定义提醒列表
  Future<bool> saveCustomReminders(List<CustomReminder> reminders) async {
    await init();
    final jsonList = reminders.map((r) => r.toJson()).toList();
    return await _prefs!.setString(_customRemindersKey, jsonEncode(jsonList));
  }

  /// 获取自定义提醒列表
  Future<List<CustomReminder>> getCustomReminders() async {
    await init();
    final jsonStr = _prefs!.getString(_customRemindersKey);
    if (jsonStr == null || jsonStr.isEmpty) return [];
    
    try {
      final jsonList = jsonDecode(jsonStr) as List;
      return jsonList
          .map((json) => CustomReminder.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (e) {
      return [];
    }
  }

  /// 保存缺勤教室记录 Map<reminderId, Set<classroomNames>>
  Future<bool> saveAbsentClassrooms(Map<int, Set<String>> absentData) async {
    await init();
    final jsonMap = absentData.map((key, value) => MapEntry(key.toString(), value.toList()));
    return await _prefs!.setString(_absentClassroomsKey, jsonEncode(jsonMap));
  }

  /// 获取缺勤教室记录
  Future<Map<int, Set<String>>> getAbsentClassrooms() async {
    await init();
    final jsonStr = _prefs!.getString(_absentClassroomsKey);
    if (jsonStr == null || jsonStr.isEmpty) return {};
    
    try {
      final jsonMap = jsonDecode(jsonStr) as Map<String, dynamic>;
      return jsonMap.map((key, value) => MapEntry(int.parse(key), (value as List).map((e) => e.toString()).toSet()));
    } catch (e) {
      return {};
    }
  }

  /// 保存学期课表数据
  Future<bool> saveSemesterClassrooms(List<SemesterClassroom> classrooms) async {
    await init();
    final jsonList = classrooms.map((c) => _semesterClassroomToJson(c)).toList();
    return await _prefs!.setString(_semesterClassroomsKey, jsonEncode(jsonList));
  }

  /// 获取学期课表数据
  Future<List<SemesterClassroom>> getSemesterClassrooms() async {
    await init();
    final jsonStr = _prefs!.getString(_semesterClassroomsKey);
    if (jsonStr == null || jsonStr.isEmpty) return [];

    try {
      final jsonList = jsonDecode(jsonStr) as List;
      return jsonList
          .map((json) => _semesterClassroomFromJson(json as Map<String, dynamic>))
          .toList();
    } catch (e) {
      return [];
    }
  }

  /// 清除学期课表数据
  Future<bool> clearSemesterClassrooms() async {
    await init();
    return await _prefs!.remove(_semesterClassroomsKey);
  }

  /// 将 SemesterClassroom 转换为 JSON
  Map<String, dynamic> _semesterClassroomToJson(SemesterClassroom classroom) {
    final scheduleJson = <String, dynamic>{};
    classroom.schedule.forEach((day, periods) {
      final periodsJson = <String, dynamic>{};
      periods.forEach((period, courses) {
        periodsJson[period.toString()] = courses.map((c) => _courseWithWeekToJson(c)).toList();
      });
      scheduleJson[day] = periodsJson;
    });

    return {
      'name': classroom.name,
      'schedule': scheduleJson,
      'capacity': classroom.capacity,
    };
  }

  /// 从 JSON 创建 SemesterClassroom
  SemesterClassroom _semesterClassroomFromJson(Map<String, dynamic> json) {
    final schedule = <String, Map<int, List<CourseWithWeek>>>{};
    final scheduleJson = json['schedule'] as Map<String, dynamic>;
    
    scheduleJson.forEach((day, periodsJson) {
      final periods = <int, List<CourseWithWeek>>{};
      (periodsJson as Map<String, dynamic>).forEach((period, coursesJson) {
        periods[int.parse(period)] = (coursesJson as List)
            .map((c) => _courseWithWeekFromJson(c as Map<String, dynamic>))
            .toList();
      });
      schedule[day] = periods;
    });

    return SemesterClassroom(
      name: json['name'] as String,
      schedule: schedule,
      capacity: json['capacity'] as int?,
    );
  }

  /// 将 CourseWithWeek 转换为 JSON
  Map<String, dynamic> _courseWithWeekToJson(CourseWithWeek course) {
    return {
      'name': course.name,
      'teacher': course.teacher,
      'weekday': course.weekday,
      'period': course.period,
      'startWeek': course.startWeek,
      'endWeek': course.endWeek,
      'rawText': course.rawText,
      'classroom': course.classroom,
      'studentCount': course.studentCount,
    };
  }

  /// 从 JSON 创建 CourseWithWeek
  CourseWithWeek _courseWithWeekFromJson(Map<String, dynamic> json) {
    return CourseWithWeek(
      name: json['name'] as String,
      teacher: json['teacher'] as String?,
      weekday: json['weekday'] as String,
      period: json['period'] as int,
      startWeek: json['startWeek'] as int,
      endWeek: json['endWeek'] as int,
      rawText: json['rawText'] as String?,
      classroom: json['classroom'] as String,
      studentCount: json['studentCount'] as int?,
    );
  }
}
