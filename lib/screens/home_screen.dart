import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import '../providers/app_provider.dart';
import '../services/excel_parser_service.dart';
import '../config.dart';
import 'course_display_screen.dart';

/// 主屏幕
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    // 初始化
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AppProvider>().init();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('当前课程'),
        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
      ),
      body: Consumer<AppProvider>(
        builder: (context, provider, _) {
          if (provider.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          if (provider.error != null) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.error_outline, size: 64, color: Colors.red[300]),
                  const SizedBox(height: 16),
                  Text(provider.error!),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () => provider.init(),
                    child: const Text('重试'),
                  ),
                ],
              ),
            );
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 当前课程卡片 - 放在最上面
                _buildCurrentCourseCard(provider),
                const SizedBox(height: 16),

                // 当前状态卡片
                _buildStatusCard(provider),
                const SizedBox(height: 16),

                // 教室列表（已导入教室）
                if (provider.classrooms.isNotEmpty)
                  _buildClassroomsCard(provider),
                
                if (provider.classrooms.isNotEmpty)
                  const SizedBox(height: 16),

                // 导入课表卡片 - 放在最下面
                _buildImportCard(provider),
              ],
            ),
          );
        },
      ),
    );
  }

  /// 导入课表卡片
  Widget _buildImportCard(AppProvider provider) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.table_chart, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                const Text(
                  '导入课表',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              provider.classrooms.isEmpty
                  ? '尚未导入课表，请点击下方按钮导入Excel课表文件'
                  : '已导入 ${provider.classrooms.length} 个教室的课表',
              style: TextStyle(color: Colors.grey[600]),
            ),
            const SizedBox(height: 12),
            // 周一至周六课表导入
            ElevatedButton.icon(
              onPressed: () => _pickExcelFile(isSunday: false),
              icon: const Icon(Icons.calendar_today),
              label: const Text('导入周一至周六'),
            ),
            const SizedBox(height: 8),
            // 周日课表导入
            OutlinedButton.icon(
              onPressed: () => _pickExcelFile(isSunday: true),
              icon: const Icon(Icons.calendar_view_day),
              label: const Text('导入周日'),
            ),
          ],
        ),
      ),
    );
  }

  /// 状态卡片
  Widget _buildStatusCard(AppProvider provider) {
    final now = DateTime.now();
    final weekday = ExcelParserService.getWeekdayName(now);
    final period = ExcelParserService.getCurrentPeriod(now);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.info_outline, color: Theme.of(context).colorScheme.secondary),
                const SizedBox(width: 8),
                const Text(
                  '当前状态',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _buildInfoRow('时间', '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}'),
            _buildInfoRow('星期', weekday),
            _buildInfoRow('第', '$period 节'),
            const Divider(),
            // Web版显示教室选择器，Android版显示附近教室
            if (AppConfig.isWebMode)
              _buildClassroomSelector(provider)
            else
              _buildInfoRow(
                '附近教室',
                provider.nearestClassroom?.name ?? '未检测到',
              ),
          ],
        ),
      ),
    );
  }

  /// 教室选择器（Web版使用）
  Widget _buildClassroomSelector(AppProvider provider) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '选择教室',
          style: TextStyle(fontSize: 14, color: Colors.grey),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          value: provider.selectedClassroom?.name,
          decoration: InputDecoration(
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            hintText: '请选择教室',
          ),
          items: provider.classrooms.map((classroom) {
            return DropdownMenuItem<String>(
              value: classroom.name,
              child: Text(classroom.name),
            );
          }).toList(),
          onChanged: (value) {
            if (value == null) {
              provider.selectClassroom(null);
            } else {
              final classroom = provider.classrooms.where((c) => c.name == value).firstOrNull;
              provider.selectClassroom(classroom);
            }
          },
        ),
      ],
    );
  }

  /// 当前课程卡片
  Widget _buildCurrentCourseCard(AppProvider provider) {
    final course = provider.currentCourse;
    final classroom = provider.nearestClassroom;
    final hasClassroom = classroom != null;

    return Card(
      color: course != null 
          ? Theme.of(context).colorScheme.primaryContainer 
          : (hasClassroom ? Theme.of(context).colorScheme.secondaryContainer : null),
      child: InkWell(
        onTap: hasClassroom
            ? () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => CourseDisplayScreen(classroom: classroom),
                  ),
                );
              }
            : null,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.school,
                    color: course != null 
                        ? Theme.of(context).colorScheme.onPrimaryContainer
                        : (hasClassroom 
                            ? Theme.of(context).colorScheme.onSecondaryContainer
                            : Colors.grey),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '当前课程',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: course != null 
                          ? Theme.of(context).colorScheme.onPrimaryContainer
                          : (hasClassroom 
                              ? Theme.of(context).colorScheme.onSecondaryContainer
                              : null),
                    ),
                  ),
                  if (hasClassroom) ...[
                    const Spacer(),
                    Icon(
                      Icons.chevron_right,
                      color: course != null 
                          ? Theme.of(context).colorScheme.onPrimaryContainer
                          : Theme.of(context).colorScheme.onSecondaryContainer,
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 12),
              if (course != null && classroom != null) ...[
                Text(
                  course.displayName,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${classroom.name} - 第${course.period}节',
                  style: TextStyle(
                    fontSize: 16,
                    color: Theme.of(context).colorScheme.onPrimaryContainer.withOpacity(0.8),
                  ),
                ),
              ] else if (hasClassroom) ...[
                // 有教室但当前无课程
                Text(
                  classroom.name,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onSecondaryContainer,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '当前时段无课程',
                  style: TextStyle(
                    fontSize: 16,
                    color: Theme.of(context).colorScheme.onSecondaryContainer.withOpacity(0.8),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '点击查看其他时段课程',
                  style: TextStyle(
                    fontSize: 14,
                    color: Theme.of(context).colorScheme.onSecondaryContainer.withOpacity(0.6),
                  ),
                ),
              ] else ...[
                Text(
                  AppConfig.isWebMode ? '请在上方选择教室' : '正在扫描附近教室...',
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// 教室列表卡片
  Widget _buildClassroomsCard(AppProvider provider) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.list_alt, color: Theme.of(context).colorScheme.tertiary),
                const SizedBox(width: 8),
                const Text(
                  '查看教室课表',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 200,
              child: ListView.builder(
                itemCount: provider.classrooms.length,
                itemBuilder: (context, index) {
                  final classroom = provider.classrooms[index];
                  final isNearest = provider.nearestClassroom?.name == classroom.name;
                  
                  return ListTile(
                    leading: Icon(
                      Icons.class_,
                      color: isNearest ? Theme.of(context).colorScheme.primary : null,
                    ),
                    title: Text(
                      classroom.name,
                      style: TextStyle(
                        fontWeight: isNearest ? FontWeight.bold : null,
                      ),
                    ),
                    trailing: isNearest ? const Icon(Icons.location_on, color: Colors.green) : null,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => CourseDisplayScreen(classroom: classroom),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: Colors.grey[600])),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  /// 选择Excel文件
  /// [isSunday] - true表示导入周日课表，false表示导入周一到周六课表
  Future<void> _pickExcelFile({required bool isSunday}) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xls'],
      );

      if (result != null && result.files.isNotEmpty) {
        final file = result.files.single;

        if (kIsWeb) {
          // Web环境：使用bytes（无path属性）
          if (file.bytes != null) {
            if (mounted) {
              await context.read<AppProvider>().parseExcelBytes(file.bytes!, isSunday: isSunday);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(isSunday ? '周日课表导入成功！' : '周一至周六课表导入成功！'),
                  ),
                );
              }
            }
          } else {
            throw Exception('Web环境下无法读取文件');
          }
        } else {
          // Android/iOS环境：使用path
          if (file.path != null) {
            if (mounted) {
              await context.read<AppProvider>().parseExcelFile(file.path!, isSunday: isSunday);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(isSunday ? '周日课表导入成功！' : '周一至周六课表导入成功！'),
                  ),
                );
              }
            }
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导入失败: $e')),
        );
      }
    }
  }
}
