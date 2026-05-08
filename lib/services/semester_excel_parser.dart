import 'dart:typed_data';
import 'package:excel/excel.dart';
import '../models/course_with_week.dart';

/// 解析进度回调
/// [current] - 当前处理进度
/// [total] - 总任务数
/// [message] - 当前处理描述
typedef ParseProgressCallback = void Function(int current, int total, String message);

/// 学期课表Excel解析服务
class SemesterExcelParser {
  /// 星期到列的映射（第1节的列号）
  static const Map<String, int> _dayColumnMap = {
    '星期日': 5,
    '星期一': 96,
    '星期二': 187,
    '星期三': 278,
    '星期四': 369,
    '星期五': 460,
    '星期六': 551,
  };

  /// 节次之间的列间隔
  static const int _periodColumnInterval = 7;

  /// 解析学期课表Excel（同步版本）
  static List<SemesterClassroom> parseSemesterExcel(Uint8List bytes) {
    final excel = Excel.decodeBytes(bytes);
    final sheet = excel.tables.values.first;

    final classrooms = <SemesterClassroom>[];

    // 查找所有教室行
    final classroomRows = _findClassroomRows(sheet);

    for (int i = 0; i < classroomRows.length; i++) {
      final row = classroomRows[i];
      final startRow = row['row'] as int;
      final endRow = (i + 1 < classroomRows.length)
          ? classroomRows[i + 1]['row'] as int
          : sheet.maxRows;

      final classroom = _parseClassroom(
        sheet,
        startRow,
        endRow,
        row['name'] as String,
      );

      if (classroom != null) {
        classrooms.add(classroom);
      }
    }

    return classrooms;
  }

  /// 异步分批解析学期课表Excel（避免阻塞UI）
  /// [bytes] - Excel文件字节
  /// [onProgress] - 进度回调
  /// [batchSize] - 每批处理的教室数量
  /// [yieldInterval] - 每处理多少个教室让出时间片
  static Future<List<SemesterClassroom>> parseSemesterExcelAsync(
    Uint8List bytes, {
    ParseProgressCallback? onProgress,
    int batchSize = 3,
    int yieldInterval = 2,
  }) async {
    onProgress?.call(0, 100, '正在读取Excel文件...');

    // 第一阶段：解码Excel（这步可能较慢，但无法分批）
    final excel = Excel.decodeBytes(bytes);
    final sheet = excel.tables.values.first;

    onProgress?.call(10, 100, '正在查找教室...');

    // 查找所有教室行
    final classroomRows = _findClassroomRows(sheet);
    final totalClassrooms = classroomRows.length;

    if (totalClassrooms == 0) {
      return [];
    }

    final classrooms = <SemesterClassroom>[];

    // 第二阶段：分批解析教室
    for (int i = 0; i < totalClassrooms; i++) {
      final row = classroomRows[i];
      final startRow = row['row'] as int;
      final endRow = (i + 1 < totalClassrooms)
          ? classroomRows[i + 1]['row'] as int
          : sheet.maxRows;

      // 更新进度
      final progress = 10 + ((i / totalClassrooms) * 85).round();
      onProgress?.call(
        progress,
        100,
        '正在解析教室 ${i + 1}/$totalClassrooms: ${row['name']}',
      );

      final classroom = _parseClassroom(
        sheet,
        startRow,
        endRow,
        row['name'] as String,
      );

      if (classroom != null) {
        classrooms.add(classroom);
      }

      // 每处理 yieldInterval 个教室，让出时间片，避免阻塞UI
      if ((i + 1) % yieldInterval == 0) {
        await Future.delayed(Duration.zero);
      }
    }

    onProgress?.call(100, 100, '解析完成，共 ${classrooms.length} 个教室');
    return classrooms;
  }

