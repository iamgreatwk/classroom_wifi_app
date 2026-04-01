import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_provider.dart';
import '../models/course.dart';
import '../services/wifi_service.dart';

/// WiFi设置界面
class WifiSettingsScreen extends StatefulWidget {
  const WifiSettingsScreen({super.key});

  @override
  State<WifiSettingsScreen> createState() => _WifiSettingsScreenState();
}

class _WifiSettingsScreenState extends State<WifiSettingsScreen> {
  @override
  void initState() {
    super.initState();
    // 开始扫描WiFi
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AppProvider>().startWifiScan();
    });
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('WiFi设置'),
        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
      ),
      body: Consumer<AppProvider>(
        builder: (context, provider, _) {
          return Column(
            children: [
              // 已设置的映射列表
              Expanded(
                flex: 2,
                child: _buildMappingsList(provider),
              ),
              const Divider(height: 1),
              // 检测到的WiFi列表
              Expanded(
                flex: 3,
                child: _buildDetectedWifiList(provider),
              ),
            ],
          );
        },
      ),
    );
  }

  /// 已设置的映射列表
  Widget _buildMappingsList(AppProvider provider) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(Icons.link, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 8),
              const Text(
                '已设置的WiFi-教室映射',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
        if (provider.wifiMappings.isEmpty)
          const Expanded(
            child: Center(
              child: Text(
                '尚未设置任何WiFi映射\n点击下方检测到的WiFi添加',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
              ),
            ),
          )
        else
          Expanded(
            child: ListView.builder(
              itemCount: provider.wifiMappings.length,
              itemBuilder: (context, index) {
                final mapping = provider.wifiMappings[index];
                return ListTile(
                  leading: const Icon(Icons.wifi),
                  title: Text(mapping.displayName),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('BSSID: ${mapping.bssid}'),
                      Text('教室: ${mapping.classroomName}'),
                    ],
                  ),
                  isThreeLine: true,
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (mapping.lastRssi != null)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: _getSignalColor(mapping.lastRssi!),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '${mapping.lastRssi} dBm',
                            style: const TextStyle(color: Colors.white, fontSize: 12),
                          ),
                        ),
                      IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () => _confirmDelete(mapping),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
      ],
    );
  }

  /// 检测到的WiFi列表
  Widget _buildDetectedWifiList(AppProvider provider) {
    final wifiList = provider.getDetectedWifiList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(Icons.wifi_find, color: Theme.of(context).colorScheme.secondary),
              const SizedBox(width: 8),
              const Text(
                '检测到的WiFi',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              if (provider.isScanning)
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: () => provider.startWifiScan(),
              ),
            ],
          ),
        ),
        Expanded(
          child: wifiList.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 16),
                      Text('正在扫描WiFi...'),
                    ],
                  ),
                )
              : ListView.builder(
                  itemCount: wifiList.length,
                  itemBuilder: (context, index) {
                    final wifi = wifiList[index];
                    final isMapped = provider.wifiMappings.any((m) => m.bssid == wifi.bssid);

                    return ListTile(
                      leading: Icon(
                        Icons.wifi,
                        color: isMapped ? Colors.green : null,
                      ),
                      title: Text(wifi.ssid.isNotEmpty ? wifi.ssid : '(无名称)'),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('BSSID: ${wifi.bssid}'),
                          Text('信号: ${wifi.signalStrength} dBm'),
                        ],
                      ),
                      isThreeLine: true,
                      trailing: isMapped
                          ? const Chip(label: Text('已映射'))
                          : ElevatedButton(
                              onPressed: () => _showAddMappingDialog(wifi),
                              child: const Text('添加'),
                            ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  /// 确认删除对话框
  void _confirmDelete(WifiClassroomMapping mapping) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要删除 "${mapping.displayName}" 的映射吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              context.read<AppProvider>().removeWifiMapping(mapping.bssid);
              Navigator.pop(context);
            },
            child: const Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  /// 显示添加映射对话框
  void _showAddMappingDialog(WifiInfo wifi) {
    final provider = context.read<AppProvider>();
    String? selectedClassroom;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('添加WiFi映射'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('WiFi名称: ${wifi.ssid.isNotEmpty ? wifi.ssid : "(无名称)"}'),
              const SizedBox(height: 4),
              Text('BSSID: ${wifi.bssid}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
              const SizedBox(height: 16),
              const Text('选择对应的教室:'),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: selectedClassroom,
                isExpanded: true,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                items: provider.classrooms.map((c) {
                  return DropdownMenuItem(
                    value: c.name,
                    child: Text(c.name),
                  );
                }).toList(),
                onChanged: (value) {
                  setDialogState(() {
                    selectedClassroom = value;
                  });
                },
              ),
              if (provider.classrooms.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    '请先导入课表',
                    style: TextStyle(color: Colors.red),
                  ),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            ElevatedButton(
              onPressed: selectedClassroom == null || provider.classrooms.isEmpty
                  ? null
                  : () {
                      provider.addWifiMapping(wifi.bssid, wifi.ssid, selectedClassroom!);
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('已添加 ${wifi.displayName} -> $selectedClassroom')),
                      );
                    },
              child: const Text('添加'),
            ),
          ],
        ),
      ),
    );
  }

  /// 根据信号强度获取颜色
  Color _getSignalColor(int rssi) {
    if (rssi >= -50) return Colors.green;
    if (rssi >= -60) return Colors.lightGreen;
    if (rssi >= -70) return Colors.yellow;
    if (rssi >= -80) return Colors.orange;
    return Colors.red;
  }
}
