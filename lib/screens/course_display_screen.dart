import 'package:flutter/material.dart';
import '../models/course.dart';
import '../services/excel_parser_service.dart';

/// 课程显示界面
class CourseDisplayScreen extends StatefulWidget {
  final Classroom classroom;

  const CourseDisplayScreen({super.key, required this.classroom});

  @override
  State<CourseDisplayScreen> createState() => _CourseDisplayScreenState();
}

class _CourseDisplayScreenState extends State<CourseDisplayScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // 星期列表
  static const List<String> _weekdays = [
    '星期一',
    '星期二',
    '星期三',
    '星期四',
    '星期五',
    '星期六',
    '星期日',
  ];

  @override
  void initState() {
    super.initState();
    // 默认显示今天
    final today = DateTime.now();
    final weekdayIndex = today.weekday - 1; // 0 = Monday
    _tabController = TabController(length: 7, vsync: this, initialIndex: weekdayIndex);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.classroom.name),
        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: _weekdays.map((wd) => Tab(text: wd)).toList(),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: _weekdays.map((wd) => _buildDaySchedule(wd)).toList(),
      ),
    );
  }

  /// 构建某天的课程表
  Widget _buildDaySchedule(String weekday) {
    final courses = widget.classroom.getCoursesForDay(weekday);
    final today = ExcelParserService.getWeekdayName(DateTime.now());
    final isToday = weekday == today;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 标题
          if (isToday)
            Container(
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.today,
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '今日课程',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                    ),
                  ),
                ],
              ),
            ),

          // 无课程提示
          if (courses.isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  children: [
                    Icon(
                      Icons.event_available,
                      size: 64,
                      color: Colors.grey[400],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      '今天没有课程',
                      style: TextStyle(
                        fontSize: 18,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            // 课程列表
            ...List.generate(12, (index) {
              final period = index + 1;
              final course = widget.classroom.getCourseAtPeriod(weekday, period);

              return _buildPeriodCard(period, course, isToday);
            }),
        ],
      ),
    );
  }

  /// 构建单节课卡片
  Widget _buildPeriodCard(int period, Course? course, bool isToday) {
    final now = DateTime.now();
    final currentPeriod = ExcelParserService.getCurrentPeriod(now);
    final isCurrentPeriod = isToday && period == currentPeriod;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: isCurrentPeriod
          ? Theme.of(context).colorScheme.secondaryContainer
          : course != null
              ? null
              : Colors.grey[100],
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            // 节次
            Container(
              width: 50,
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: isCurrentPeriod
                    ? Theme.of(context).colorScheme.secondary
                    : Theme.of(context).colorScheme.primary,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                children: [
                  Text(
                    '第$period',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    '节',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.8),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            // 课程信息
            Expanded(
              child: course != null
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          course.displayName,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: isCurrentPeriod ? FontWeight.bold : FontWeight.w500,
                          ),
                        ),
                        if (isCurrentPeriod)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.secondary,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Text(
                                '正在上课',
                                style: TextStyle(color: Colors.white, fontSize: 12),
                              ),
                            ),
                          ),
                      ],
                    )
                  : Text(
                      '无课',
                      style: TextStyle(color: Colors.grey[500]),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
