/// WiFi信息模型
class WifiInfo {
  final String ssid;
  final String bssid;
  final int signalStrength;

  WifiInfo({
    required this.ssid,
    required this.bssid,
    required this.signalStrength,
  });

  /// 获取显示名称（优先使用SSID，如果没有则显示BSSID）
  String get displayName => ssid.isNotEmpty ? ssid : bssid;
}

/// WiFi检测服务
/// Web版本：仅返回空列表，因为Web无法扫描WiFi
class WifiService {
  static final WifiService _instance = WifiService._internal();
  factory WifiService() => _instance;
  WifiService._internal();

  /// 扫描结果回调
  Function(List<WifiInfo>)? onScanResult;

  /// 开始WiFi扫描
  /// Web平台返回空列表
  Future<List<WifiInfo>> scanWifi() async {
    // Web平台不支持WiFi扫描
    return [];
  }

  /// 获取指定WiFi的信号强度
  Future<int?> getWifiSignalStrength(String bssid) async {
    // Web平台不支持
    return null;
  }

  /// 查找信号最强的WiFi
  Future<WifiInfo?> findStrongestWifi() async {
    // Web平台不支持
    return null;
  }

  /// 启动定时扫描
  void startPeriodicScan(Duration interval, Function(List<WifiInfo>) callback) {
    // Web平台不支持，不做任何操作
  }

  /// 停止扫描
  void stopScan() {
    // Web平台不支持，不做任何操作
  }

  /// 清理资源
  void dispose() {
    stopScan();
  }
}
