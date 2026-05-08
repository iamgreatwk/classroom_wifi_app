import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import '../models/reminder.dart';
import '../models/course.dart';
import '../providers/app_provider.dart';
import '../config.dart';

/// 查看页面（导入课表 + 筛选查看教室）
class ReminderScreen extends StatelessWidget {
  const ReminderScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('查看'),
        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
      ),
      body: Consumer<AppProvider>(
        builder: (context, provider, _) {
          // 筛选查看配置：排除 id 6 (12:10) 和 id 13 (21:05)
          final viewConfigs = FixedReminderConfig.all
              .where((c) => c.id != 6 && c.id != 13)
              .toList();

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // 筛选查看部分
              _buildSectionHeader(context, '筛选查看', Icons.filter_list),
              const SizedBox(height: 8),
              Card(
                child: Column(
                  children: viewConfigs.map((config) {
                    return _buildViewTile(context, provider, config);
                  }).toList(),
                ),
              ),
              const SizedBox(height: 24),

              // 导入课表部分
              _buildSectionHeader(context, '导入课表', Icons.table_chart),
              const SizedBox(height: 8),
              _buildImportCard(context, provider),
              const SizedBox(height: 24),

              // 导入学期课表部分
              _buildSectionHeader(context, '学期课表', Icons.calendar_month),
              const SizedBox(height: 8),
              _buildSemesterImportCard(context, provider),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }

  /// 导入课表卡片
  Widget _buildImportCard(BuildContext context, AppProvider provider) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              provider.classrooms.isEmpty
                  ? '尚未导入课表，请点击下方按钮导入 Excel 课表文件'
                  : '已导入 ${provider.classrooms.length} 个教室的课表',
              style: TextStyle(color: Colors.grey[600]),
            ),
            const SizedBox(height: 12),
            // 周一至周六课表导入
            _ImportButton(
              label: '导入周一至周六',
              icon: Icons.calendar_today,
              isSunday: false,
            ),
            const SizedBox(height: 8),
            // 周日课表导入
            _ImportButton(
              label: '导入周日',
              icon: Icons.calendar_view_day,
              isSunday: true,
              outlined: true,
            ),
          ],
        ),
      ),
    );
  }

  /// 学期课表导入卡片
  Widget _buildSemesterImportCard(BuildContext context, AppProvider provider) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              provider.hasSemesterData
                  ? '已导入学期课表，共 ${provider.semesterClassrooms.length} 个教室'
                  : '导入整学期课表，可查看每周每天的课程安排',
              style: TextStyle(color: Colors.grey[600]),
            ),
            const SizedBox(height: 12),
            // 导入学期课表按钮（Excel）
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => _pickSemesterExcelFile(context, provider),
                icon: const Icon(Icons.upload_file),
                label: Text(provider.hasSemesterData ? '重新导入学期课表 (Excel)' : '导入学期课表 (Excel)'),
              ),
            ),
            const SizedBox(height: 8),
            // 导入学期课表按钮（JSON）
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _pickSemesterJsonFile(context, provider),
                icon: const Icon(Icons.code),
                label: const Text('导入学期课表 (JSON)'),
              ),
            ),
            if (provider.hasSemesterData) ...[
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => _clearSemesterData(context, provider),
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('清除学期课表'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 选择学期课表Excel文件（带进度对话框）
  Future<void> _pickSemesterExcelFile(BuildContext context, AppProvider provider) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xls'],
      );

      if (result != null && result.files.isNotEmpty) {
        final file = result.files.single;

        if (file.bytes != null) {
          // 使用 Stream 来传递进度，支持对话框内实时更新
          final progressController = StreamController<Map<String, dynamic>>.broadcast();

          // 显示进度对话框
          if (context.mounted) {
            showDialog(
              context: context,
              barrierDismissible: false,
              builder: (dialogContext) => StreamBuilder<Map<String, dynamic>>(
                stream: progressController.stream,
                initialData: {'progress': 0.0, 'message': '准备导入...'},
                builder: (context, snapshot) {
                  final data = snapshot.data ?? {'progress': 0.0, 'message': '准备导入...'};
                  final progress = (data['progress'] as num).toDouble();
                  final message = data['message'] as String;

                  return PopScope(
                    canPop: false,
                    child: AlertDialog(
                      title: const Row(
                        children: [
                          SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          SizedBox(width: 12),
                          Text('正在导入...'),
                        ],
                      ),
                      content: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(message),
                          const SizedBox(height: 16),
                          LinearProgressIndicator(
                            value: progress > 0 ? progress : null,
                            minHeight: 8,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '${(progress * 100).toInt()}%',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            );
          }

          try {
            // 使用异步分批解析
            await provider.parseSemesterExcelBytesAsync(
              file.bytes!,
              onProgress: (current, total, message) {
                progressController.add({
                  'progress': current / total,
                  'message': message,
                });
              },
            );

            await progressController.close();

            // 关闭进度对话框
            if (context.mounted) {
              Navigator.of(context).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('学期课表导入成功！')),
              );
            }
          } catch (e) {
            await progressController.close();
            // 关闭进度对话框
            if (context.mounted) {
              Navigator.of(context).pop();
            }
            throw e;
          }
        } else {
          throw Exception('无法读取文件内容');
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导入失败: $e')),
        );
      }
    }
  }

  /// 选择学期课表 JSON 文件
  Future<void> _pickSemesterJsonFile(BuildContext context, AppProvider provider) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );

      if (result != null && result.files.isNotEmpty) {
        final file = result.files.single;

        if (file.bytes != null) {
          // 显示进度对话框
          if (context.mounted) {
            showDialog(
              context: context,
              barrierDismissible: false,
              builder: (dialogContext) => const PopScope(
                canPop: false,
                child: AlertDialog(
                  title: Row(
                    children: [
                      SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      SizedBox(width: 12),
                      Text('正在导入 JSON...'),
                    ],
                  ),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('正在解析 JSON 数据...'),
                      SizedBox(height: 16),
                      LinearProgressIndicator(),
                    ],
                  ),
                ),
              ),
            );
          }

          try {
            // 使用 JSON 解析器
            await provider.parseSemesterJsonBytes(file.bytes!);

            // 关闭进度对话框
            if (context.mounted) {
              Navigator.of(context).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('学期课表 JSON 导入成功！')),
              );
            }
          } catch (e) {
            // 关闭进度对话框
            if (context.mounted) {
              Navigator.of(context).pop();
            }
            throw e;
          }
        } else {
          throw Exception('无法读取文件内容');
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('JSON 导入失败: $e')),
        );
      }
    }
  }

  /// 清除学期课表数据
  Future<void> _clearSemesterData(BuildContext context, AppProvider provider) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认清除'),
        content: const Text('确定要清除学期课表数据吗？此操作不可恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('清除'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await provider.clearSemesterData();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('学期课表已清除')),
        );
      }
    }
  }

  /// 筛选查看项
  Widget _buildViewTile(BuildContext context, AppProvider provider, FixedReminderConfig config) {
    IconData leadingIcon;
    Color iconColor;

    if (config.isAttendanceCheck) {
      leadingIcon = Icons.person_off;
      iconColor = Colors.orange;
    } else if (config.isTeacherDiff) {
      leadingIcon = Icons.person_search;
      iconColor = Colors.purple;
    } else if (config.isCourseCheck) {
      leadingIcon = Icons.check_circle_outline;
      iconColor = Colors.teal;
    } else {
      leadingIcon = Icons.class_;
      iconColor = Colors.blue;
    }

    return ListTile(
      leading: Icon(leadingIcon, color: iconColor),
      title: Text(config.name),
      subtitle: Text(config.description, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => _showClassroomsDialog(context, provider, config),
    );
  }

  /// 解析老师名字符串，处理多老师情况
  /// 支持分隔符：/ , 、，以及空格（外文名）
  List<String> _parseTeachers(String teacherStr) {
    if (teacherStr.isEmpty) return [];
    
    // 先按常见分隔符分割
    final separators = RegExp(r'[/,，、]');
    if (teacherStr.contains(separators)) {
      return teacherStr
          .split(separators)
          .map((t) => t.trim())
          .where((t) => t.isNotEmpty)
          .toList();
    }
    
    // 单个老师
    return [teacherStr.trim()];
  }
  
  /// 判断两个老师名是否相同（忽略大小写和空格）
  bool _isSameTeacher(String t1, String t2) {
    final normalized1 = t1.toLowerCase().replaceAll(RegExp(r'\s+'), '');
    final normalized2 = t2.toLowerCase().replaceAll(RegExp(r'\s+'), '');
    return normalized1 == normalized2;
  }

  /// 获取节次范围的文字描述
  String _getPeriodsText(List<int> periods) {
    if (periods.isEmpty) return '';
    if (periods.length == 1) return '第${periods[0]}节';
    if (periods.length == 2) return '第${periods[0]}-${periods[1]}节';
    return '第${periods.first}-${periods.last}节';
  }

  /// 显示教室列表对话框
  void _showClassroomsDialog(BuildContext context, AppProvider provider, FixedReminderConfig config) {
    final periods = config.periods ?? [];
    final isTeacherDiff = config.isTeacherDiff;
    final isAttendanceCheck = config.isAttendanceCheck;
    final isCourseCheck = config.isCourseCheck;
    final now = DateTime.now();
    const weekdayMap = {
      'Monday': '星期一',
      'Tuesday': '星期二',
      'Wednesday': '星期三',
      'Thursday': '星期四',
      'Friday': '星期五',
      'Saturday': '星期六',
      'Sunday': '星期日',
    };
    final weekdayEn = ['Monday','Tuesday','Wednesday','Thursday','Friday','Saturday','Sunday'][now.weekday - 1];
    final chineseWeekday = weekdayMap[weekdayEn] ?? weekdayEn;

    // 获取当前选中的所有分页，默认为"2楼大"
    final selectedPages = provider.selectedOverviewPages.isNotEmpty
        ? provider.selectedOverviewPages
        : {'2楼大'};
    final selectedPageNames = selectedPages.join('、');

    List<Classroom> classroomsToShow = [];
    String dialogTitle = '${config.name}（$selectedPageNames）';
    String emptyMessage = '今日对应时段没有课程';

    // 先根据分页过滤教室（合并所有选中分页）
    List<Classroom> filteredByPage = provider.classrooms.where((c) {
      return selectedPages.any((page) => provider.isClassroomInPage(c.name, page));
    }).toList();

    if (isAttendanceCheck) {
      // 确认缺勤：显示该时段有课的教室
      classroomsToShow = filteredByPage.where((c) {
        return c.hasCourseInPeriods(chineseWeekday, periods);
      }).toList();
      emptyMessage = '今日对应时段没有课程';
    } else if (isCourseCheck && config.prevPeriods != null) {
      // 有课检查：
      // 9:40 - 1、2节缺勤且3、4节有课（且2、3节老师不同），或1、2节无课但3、4节有课
      // 15:10 - 6、7节缺勤且8、9节有课（且7、8节老师不同），或6、7节无课但8、9节有课
      final prevPeriods = config.prevPeriods!;
      final absentClassrooms = provider.getAbsentClassroomsForRelatedReminder(config.relatedReminderId);
      
      // 获取边界节次用于判断老师是否相同（9:40检查2、3节，15:10检查7、8节）
      final boundaryPeriod1 = prevPeriods.last; // 2或7
      final boundaryPeriod2 = periods.first;    // 3或8

      classroomsToShow = filteredByPage.where((c) {
        final hasPrevCourse = c.hasCourseInPeriods(chineseWeekday, prevPeriods);
        final hasCurrentCourse = c.hasCourseInPeriods(chineseWeekday, periods);
        final isAbsent = absentClassrooms.contains(c.name);

        // 检查边界节次（2、3节或7、8节）的老师是否不同
        final course1 = c.getCourseAtPeriod(chineseWeekday, boundaryPeriod1);
        final course2 = c.getCourseAtPeriod(chineseWeekday, boundaryPeriod2);
        final teachers1 = course1 != null ? _parseTeachers(course1.teacher ?? '') : [];
        final teachers2 = course2 != null ? _parseTeachers(course2.teacher ?? '') : [];
        
        // 判断老师是否相同（有共同老师则认为相同）
        final hasCommonTeacher = teachers1.isNotEmpty && teachers2.isNotEmpty &&
            teachers1.any((t1) => teachers2.any((t2) => _isSameTeacher(t1, t2)));

        // 条件1：前序节次有课且缺勤，且当前节次有课，且老师不同
        // 条件2：前序节次无课但当前节次有课
        if (hasPrevCourse && isAbsent && hasCurrentCourse) {
          // 前序节次有课且缺勤的情况：需要老师不同
          return !hasCommonTeacher;
        }
        // 前序节次无课的情况：直接显示
        return hasCurrentCourse && !hasPrevCourse;
      }).toList();

      emptyMessage = '没有符合条件的教室';
    } else if (isTeacherDiff && periods.length >= 2) {
      // 老师不同
      final period1 = periods[0];
      final period2 = periods[1];

      classroomsToShow = filteredByPage.where((classroom) {
        final course1 = classroom.getCourseAtPeriod(chineseWeekday, period1);
        final course2 = classroom.getCourseAtPeriod(chineseWeekday, period2);

        if (course1 != null && course2 != null) {
          final teacher1 = course1.teacher ?? '';
          final teacher2 = course2.teacher ?? '';
          
          // 处理多老师情况：按常见分隔符分割老师名
          final teachers1 = _parseTeachers(teacher1);
          final teachers2 = _parseTeachers(teacher2);
          
          // 如果任一方没有老师信息，不认为是老师不同
          if (teachers1.isEmpty || teachers2.isEmpty) {
            return false;
          }
          
          // 检查两组老师是否有交集（有交集说明有相同老师，不算"不同"）
          // 如果两组老师完全不同，则认为老师不同
          final hasCommonTeacher = teachers1.any((t1) => 
            teachers2.any((t2) => _isSameTeacher(t1, t2))
          );
          
          return !hasCommonTeacher;
        }
        return false;
      }).toList();
      emptyMessage = '今日没有老师不同的教室';
    } else {
      // 普通有课教室
      classroomsToShow = filteredByPage.where((c) {
        return c.hasCourseInPeriods(chineseWeekday, periods);
      }).toList();
    }

    if (classroomsToShow.isEmpty) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(dialogTitle),
          content: Text(emptyMessage),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('确定'),
            ),
          ],
        ),
      );
      return;
    }

    classroomsToShow.sort((a, b) => a.name.compareTo(b.name));

    // 缺勤确认使用有状态对话框
    if (isAttendanceCheck) {
      _showAttendanceDialog(context, provider, config, classroomsToShow, chineseWeekday, periods);
      return;
    }

    // 其他类型使用简单查看对话框
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(dialogTitle),
        contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '今日 $chineseWeekday',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text('共 ${classroomsToShow.length} 个教室',
                  style: const TextStyle(color: Colors.grey)),
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.4,
                ),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: classroomsToShow.length,
                  itemBuilder: (context, index) {
                    final classroom = classroomsToShow[index];
                    final classroomNumber = classroom.name.replaceAll(RegExp(r'[^0-9]'), '');

                    // 老师不同：显示课程和老师
                    if (isTeacherDiff && periods.length >= 2) {
                      final course1 = classroom.getCourseAtPeriod(chineseWeekday, periods[0]);
                      final course2 = classroom.getCourseAtPeriod(chineseWeekday, periods[1]);
                      return Card(
                        margin: const EdgeInsets.symmetric(vertical: 2),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                classroomNumber,
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '第${periods[0]}节: ${course1?.name ?? '-'} - ${course1?.teacher ?? '-'}',
                                style: const TextStyle(fontSize: 12),
                              ),
                              Text(
                                '第${periods[1]}节: ${course2?.name ?? '-'} - ${course2?.teacher ?? '-'}',
                                style: const TextStyle(fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                      );
                    }

                    // 普通查看：只显示教室编号
                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 2),
                      child: ListTile(
                        dense: true,
                        title: Text(classroomNumber),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  /// 显示缺勤确认对话框（可勾选）
  void _showAttendanceDialog(
    BuildContext context,
    AppProvider provider,
    FixedReminderConfig config,
    List<Classroom> classrooms,
    String chineseWeekday,
    List<int> periods,
  ) {
    showDialog(
      context: context,
      builder: (context) => _AttendanceCheckDialog(
        config: config,
        classrooms: classrooms,
        chineseWeekday: chineseWeekday,
        periods: periods,
        provider: provider,
      ),
    );
  }
}

/// 缺勤确认对话框（有状态）
class _AttendanceCheckDialog extends StatefulWidget {
  final FixedReminderConfig config;
  final List<Classroom> classrooms;
  final String chineseWeekday;
  final List<int> periods;
  final AppProvider provider;

  const _AttendanceCheckDialog({
    required this.config,
    required this.classrooms,
    required this.chineseWeekday,
    required this.periods,
    required this.provider,
  });

  @override
  State<_AttendanceCheckDialog> createState() => _AttendanceCheckDialogState();
}

class _AttendanceCheckDialogState extends State<_AttendanceCheckDialog> {
  late Set<String> _selectedClassrooms;

  @override
  void initState() {
    super.initState();
    // 初始化时加载已保存的缺勤记录
    final absentClassrooms = widget.provider.getAbsentClassroomsForRelatedReminder(widget.config.id);
    _selectedClassrooms = Set<String>.from(absentClassrooms);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.config.name),
      contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '今日 ${widget.chineseWeekday} ${_getPeriodsText(widget.periods)}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              '共 ${widget.classrooms.length} 个教室，请勾选缺勤的教室',
              style: const TextStyle(color: Colors.grey, fontSize: 12),
            ),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.4,
              ),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: widget.classrooms.length,
                itemBuilder: (context, index) {
                  final classroom = widget.classrooms[index];
                  final classroomNumber = classroom.name.replaceAll(RegExp(r'[^0-9]'), '');
                  final isSelected = _selectedClassrooms.contains(classroom.name);

                  return Card(
                    margin: const EdgeInsets.symmetric(vertical: 2),
                    child: CheckboxListTile(
                      dense: true,
                      title: Text(classroomNumber),
                      value: isSelected,
                      onChanged: (checked) {
                        setState(() {
                          if (checked == true) {
                            _selectedClassrooms.add(classroom.name);
                          } else {
                            _selectedClassrooms.remove(classroom.name);
                          }
                        });
                      },
                    ),
                  );
                },
              ),
            ),
            if (_selectedClassrooms.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  '已选择 ${_selectedClassrooms.length} 个教室',
                  style: TextStyle(
                    color: Colors.orange[700],
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        ElevatedButton(
          onPressed: () async {
            // 保存缺勤记录到 provider（包括空选择，即清空缺勤记录）
            await widget.provider.saveAbsentClassrooms(
              widget.config.id,
              _selectedClassrooms,
            );
            Navigator.pop(context);
            if (_selectedClassrooms.isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('已清空缺勤记录')),
              );
            } else {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('已确认 ${_selectedClassrooms.length} 个教室缺勤')),
              );
            }
          },
          child: const Text('确认'),
        ),
      ],
    );
  }

  String _getPeriodsText(List<int> periods) {
    if (periods.isEmpty) return '';
    if (periods.length == 1) return '第${periods[0]}节';
    if (periods.length == 2) return '第${periods[0]}-${periods[1]}节';
    return '第${periods.first}-${periods.last}节';
  }
}

