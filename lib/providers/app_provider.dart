import 'dart:convert';
import 'dart:async';
import 'dart:typed_data';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../models/course.dart';
import '../models/course_with_week.dart';
import '../models/reminder.dart';
import '../services/excel_parser_service.dart';
import '../services/semester_excel_parser.dart';
import '../services/semester_json_parser.dart';
import '../services/wifi_service.dart';
import '../services/storage_service.dart';
import '../services/reminder_service.dart';
import '../config.dart';

/// 应用状态Provider
class AppProvider extends ChangeNotifier {
  final WifiService _wifiService = WifiService();
  final StorageService _storageService = StorageService();
  final ReminderService _reminderService = ReminderService();

  // 固定提醒启用状态
  Set<int> _enabledFixedReminders = {};
  Set<int> get enabledFixedReminders => _enabledFixedReminders;

  // 自定义提醒列表
  List<CustomReminder> _customReminders = [];
  List<CustomReminder> get customReminders => _customReminders;

  // 缺勤教室记录 Map<reminderId, Set<classroomNames>>
  Map<int, Set<String>> _absentClassrooms = {};
  Map<int, Set<String>> get absentClassrooms => _absentClassrooms;

  /// 获取所有启用的固定提醒列表
  List<FixedReminderConfig> get enabledFixedRemindersList {
    return FixedReminderConfig.all
        .where((r) => _enabledFixedReminders.contains(r.id))
        .toList();
  }

  /// 获取所有启用的自定义提醒列表
  List<CustomReminder> get enabledCustomReminders {
    return _customReminders.where((r) => r.isEnabled).toList();
  }

  /// 获取所有提醒列表（固定+自定义），按时间排序
  List<Map<String, dynamic>> get allReminders {
    final List<Map<String, dynamic>> reminders = [];
    
    // 添加固定提醒
    for (final config in FixedReminderConfig.all) {
      if (_enabledFixedReminders.contains(config.id)) {
        reminders.add({
          'type': 'fixed',
          'id': config.id,
          'name': config.name,
          'hour': config.hour,
          'minute': config.minute,
          'description': config.description,
        });
      }
    }
    
    // 添加自定义提醒
    for (final reminder in _customReminders) {
      if (reminder.isEnabled) {
        reminders.add({
          'type': 'custom',
          'id': reminder.id,
          'content': reminder.content,
          'hour': reminder.hour,
          'minute': reminder.minute,
        });
      }
    }
    
    // 按时间排序
    reminders.sort((a, b) {
      final aTime = a['hour'] * 60 + a['minute'];
      final bTime = b['hour'] * 60 + b['minute'];
      return aTime.compareTo(bTime);
    });
    
    return reminders;
  }

  /// 检查当前时间是否有提醒需要触发
  /// 返回需要触发的提醒列表
  List<Map<String, dynamic>> getTriggingReminders() {
    final now = DateTime.now();
    final currentHour = now.hour;
    final currentMinute = now.minute;
    final currentTime = currentHour * 60 + currentMinute;
    
    final List<Map<String, dynamic>> triggeringReminders = [];
    
    for (final reminder in allReminders) {
      final reminderTime = (reminder['hour'] as int) * 60 + (reminder['minute'] as int);
      // 检查是否在当前分钟（允许1分钟内的误差）
      if (currentTime == reminderTime) {
        triggeringReminders.add(reminder);
      }
    }
    
    return triggeringReminders;
  }

  /// 记录上次触发的时间（防止重复弹窗）
  int? _lastTriggeredMinute;
  
  /// 检查并触发提醒弹窗
  /// 返回 true 表示有提醒触发
  bool checkAndTriggerReminder() {
    final now = DateTime.now();
    final currentMinute = now.hour * 60 + now.minute;
    
    // 防止同一分钟内重复触发
    if (_lastTriggeredMinute == currentMinute) {
      return false;
    }
    
    _lastTriggeredMinute = currentMinute;
    
    final triggering = getTriggingReminders();
    return triggering.isNotEmpty;
  }

  // 课室数据
  List<Classroom> _classrooms = [];
  List<Classroom> get classrooms => _classrooms;

