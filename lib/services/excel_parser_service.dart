import 'dart:io';
import 'dart:typed_data';
import 'package:excel/excel.dart';
import '../models/course.dart';

/// Excel课表解析服务
/// 根据Python代码的逻辑解析课表
class ExcelParserService {
  // 数据文件中星期的起始列（0-based索引）
  static const Map<String, int> weekdayStartCol = {
    '星期日': 5,
    '星期一': 96,
    '星期二': 187,
    '星期三': 278,
    '星期四': 369,
    '星期五': 460,
    '星期六': 551,
  };

  // 星期列表（按顺序）
  static const List<String> weekdays = [
    '星期一',
    '星期二',
    '星期三',
    '星期四',
    '星期五',
    '星期六',
    '星期日',
  ];

  /// 解析Excel文件，返回教室列表
  /// [isSunday] - true表示解析周日课表，false表示解析周一到周六课表
  static Future<List<Classroom>> parseExcelFile(String filePath, {bool isSunday = false}) async {
    final file = File(filePath);
    final bytes = await file.readAsBytes();
    return _parseExcelBytes(bytes, isSunday: isSunday);
  }

  /// 从字节数据解析Excel文件（适用于Web环境）
  /// [isSunday] - true表示解析周日课表，false表示解析周一到周六课表
  static Future<List<Classroom>> parseExcelBytes(Uint8List bytes, {bool isSunday = false}) async {
    return _parseExcelBytes(bytes, isSunday: isSunday);
  }

  /// 内部解析方法
  /// 采用方案3：先预扫描所有主行，再解析（支持变长间隔，如9、18、27行等）
  static Future<List<Classroom>> _parseExcelBytes(dynamic bytes, {bool isSunday = false}) async {
    final excel = Excel.decodeBytes(bytes as Uint8List);
    
    final sheetName = excel.tables.keys.first;
    final worksheet = excel.tables[sheetName];
    
    if (worksheet == null) {
      throw Exception('无法读取Excel文件');
    }

    final classrooms = <Classroom>[];

    // 步骤1：预扫描所有主行索引
    final mainRowIndices = _scanMainRows(worksheet);
    
    // 步骤2：按主行索引解析每个教室
    for (final rowIndex in mainRowIndices) {
      final row = worksheet.row(rowIndex);
      final roomName = _getCellValue(row, 2);
      
      if (roomName.isEmpty || roomName.length < 3) {
        continue;
      }

      // 解析容量（第5列，index=4）
      int? capacity;
      final capacityStr = _getCellValue(row, 4);
      if (capacityStr.isNotEmpty) {
        // 可能格式：纯数字 "120"，或带单位 "120人"、"座120"
        final capacityMatch = RegExp(r'(\d+)').firstMatch(capacityStr);
        if (capacityMatch != null) {
          capacity = int.tryParse(capacityMatch.group(1)!);
        }
      }

      // 解析该教室的课程数据
      final schedule = _parseClassroomSchedule(worksheet, rowIndex, isSunday: isSunday);
      
      if (schedule.isNotEmpty) {
        classrooms.add(Classroom(
          name: roomName,
          schedule: schedule,
          capacity: capacity,
        ));
      }
    }

    return classrooms;
  }

  /// 预扫描工作表，找出所有教室主行的索引
  /// 主行特征：第3列（index=2）有有效的教室名称
  /// 过滤规则：如果两个主行间隔小于9行，只保留第一个（取前9行数据）
  static List<int> _scanMainRows(Sheet worksheet) {
    final mainRowIndices = <int>[];
    
    // 从第3行开始扫描（0-based索引为2，跳过标题行）
    for (int rowIndex = 2; rowIndex < worksheet.maxRows; rowIndex++) {
      final row = worksheet.row(rowIndex);
      
      if (_isMainRow(row)) {
        // 检查与上一个主行的间隔
        if (mainRowIndices.isNotEmpty) {
          final lastIndex = mainRowIndices.last;
          final gap = rowIndex - lastIndex;
          
          // 如果间隔小于9行，说明是同一个教室的多行数据，跳过
          if (gap < 9) {
            continue;
          }
        }
        mainRowIndices.add(rowIndex);
      }
    }
    
    return mainRowIndices;
  }

  /// 判断一行是否是教室主行
  /// 主行特征：第3列（index=2）有非空的教室名称，且包含数字（如"218"、"555"等）
  static bool _isMainRow(List<Data?> row) {
    if (row.length < 3) return false;
    
    final roomName = _getCellValue(row, 2);
    
    // 教室名不能为空
    if (roomName.isEmpty) return false;
    
    // 教室名应该包含数字（如218、555等）
    // 这样可以过滤掉标题行、空行等
    return RegExp(r'\d').hasMatch(roomName);
  }

  /// 获取单元格值
  static String _getCellValue(List<Data?> row, int index) {
    if (index < 0 || index >= row.length) return '';
    final cell = row[index];
    return cell?.value?.toString().trim() ?? '';
  }

  /// 解析单个教室的课表
  /// [isSunday] - true表示解析周日课表，false表示解析周一到周六课表
  static Map<String, Map<int, Course>> _parseClassroomSchedule(
    Sheet worksheet,
    int startRow, {
    bool isSunday = false,
  }) {
    final schedule = <String, Map<int, Course>>{};

    // 根据isSunday决定解析哪些天
    List<String> daysToParse;
    if (isSunday) {
      daysToParse = ['星期日'];
    } else {
      daysToParse = weekdays; // 周一到周六
    }

    // 遍历每一天
    for (final wd in daysToParse) {
      final startCol = weekdayStartCol[wd];
      if (startCol == null) continue;

      final daySchedule = <int, Course>{};

      // 遍历每一节（1-12节）
      for (int period = 1; period <= 12; period++) {
        final col = startCol + (period - 1) * 7;
        
        if (startRow < worksheet.maxRows) {
          final row = worksheet.row(startRow);
          final cellVal = _getCellValue(row, col);
          if (cellVal.isNotEmpty) {
            final parsed = _cleanCourseText(cellVal);
            if (parsed['name']!.isNotEmpty) {
              daySchedule[period] = Course(
                name: parsed['name']!,
                teacher: parsed['teacher'],
                weekday: wd,
                period: period,
              );
            }
          }
        }
      }

      if (daySchedule.isNotEmpty) {
        schedule[wd] = daySchedule;
      }
    }

    return schedule;
  }

