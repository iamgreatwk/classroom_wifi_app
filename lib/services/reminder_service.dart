import '../models/reminder.dart';

/// 提醒通知服务
/// Web版本：仅保留数据结构，不实际发送通知
class ReminderService {
  static final ReminderService _instance = ReminderService._internal();
  factory ReminderService() => _instance;
  ReminderService._internal();

  bool _isInitialized = false;

  /// 初始化通知服务
  Future<void> init() async {
    _isInitialized = true;
  }

  /// 请求通知权限
  Future<bool> requestPermission() async {
    // Web平台直接返回false
    return false;
  }

  /// 显示即时通知
  Future<void> showNotification({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {
    // Web平台不发送通知
    return;
  }

  /// 调度每日定时通知
  Future<void> scheduleDailyNotification({
    required int id,
    required String title,
    required String body,
    required int hour,
    required int minute,
  }) async {
    // Web平台不调度
    return;
  }

  /// 取消指定通知
  Future<void> cancelNotification(int id) async {
    // Web平台不做任何操作
    return;
  }

  /// 取消所有通知
  Future<void> cancelAllNotifications() async {
    // Web平台不做任何操作
    return;
  }

  /// 调度所有固定提醒
  Future<void> scheduleAllFixedReminders(Set<int> enabledReminderIds) async {
    // Web平台不调度
    return;
  }

  /// 调度自定义提醒
  Future<void> scheduleCustomReminder(CustomReminder reminder) async {
    // Web平台不调度
    return;
  }

  /// 调度单次定时通知
  Future<void> scheduleOneTimeNotification({
    required int id,
    required String title,
    required String body,
    required int year,
    required int month,
    required int day,
    required int hour,
    required int minute,
  }) async {
    // Web平台不调度
    return;
  }

  /// 取消自定义提醒
  Future<void> cancelCustomReminder(CustomReminder reminder) async {
    // Web平台不做任何操作
    return;
  }
}