  /// 硬编码的BSSID→教室映射表（教室名称与Excel中一致，带"室"字）
  static const Map<String, String> _staticBssidMap = {
    '92:0d:9e:85:ee:6a': '番禺教学大楼233室',
    'a2:0d:9e:85:f7:4c': '番禺教学大楼232室',
    'a2:0d:9e:85:eb:dc': '番禺教学大楼230室',
    '9a:d0:f5:e6:e1:fb': '番禺教学大楼227室',
    '12:0d:9e:85:ec:72': '番禺教学大楼220室',
    '0a:05:88:99:95:b7': '番禺教学大楼234室',
    'ea:d0:f5:e6:d1:80': '番禺教学大楼231室',
    '3a:d0:f5:e6:d0:55': '番禺教学大楼229室',
    '06:69:6c:85:d4:29': '番禺教学大楼228室',
    '0a:69:6c:bb:d9:69': '番禺教学大楼226室',
    '8a:d0:f5:e6:e6:2a': '番禺教学大楼223室',
    '42:0d:9e:85:f6:56': '番禺教学大楼225室',
    '9a:d0:f5:e6:d8:6b': '番禺教学大楼221室',
    '0a:69:6c:bb:d9:af': '番禺教学大楼224室',
    '52:0d:9e:85:ec:66': '番禺教学大楼222室',
    '6a:d0:f5:e6:d0:b8': '番禺教学大楼219室',
    'e2:0d:9e:85:eb:00': '番禺教学大楼218室',
    '44:df:65:ac:12:35': '番禺教学大楼555室',
  };

  // WiFi与教室的映射（由硬编码表生成，不再手动管理）
  List<WifiClassroomMapping> _wifiMappings = [];
  List<WifiClassroomMapping> get wifiMappings => _wifiMappings;

  // 当前检测到的WiFi列表
  List<WifiInfo> _currentWifiList = [];
  List<WifiInfo> get currentWifiList => _currentWifiList;

  // 当前匹配的教室
  Classroom? _nearestClassroom;
  
  /// 手动选择的教室（Web版使用）
  Classroom? _selectedClassroom;
  
  /// 获取当前教室（Web版返回手动选择的，Android版返回WiFi检测的）
  Classroom? get nearestClassroom {
    if (AppConfig.isWebMode) {
      return _selectedClassroom;
    }
    return _nearestClassroom;
  }
  
  /// 选择教室（Web版使用）
  void selectClassroom(Classroom? classroom) {
    _selectedClassroom = classroom;
    _updateCurrentCourse();
    notifyListeners();
  }
  
  /// 获取手动选择的教室（Web版使用）
  Classroom? get selectedClassroom => _selectedClassroom;

  // 当前课程
  Course? _currentCourse;
  Course? get currentCourse => _currentCourse;

  // 加载状态
  bool _isLoading = false;
  bool get isLoading => _isLoading;

  // 错误信息
  String? _error;
  String? get error => _error;

  // WiFi扫描定时器
  Timer? _scanTimer;
  bool _isScanning = false;
  bool get isScanning => _isScanning;

  /// 初始化
  Future<void> init() async {
    _isLoading = true;
    notifyListeners();

    try {
      // 加载保存的教室课表数据
      _classrooms = await _storageService.getClassrooms();

      // 从硬编码表初始化WiFi映射（不再读取storage）
      _wifiMappings = _staticBssidMap.entries
          .map((e) => WifiClassroomMapping(bssid: e.key, classroomName: e.value))
          .toList();

      // 检查权限（非Web版）
      if (!AppConfig.isWebMode) {
        await _wifiService.checkPermissions();
      }

      // 初始化提醒服务（非Web版）
      if (!AppConfig.isWebMode) {
        await _reminderService.init();
        await _reminderService.requestPermission();
      }

      // 加载保存的提醒设置
      await _loadReminderSettings();
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }

    // 初始化完成后自动开始WiFi扫描（非Web版）
    if (!AppConfig.isWebMode) {
      startWifiScan();
    }
  }

  /// 加载提醒设置
  Future<void> _loadReminderSettings() async {
    _enabledFixedReminders = await _storageService.getEnabledFixedReminders();
    _customReminders = await _storageService.getCustomReminders();
    _absentClassrooms = await _storageService.getAbsentClassrooms();
    
    // 调度所有启用的提醒
    await _scheduleAllReminders();
  }