  /// 清理课程文本，提取课程名和教师名
  /// 返回 Map 包含 'name' 和 'teacher'
  /// 参考Python代码中的clean_course_text函数
  static Map<String, String?> _cleanCourseText(String text) {
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
    } else if (text.contains('◇')) {
      // 格式1：◇教师名 课程名称 (第N周) 学院
      // 例：◇陈静怡 口译理论与技巧new (第4周) 外国语学院
      // 提取教师名（◇后面的第一个词）
      final teacherMatch = RegExp(r'◇(\S+)').firstMatch(text);
      if (teacherMatch != null) {
        teacher = teacherMatch.group(1);
        // 去掉教师名前面的数字编号（如 "01659" -> ""）
        if (teacher != null) {
          teacher = teacher.replaceAll(RegExp(r'^\d+'), '').trim();
          if (teacher.isEmpty) teacher = null;
        }
      }
      
      // 提取课程名
      final match = RegExp(r'◇\S+\s+(.+?)\s*\(第\d+周\)').firstMatch(text);
      if (match != null) {
        courseName = match.group(1)?.trim() ?? text;
      } else {
        // 兜底
        final match2 = RegExp(r'◇\S+\s+(.+)').firstMatch(text);
        if (match2 != null) {
          courseName = match2.group(1)?.trim() ?? text;
        }
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
        // 例：(本)03有机化学(27人) 04288 周凤涛,宋建国,谭毅\t第3节...
        // 例：(本)01音乐与时代(100人) 08622 LIU YIHENG（刘弋珩） 4...
        final teacherMatch2 = RegExp(r'\(\d+人\)\s*\d+\s+([^()]*?)(?:\s+\d+周|\s+第\d+节|$|\t)').firstMatch(text);
        if (teacherMatch2 != null) {
          teacher = teacherMatch2.group(1)?.trim();
        }
      }
      
      // 去掉教师名前面的数字编号（如 "01659 黄节" -> "黄节"）
      if (teacher != null) {
        teacher = teacher.replaceAll(RegExp(r'^\d+\s*'), '').trim();
      }

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

    // 限制课程名长度
    if (courseName.length > 20) {
      courseName = courseName.substring(0, 20);
    }

    return {'name': courseName, 'teacher': teacher};
  }

  /// 获取星期几的中文名称
  static String getWeekdayName(DateTime date) {
    const weekdayNames = ['星期一', '星期二', '星期三', '星期四', '星期五', '星期六', '星期日'];
    // DateTime.weekday: 1=Monday, 7=Sunday
    final index = date.weekday - 1;
    return weekdayNames[index];
  }

  /// 获取当前是第几节课（基于时间）
  /// 节次时间段：
  /// 第1节:  8:30-9:15
  /// 第2节:  9:25-10:10
  /// 第3节:  10:30-11:15
  /// 第4节:  11:25-12:10
  /// 第5节:  13:05-13:50
  /// 第6节:  14:00-14:45
  /// 第7节:  14:55-15:40
  /// 第8节:  15:50-16:35
  /// 第9节:  16:45-17:30
  /// 第10节: 18:30-19:15
  /// 第11节: 19:25-20:10
  /// 第12节: 20:20-21:05
  static int getCurrentPeriod(DateTime time) {
    final totalMinutes = time.hour * 60 + time.minute;

    // 各节课的开始和结束时间（分钟数）
    const periods = [
      [8 * 60 + 30,  9 * 60 + 15],  // 第1节
      [9 * 60 + 25,  10 * 60 + 10], // 第2节
      [10 * 60 + 30, 11 * 60 + 15], // 第3节
      [11 * 60 + 25, 12 * 60 + 10], // 第4节
      [13 * 60 + 5,  13 * 60 + 50], // 第5节
      [14 * 60 + 0,  14 * 60 + 45], // 第6节
      [14 * 60 + 55, 15 * 60 + 40], // 第7节
      [15 * 60 + 50, 16 * 60 + 35], // 第8节
      [16 * 60 + 45, 17 * 60 + 30], // 第9节
      [18 * 60 + 30, 19 * 60 + 15], // 第10节
      [19 * 60 + 25, 20 * 60 + 10], // 第11节
      [20 * 60 + 20, 21 * 60 + 5],  // 第12节
    ];

    // 正在上课中：返回对应节次
    for (int i = 0; i < periods.length; i++) {
      if (totalMinutes >= periods[i][0] && totalMinutes <= periods[i][1]) {
        return i + 1;
      }
    }

    // 课间或非上课时间：返回最近的下一节课，或已过的最后一节
    // 上午第一节课之前 → 第1节
    if (totalMinutes < periods[0][0]) return 1;
    // 晚上最后一节课之后 → 第12节
    if (totalMinutes > periods[11][1]) return 12;

    // 在两节课之间：返回下一节课
    for (int i = 0; i < periods.length - 1; i++) {
      if (totalMinutes > periods[i][1] && totalMinutes < periods[i + 1][0]) {
        return i + 2;
      }
    }

    return 12;
  }
}
