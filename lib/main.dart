import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/app_provider.dart';
import 'screens/reminder_screen.dart';
import 'screens/overview_screen.dart';

void main() {
  runApp(const ClassroomWifiApp());
}

class ClassroomWifiApp extends StatelessWidget {
  const ClassroomWifiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AppProvider(),
      child: MaterialApp(
        title: '手机课表',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.blue,
            brightness: Brightness.light,
          ),
          useMaterial3: true,
        ),
        home: const MainScreen(),
      ),
    );
  }
}

/// 主屏幕（带底部导航栏）
class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> with WidgetsBindingObserver {
  int _currentIndex = 0; // 默认显示总览页面
  Timer? _reminderTimer;
  
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // 启动定时检查提醒
    _startReminderCheck();
  }
  
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _reminderTimer?.cancel();
    super.dispose();
  }
  
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // App 恢复到前台时立即检查
    if (state == AppLifecycleState.resumed) {
      _checkReminder();
    }
  }
  
  void _startReminderCheck() {
    // 每30秒检查一次是否有提醒需要触发
    _reminderTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _checkReminder();
    });
  }
  
  void _checkReminder() {
    final provider = Provider.of<AppProvider>(context, listen: false);
    if (provider.checkAndTriggerReminder()) {
      // 有提醒触发，显示弹窗
      _showReminderDialog(provider);
    }
  }
  
  void _showReminderDialog(AppProvider provider) {
    final triggering = provider.getTriggingReminders();
    if (triggering.isEmpty) return;
    
    final reminder = triggering.first;
    String title;
    String content;
    
    if (reminder['type'] == 'fixed') {
      title = '课表提醒';
      content = reminder['description'] as String? ?? reminder['name'] as String;
    } else {
      title = '提醒';
      content = reminder['content'] as String;
    }
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.alarm, size: 48, color: Colors.orange),
        title: Text(title),
        content: Text(content, style: const TextStyle(fontSize: 18)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: [
        const OverviewScreen(),
        const ReminderScreen(),
      ][_currentIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.grid_view_outlined),
            selectedIcon: Icon(Icons.grid_view),
            label: '总览',
          ),
          NavigationDestination(
            icon: Icon(Icons.visibility_outlined),
            selectedIcon: Icon(Icons.visibility),
            label: '查看',
          ),
        ],
      ),
    );
  }
}