  /// 调度所有提醒
  Future<void> _scheduleAllReminders() async {
    // Web版不调度通知
    if (AppConfig.isWebMode) return;
    
    // 调度固定提醒
    await _reminderService.scheduleAllFixedReminders(_enabledFixedReminders);
    
    // 调度自定义提醒
    for (final reminder in _customReminders) {
      if (reminder.isEnabled) {
        await _reminderService.scheduleCustomReminder(reminder);
      }
    }
  }

  /// 切换固定提醒
  Future<void> toggleFixedReminder(int id, bool enabled) async {
    if (enabled) {
      _enabledFixedReminders.add(id);
    } else {
      _enabledFixedReminders.remove(id);
    }
    notifyListeners();
    
    await _storageService.saveEnabledFixedReminders(_enabledFixedReminders);
    if (!AppConfig.isWebMode) {
      await _reminderService.scheduleAllFixedReminders(_enabledFixedReminders);
    }
  }

  /// 添加自定义提醒
  Future<void> addCustomReminder({
    required String content,
    required int hour,
    required int minute,
    int? year,
    int? month,
    int? day,
  }) async {
    final reminder = CustomReminder(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      content: content,
      hour: hour,
      minute: minute,
      year: year,
      month: month,
      day: day,
      isEnabled: true,
    );
    
    _customReminders.add(reminder);
    notifyListeners();
    
    await _storageService.saveCustomReminders(_customReminders);
    if (!AppConfig.isWebMode) {
      await _reminderService.scheduleCustomReminder(reminder);
    }
  }

  /// 切换自定义提醒
  Future<void> toggleCustomReminder(String id, bool enabled) async {
    final index = _customReminders.indexWhere((r) => r.id == id);
    if (index != -1) {
      _customReminders[index].isEnabled = enabled;
      notifyListeners();
      
      await _storageService.saveCustomReminders(_customReminders);
      if (!AppConfig.isWebMode) {
        if (enabled) {
          await _reminderService.scheduleCustomReminder(_customReminders[index]);
        } else {
          await _reminderService.cancelCustomReminder(_customReminders[index]);
        }
      }
    }
  }

  /// 删除自定义提醒
  Future<void> deleteCustomReminder(String id) async {
    final reminder = _customReminders.firstWhere((r) => r.id == id);
    if (!AppConfig.isWebMode) {
      await _reminderService.cancelCustomReminder(reminder);
    }
    
    _customReminders.removeWhere((r) => r.id == id);
    await _storageService.saveCustomReminders(_customReminders);
    notifyListeners();
  }

  /// 保存缺勤教室记录
  Future<void> saveAbsentClassrooms(int reminderId, Set<String> classrooms) async {
    _absentClassrooms[reminderId] = classrooms;
    await _storageService.saveAbsentClassrooms(_absentClassrooms);
    notifyListeners();
  }

  /// 获取特定提醒的缺勤教室
  Set<String> getAbsentClassroomsForReminder(int reminderId) {
    return _absentClassrooms[reminderId] ?? {};
  }

  /// 获取关联提醒的缺勤教室（比如9:40显示8:45确认缺勤的教室）
  Set<String> getAbsentClassroomsForRelatedReminder(int? relatedReminderId) {
    if (relatedReminderId == null) return {};
    return _absentClassrooms[relatedReminderId] ?? {};
  }

  // 当前选中的总览分页集合（支持多选，用于筛选查看时过滤教室）
  Set<String> _selectedOverviewPages = {'2楼大'};
  Set<String> get selectedOverviewPages => _selectedOverviewPages;

  /// 兼容旧代码：返回第一个选中的分页（单选场景使用）
  String? get selectedOverviewPage =>
      _selectedOverviewPages.isNotEmpty ? _selectedOverviewPages.first : null;

  /// 设置当前选中的总览分页（单选兼容旧接口）
  void setSelectedOverviewPage(String? pageName) {
    if (pageName != null) {
      _selectedOverviewPages = {pageName};
    }
    notifyListeners();
  }