/// 导入按钮（独立Widget以支持StatefulBuilder）
class _ImportButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isSunday;
  final bool outlined;

  const _ImportButton({
    required this.label,
    required this.icon,
    required this.isSunday,
    this.outlined = false,
  });

  Future<void> _pickExcelFile(BuildContext context) async {
    final provider = context.read<AppProvider>();
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xls'],
      );

      if (result != null && result.files.isNotEmpty) {
        final file = result.files.single;

        if (kIsWeb) {
          // Web环境：使用bytes
          if (file.bytes != null) {
            await provider.parseExcelBytes(file.bytes!, isSunday: isSunday);
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(isSunday ? '周日课表导入成功！' : '周一至周六课表导入成功！'),
                ),
              );
            }
          } else {
            throw Exception('Web 环境下无法读取文件');
          }
        } else {
          // Android/iOS环境：使用path
          if (file.path != null) {
            await provider.parseExcelFile(file.path!, isSunday: isSunday);
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(isSunday ? '周日课表导入成功！' : '周一至周六课表导入成功！'),
                ),
              );
            }
          }
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导入失败: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (outlined) {
      return SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: () => _pickExcelFile(context),
          icon: Icon(icon),
          label: Text(label),
        ),
      );
    }
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: () => _pickExcelFile(context),
        icon: Icon(icon),
        label: Text(label),
      ),
    );
  }
}