  /// 查找所有教室行
  static List<Map<String, dynamic>> _findClassroomRows(Sheet sheet) {
    final result = <Map<String, dynamic>>[];

    for (int row = 0; row < sheet.maxRows; row++) {
      final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: row));
      if (cell.value != null) {
        final value = cell.value.toString();
        if (value.contains('番禺教学大楼')) {
          result.add({'row': row, 'name': value});
        }
      }
    }

    return result;
  }

  /// 解析单个教室的数据
  static SemesterClassroom? _parseClassroom(
    Sheet sheet,
    int startRow,
    int endRow,
    String classroomName,
  ) {
    final schedule = <String, Map<int, List<CourseWithWeek>>>{};

    // 初始化星期和节次
    for (final day in _dayColumnMap.keys) {
      schedule[day] = {};
      for (int period = 1; period <= 13; period++) {
        schedule[day]![period] = [];
      }
    }

    // 遍历所有星期和节次
    for (final entry in _dayColumnMap.entries) {
      final day = entry.key;
      final baseColumn = entry.value;

      for (int period = 1; period <= 13; period++) {
        final column = baseColumn + (period - 1) * _periodColumnInterval;

        // 在当前教室的所有行中查找课程
        for (int row = startRow; row < endRow; row++) {
          final cell = sheet.cell(
            CellIndex.indexByColumnRow(columnIndex: column, rowIndex: row),
          );

          if (cell.value != null) {
            final text = cell.value.toString().trim();
            if (text.isNotEmpty && text.contains('周')) {
              final course = _parseCourse(text, day, period, classroomName);
              if (course != null) {
                schedule[day]![period]!.add(course);
              }
            }
          }
        }
      }
    }

    // 从第5列（索引4）读取容量
    final capacity = _readCapacityFromSheet(sheet, startRow);

    return SemesterClassroom(
      name: classroomName,
      schedule: schedule,
      capacity: capacity,
    );
  }

  /// 从教室行的第5列读取容量
  static int? _readCapacityFromSheet(Sheet sheet, int row) {
    final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: row));
    if (cell.value != null) {
      final value = cell.value.toString().trim();
      // 提取数字，如"120人"或"120" → 120
      final match = RegExp(r'(\d+)').firstMatch(value);
      if (match != null) {
        return int.tryParse(match.group(1)!);
      }
    }
    return null;
  }

  /// 解析课程信息
  static CourseWithWeek? _parseCourse(
    String text,
    String weekday,
    int period,
    String classroom,
  ) {
    // 解析周次
    final weekInfo = _parseWeeks(text);
    if (weekInfo == null) return null;

    // 解析课程名和教师
    final courseInfo = _parseCourseInfo(text);

    return CourseWithWeek(
      name: courseInfo['name'] ?? '未知课程',
      teacher: courseInfo['teacher'],
      weekday: weekday,
      period: period,
      startWeek: weekInfo['startWeek']!,
      endWeek: weekInfo['endWeek']!,
      rawText: text,
      classroom: classroom,
    );
  }

  /// 解析周次信息
  static Map<String, int>? _parseWeeks(String text) {
    // 匹配 "1-17周" 或 "第3周"
    final rangeRegExp = RegExp(r'(\d+)-(\d+)周');
    final singleRegExp = RegExp(r'第(\d+)周');

    final rangeMatch = rangeRegExp.firstMatch(text);
    if (rangeMatch != null) {
      return {
        'startWeek': int.parse(rangeMatch.group(1)!),
        'endWeek': int.parse(rangeMatch.group(2)!),
      };
    }

    final singleMatch = singleRegExp.firstMatch(text);
    if (singleMatch != null) {
      final week = int.parse(singleMatch.group(1)!);
      return {
        'startWeek': week,
        'endWeek': week,
      };
    }

    return null;
  }

  /// 解析课程信息（名称和教师）
  /// 参考ExcelParserService._cleanCourseText的实现，保持一致性
  static Map<String, String?> _parseCourseInfo(String text) {
    if (text.isEmpty) return {'name': '', 'teacher': null};

    String? teacher;
    String courseName = text;

    // 格式0：借用教师名 课程名称（第x周）
    // 例：借用高某某 微积分（第8周）
    if (text.startsWith('借用')) {
      // 提取教师名（"借用"后面的第一个词）
      final teacherMatch = RegExp(r'借用(\S+)').firstMatch(text);
      if (teacherMatch != null) {
        teacher = teacherMatch.group(1);
      }

      // 提取课程名（教师名后面的内容，到（第x周）为止）
      final match = RegExp(r'借用\S+\s+(.+?)(?:（第\d+周）|\s|$)').firstMatch(text);
      if (match != null) {
        courseName = match.group(1)?.trim() ?? text;
      }
    } else if (text.startsWith('(研)') || text.contains('◇')) {
      // 格式1：研究生课程
      // 可能格式：
      // ◇教师名 课程名称 (第N周) 学院
      // (研)◇教师名 课程名称 (第N周) 学院
      // ◇数字教师名 课程名称 ...
      // (研)课程名称 周次 (没有教师名，没有◇)

      // 去掉开头的(研)标记
      String processedText = text;
      if (processedText.startsWith('(研)')) {
        processedText = processedText.substring(3).trim();
      }

      if (processedText.contains('◇')) {
        // 有◇的情况：◇教师名 课程名 周次
        // 提取教师名（◇后面的第一个词，可能带有数字前缀）
        final teacherMatch = RegExp(r'◇(\S+)').firstMatch(processedText);
        if (teacherMatch != null) {
          teacher = teacherMatch.group(1);
          // 去掉教师名前面的数字编号（如 "01659陈静怡" -> "陈静怡"）
          if (teacher != null) {
            teacher = teacher.replaceAll(RegExp(r'^\d+'), '').trim();
            if (teacher.isEmpty) teacher = null;
          }
        }

        // 提取课程名：◇后面的内容到 (第N周) 或 空格+数字周 为止
        final match = RegExp(r'◇\S+\s+(.+?)(?:\s*\(第\d+周\)|\s+第\d+周|\s+\d+周)').firstMatch(processedText);
        if (match != null) {
          courseName = match.group(1)?.trim() ?? text;
        } else {
          // 兜底：取◇之后到第一个"第X周"或"(第X周)"之前的内容
          final fallbackMatch = RegExp(r'◇\S+\s+(.+?)(?:\s+第|\s*\(第|$)').firstMatch(processedText);
          if (fallbackMatch != null) {
            courseName = fallbackMatch.group(1)?.trim() ?? text;
          }
        }
      } else {
        // 没有◇的情况：(研)课程名 周次，没有教师名
        // 提取课程名：从开头到周次之前
        final match = RegExp(r'^(.+?)(?:\s+第?\d+-?\d*周|\s*\(第?\d+-?\d*周\))').firstMatch(processedText);
        if (match != null) {
          courseName = match.group(1)?.trim() ?? text;
        } else {
          courseName = processedText;
        }
        teacher = null;
      }
    } else {
      // 格式2：(本)01课程名(N人) 工号 教师名 X周 第N节-第M节 ...
      // 提取教师名（在课程名后面的某个位置）
      // 先尝试匹配：)内容 数字周
      final teacherMatch = RegExp(r'\)\s*(\d+\s+)?([^()]+?)\s+\d+周').firstMatch(text);
      if (teacherMatch != null) {
        teacher = teacherMatch.group(2)?.trim();
      } else {
        // 备选：匹配 )工号 教师名（后面没有直接的X周，可能是制表符分隔）
        final teacherMatch2 = RegExp(r'\(\d+人\)\s*\d+\s+([^()]*?)(?:\s+\d+周|\s+第\d+节|$|\t)').firstMatch(text);
        if (teacherMatch2 != null) {
          teacher = teacherMatch2.group(1)?.trim();
        }
      }

      // 去掉教师名前面的数字编号（如 "01659 黄节" -> "黄节"）
      if (teacher != null) {
        teacher = teacher.replaceAll(RegExp(r'^\d+\s*'), '').trim();
      }

      // 提取课程名
      final match = RegExp(r'\)(\d+)(.+?)\(\d+人\)').firstMatch(text);
      if (match != null) {
        courseName = match.group(2)?.trim() ?? text;
      } else {
        final match2 = RegExp(r'\((?:本|研|专)\)(.+?)\s+\d+周').firstMatch(text);
        if (match2 != null) {
          courseName = match2.group(1)?.trim() ?? text;
        }
      }
    }

    // 清理课程名中可能包含的周次信息
    courseName = courseName.replaceAll(RegExp(r'\s*第?\d+-?\d*周\s*'), '');
    courseName = courseName.replaceAll(RegExp(r'\s*\(第?\d+-?\d*周\)\s*'), '');

    // 限制课程名长度
    if (courseName.length > 20) {
      courseName = courseName.substring(0, 20);
    }

    return {'name': courseName, 'teacher': teacher};
  }
}