  /// 切换分页的选中状态（多选）
  void toggleOverviewPage(String pageName) {
    if (_selectedOverviewPages.contains(pageName)) {
      if (_selectedOverviewPages.length > 1) {
        _selectedOverviewPages = Set.from(_selectedOverviewPages)..remove(pageName);
      }
      // 最少保留1个选中，不允许取消最后一个
    } else {
      _selectedOverviewPages = Set.from(_selectedOverviewPages)..add(pageName);
    }
    notifyListeners();
  }

  /// 检查分页是否被选中
  bool isOverviewPageSelected(String pageName) {
    return _selectedOverviewPages.contains(pageName);
  }

  /// 固定的分页配置（教室编号范围）
  /// 格式：{ '页面名称': [教室编号列表] }
  static final Map<String, List<int>> pageConfigs = {
    '2楼小': List.generate(14, (i) => 204 + i), // 204-217
    '2楼大': List.generate(17, (i) => 218 + i), // 218-234
    '3楼小': List.generate(15, (i) => 301 + i), // 301-315
    '3楼大': List.generate(18, (i) => 316 + i), // 316-333
    '4楼小': List.generate(15, (i) => 401 + i), // 401-415
    '4楼大': List.generate(18, (i) => 416 + i), // 416-433
    '5楼语音室': [...List.generate(5, (i) => 501 + i), ...List.generate(7, (i) => 512 + i)], // 501-505, 512-518
    '5楼多媒体': [113, 114, 507, 508, 509, 510, 511, 524, 525, 526, 527, 528, 529], // 113-114, 507-511, 524-529
  };

  /// 根据分页名称获取该分页的教室编号列表
  List<int>? getPageNumbers(String pageName) {
    return pageConfigs[pageName];
  }

  /// 检查教室是否属于指定分页
  bool isClassroomInPage(String classroomName, String pageName) {
    final allowedNumbers = pageConfigs[pageName];
    if (allowedNumbers == null) return false;
    
    final numStr = classroomName.replaceAll(RegExp(r'[^0-9]'), '');
    final num = int.tryParse(numStr) ?? 0;
    return allowedNumbers.contains(num);
  }

  /// 解析Excel文件
  /// [isSunday] - true表示导入周日课表，false表示导入周一到周六课表
  Future<void> parseExcelFile(String filePath, {bool isSunday = false}) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final newClassrooms = await ExcelParserService.parseExcelFile(filePath, isSunday: isSunday);
      
      if (isSunday) {
        // 周日课表：合并到现有教室数据中（只更新星期日的课程），清空缺勤
        _mergeSundayTimetable(newClassrooms);
        _absentClassrooms = {};
        await _storageService.saveAbsentClassrooms(_absentClassrooms);
      } else {
        // 周一至周六课表：完全替换旧数据，清空缺勤
        _classrooms = newClassrooms;
        _absentClassrooms = {};
        await _storageService.saveAbsentClassrooms(_absentClassrooms);
      }
      
