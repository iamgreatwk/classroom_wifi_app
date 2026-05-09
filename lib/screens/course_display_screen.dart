import 'package:flutter/material.dart';
import '../models/course.dart';
import '../services/excel_parser_service.dart';

/// 课程显示界面
class CourseDisplayScreen extends StatefulWidget {
  final Classroom classroom;
  final String? initialWeekday;
  final int? initialPeriod;

  const CourseDisplayScreen({
    super.key,
    required this.classroom,
    this.initialWeekday,
    this.initialPeriod,
  });

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
    // 根据传入的参数或默认显示今天
    int initialIndex;
    if (widget.initialWeekday != null) {
      initialIndex = _weekdays.indexOf(widget.initialWeekday!);
      if (initialIndex < 0) initialIndex = DateTime.now().weekday - 1;
    } else {
      initialIndex = DateTime.now().weekday - 1; // 0 = Monday
    }
    _tabController = TabController(length: 7, vsync: this, initialIndex: initialIndex);
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

              return _buildPeriodCard(period, course, isToday, weekday);
            }),
        ],
      ),
    );
  }

  /// 构建单节课卡片
  Widget _buildPeriodCard(int period, Course? course, bool isToday, String weekday) {
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
      child: InkWell(
        onTap: course != null ? () => _showCourseDetailDialog(course, period, weekday) : null,
        borderRadius: BorderRadius.circular(12),
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
              if (course != null)
                const Icon(Icons.chevron_right, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }

  /// 显示课程详情弹窗
  void _showCourseDetailDialog(Course course, int period, String weekday) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400, maxHeight: 600),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 标题栏
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '课程详情',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).colorScheme.onPrimaryContainer,
                            ),
                          ),
                          Text(
                            '${widget.classroom.name} - $weekday 第$period节',
                            style: TextStyle(
                              fontSize: 14,
                              color: Theme.of(context).colorScheme.onPrimaryContainer.withOpacity(0.8),
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
              // 内容区域
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 结构化信息
                      _buildInfoCard(
                        title: '课程信息',
                        icon: Icons.book,
                        items: [
                          _InfoItem('课程名称', course.name),
                          if (course.teacher != null && course.teacher!.isNotEmpty)
                            _InfoItem('授课老师', course.teacher!),
                          _InfoItem('上课时间', '$weekday 第$period节'),
                          _InfoItem('上课地点', widget.classroom.name),
                        ],
                      ),
                      const SizedBox(height: 16),
                      // 原始数据
                      _buildInfoCard(
                        title: '原始数据',
                        icon: Icons.raw_on,
                        items: [
                          _InfoItem('课程原始文本', course.rawText ?? course.displayName),
                          if (course.teacher != null)
                            _InfoItem('老师原始文本', course.teacher!),
                        ],
                        isRaw: true,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 构建信息卡片
  Widget _buildInfoCard({
    required String title,
    required IconData icon,
    required List<_InfoItem> items,
    bool isRaw = false,
  }) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isRaw ? Colors.orange.shade200 : Colors.grey.shade300,
        ),
      ),
      color: isRaw ? Colors.orange.shade50 : Colors.grey.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  icon,
                  size: 20,
                  color: isRaw ? Colors.orange : Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: isRaw ? Colors.orange.shade800 : null,
                  ),
                ),
              ],
            ),
            const Divider(height: 24),
            ...items.map((item) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.label,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    item.value,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            )),
          ],
        ),
      ),
    );
  }
}

/// 信息项数据类
class _InfoItem {
  final String label;
  final String value;

  _InfoItem(this.label, this.value);
}