      // 保存到本地
      await _storageService.saveClassrooms(_classrooms);
      await _storageService.saveLastExcelPath(filePath);
    } catch (e) {
      _error = '解析Excel文件失败: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// 从字节数据解析Excel文件（适用于Web环境）
  /// [isSunday] - true表示导入周日课表，false表示导入周一到周六课表
  Future<void> parseExcelBytes(Uint8List bytes, {bool isSunday = false}) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final newClassrooms = await ExcelParserService.parseExcelBytes(bytes, isSunday: isSunday);

      if (isSunday) {
        // 周日课表：合并到现有教室数据中（只更新星期日的课程），清空缺勤
        _mergeSundayTimetable(newClassrooms);
        _absentClassrooms = {};
        await _storageService.saveAbsentClassrooms(_absentClassrooms);
      } else {
        // 周一至周六课表：完全替换旧数据，清空缺勤
        _classrooms = newClassrooms;
        _absentClassrooms = {};
        await _storageService.saveAbsentClassrooms(_absentClassrooms);
      }

      // 保存到本地
      await _storageService.saveClassrooms(_classrooms);
    } catch (e) {
      _error = '解析Excel文件失败: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// 合并周一至周六课表
  void _mergeWeekdayTimetable(List<Classroom> newClassrooms) {
    for (final newClass in newClassrooms) {
      final existingIndex = _classrooms.indexWhere((c) => c.name == newClass.name);
      if (existingIndex != -1) {
        final existing = _classrooms[existingIndex];
        // 合并schedule，同时更新capacity（优先用新导入的）
        final mergedSchedule = Map<String, Map<int, Course>>.from(existing.schedule);
        for (final entry in newClass.schedule.entries) {
          mergedSchedule[entry.key] = entry.value;
        }
        _classrooms[existingIndex] = Classroom(
          name: existing.name,
          schedule: mergedSchedule,
          capacity: newClass.capacity ?? existing.capacity,
        );
      } else {
        // 添加新教室
        _classrooms.add(newClass);
      }
    }
  }

  /// 合并周日课表
  void _mergeSundayTimetable(List<Classroom> newClassrooms) {
    for (final newClass in newClassrooms) {
      final existingIndex = _classrooms.indexWhere((c) => c.name == newClass.name);
      if (existingIndex != -1) {
        final existing = _classrooms[existingIndex];
        // 合并周日schedule
        final mergedSchedule = Map<String, Map<int, Course>>.from(existing.schedule);
        final sundaySchedule = newClass.schedule['星期日'];
        if (sundaySchedule != null) {
          mergedSchedule['星期日'] = sundaySchedule;
        }
        _classrooms[existingIndex] = Classroom(
          name: existing.name,
          schedule: mergedSchedule,
          capacity: newClass.capacity ?? existing.capacity,
        );
      } else {
        // 添加新教室（只有周日课表）
        _classrooms.add(newClass);
      }
    }
  }

  /// 开始WiFi扫描
  void startWifiScan() {
    if (_isScanning) return;
    _isScanning = true;
    notifyListeners();

    // 立即扫描一次
    _performScan();

    // 每5秒扫描一次
    _scanTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _performScan();
    });
  }

  /// 停止WiFi扫描
  void stopWifiScan() {
    _scanTimer?.cancel();
    _scanTimer = null;
    _isScanning = false;
    notifyListeners();
  }

  /// 执行扫描
  Future<void> _performScan() async {
    try {
      final wifiList = await _wifiService.scanWifi();
      _currentWifiList = wifiList;

      // 更新映射中的RSSI值
      for (var mapping in _wifiMappings) {
        final wifi = wifiList.where((w) => w.bssid == mapping.bssid).firstOrNull;
        if (wifi != null) {
          mapping.lastRssi = wifi.signalStrength;
        }
      }

      // 查找最近的教室
      _findNearestClassroom();

      // 更新当前课程
      _updateCurrentCourse();

      notifyListeners();
    } catch (e) {
      _error = 'WiFi扫描失败: $e';
    }
  }

  /// 查找最近的教室
  void _findNearestClassroom() {
    if (_wifiMappings.isEmpty || _classrooms.isEmpty) {
      _nearestClassroom = null;
      return;
    }

    // 找到信号最强的WiFi
    int? strongestRssi;
    WifiClassroomMapping? nearestMapping;

    for (var mapping in _wifiMappings) {
      // BSSID匹配时不区分大小写
      final wifi = _currentWifiList.where(
        (w) => w.bssid.toLowerCase() == mapping.bssid.toLowerCase()
      ).firstOrNull;
      if (wifi != null && (strongestRssi == null || wifi.signalStrength > strongestRssi)) {
        strongestRssi = wifi.signalStrength;
        nearestMapping = mapping;
      }
    }

    if (nearestMapping == null) {
      _nearestClassroom = null;
      return;
    }

    // 找到对应的教室
    _nearestClassroom = _classrooms
        .where((c) => c.name == nearestMapping!.classroomName)
        .firstOrNull;
  }

  /// 更新当前课程
  void _updateCurrentCourse() {
    // Web版使用手动选择的教室，Android版使用WiFi检测的教室
    final currentClassroom = AppConfig.isWebMode ? _selectedClassroom : _nearestClassroom;
    
    if (currentClassroom == null) {
      _currentCourse = null;
      return;
    }

    final now = DateTime.now();
    final weekday = ExcelParserService.getWeekdayName(now);
    final period = ExcelParserService.getCurrentPeriod(now);

    _currentCourse = currentClassroom.getCourseAtPeriod(weekday, period);
  }

  /// 获取指定教室的课程
  List<Course> getCoursesForClassroom(Classroom classroom, String weekday) {
    return classroom.getCoursesForDay(weekday);
  }

  /// 获取所有WiFi列表（当前检测到的）
  List<WifiInfo> getDetectedWifiList() {
    return _currentWifiList;
  }

  /// 清理资源
  @override
  void dispose() {
    stopWifiScan();
    _wifiService.dispose();
    super.dispose();
  }

  // ========== 学期课表相关 ==========

  /// 学期课表教室数据
  List<SemesterClassroom> _semesterClassrooms = [];
  List<SemesterClassroom> get semesterClassrooms => _semesterClassrooms;

  /// 当前选中的周次（用于学期总览）
  int _selectedWeek = 1;
  int get selectedWeek => _selectedWeek;

  /// 是否有学期课表数据
  bool get hasSemesterData => _semesterClassrooms.isNotEmpty;

  /// 设置选中的周次
  void setSelectedWeek(int week) {
    if (week >= 1 && week <= 18) {
      _selectedWeek = week;
      notifyListeners();
    }
  }

  /// 加载学期课表数据
  Future<void> loadSemesterClassrooms(List<SemesterClassroom> classrooms) async {
    _semesterClassrooms = classrooms;
    notifyListeners();
    // 保存到本地存储
    await _storageService.saveSemesterClassrooms(classrooms);
  }

  /// 从存储加载学期课表数据
  Future<void> loadSemesterDataFromStorage() async {
    _semesterClassrooms = await _storageService.getSemesterClassrooms();
    notifyListeners();
  }

  /// 清除学期课表数据
  Future<void> clearSemesterData() async {
    _semesterClassrooms = [];
    _selectedWeek = 1;
    notifyListeners();
    await _storageService.clearSemesterClassrooms();
  }

  /// 导入学期课表（Web版）- 同步版本
  Future<void> parseSemesterExcelBytes(Uint8List bytes) async {
    _isLoading = true;
    notifyListeners();

    try {
      final classrooms = SemesterExcelParser.parseSemesterExcel(bytes);
      await loadSemesterClassrooms(classrooms);
      _error = null;
    } catch (e) {
      _error = '学期课表解析失败: $e';
      throw Exception(_error);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// 导入学期课表（Web版）- 异步分批版本，带进度回调
  /// [onProgress] - 进度回调 (current, total, message)
  Future<void> parseSemesterExcelBytesAsync(
    Uint8List bytes, {
    required void Function(int current, int total, String message) onProgress,
  }) async {
    _isLoading = true;
    notifyListeners();

    try {
      final classrooms = await SemesterExcelParser.parseSemesterExcelAsync(
        bytes,
        onProgress: onProgress,
      );
      await loadSemesterClassrooms(classrooms);
      _error = null;
    } catch (e) {
      _error = '学期课表解析失败: $e';
      throw Exception(_error);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// 导入学期课表 JSON 文件
  Future<void> parseSemesterJsonBytes(Uint8List bytes) async {
    _isLoading = true;
    notifyListeners();

    try {
      final classrooms = SemesterJsonParser.parseSemesterJson(bytes);
      await loadSemesterClassrooms(classrooms);
      _error = null;
    } catch (e) {
      _error = '学期课表 JSON 解析失败: $e';
      throw Exception(_error);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// 从文件路径导入学期课表（iOS/Android使用）
  Future<void> parseSemesterExcelFile(
    String filePath, {
    required void Function(int current, int total, String message) onProgress,
  }) async {
    final bytes = await File(filePath).readAsBytes();
    return parseSemesterExcelBytesAsync(bytes, onProgress: onProgress);
  }

  /// 从文件路径导入学期课表 JSON（iOS/Android使用）
  Future<void> parseSemesterJsonFile(String filePath) async {
    final bytes = await File(filePath).readAsBytes();
    return parseSemesterJsonBytes(bytes);
  }
}
