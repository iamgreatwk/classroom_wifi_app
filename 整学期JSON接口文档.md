# 整学期教室总表 JSON 接口文档

> 由 `parse_schedule.py` 从 FineReport 导出的 HTML 解析生成。
> 源文件：`整学期.html`（GBK 编码） → 输出：`整学期.json`（UTF-8）

---

## 1. 顶层结构

```json
{
  "title": "2025-2026学年 第2学期教室总表",
  "classrooms": [ ... ]
}
```

| 字段 | 类型 | 说明 |
|------|------|------|
| `title` | string | 学期标题，可直接用作展示 |
| `classrooms` | array | 教室列表，按楼层层号排序 |

---

## 2. 教室对象

```json
{
  "room_code": "N204",
  "room_name": "番禺教学大楼204室",
  "campus": "番禺校区",
  "room_type": "多",
  "capacity": "85",
  "course_count": 46,
  "schedule": [ ... ]
}
```

| 字段 | 类型 | 说明 |
|------|------|------|
| `room_code` | string | 教室编号，如 `N204`，全局唯一 |
| `room_name` | string | 教室全名 |
| `campus` | string | 校区 |
| `room_type` | string | 教室类型缩写（"多"=多媒体） |
| `capacity` | string | 容量（字符串，非数字） |
| `course_count` | int | 该教室课程记录总数 |
| `schedule` | array | 课程记录列表 |

---

## 3. 课程记录

所有课程记录共享以下 **必选字段**（100% 覆盖）：

| 字段 | 类型 | 说明 |
|------|------|------|
| `raw` | string | HTML `<td>` 的 `title` 属性原文，保留完整信息 |
| `type` | string | 课程类型，固定三种：`"本科"` / `"研究生"` / `"借用"` |
| `day` | string | 星期几，取值：`"星期日"` ~ `"星期六"` |
| `day_index` | int | 星期索引，0=星期日, 1=星期一, ..., 6=星期六 |
| `start_period` | int | 起始节次（1-13） |
| `end_period` | int | 结束节次（1-13），≥ `start_period` |
| `period` | int | 向后兼容字段，等于 `start_period` |
| `weeks` | string | 周次原始字符串，如 `"1-17周"`、`"2-16周(双)"`、`"8周,10-12周"` |
| `weeks_list` | int[] | 周次展开列表，如 `[1,2,3,...,17]`、`[2,4,6,...,16]`、`[8,10,11,12]` |

### 3.1 类型判断规则

| raw 前缀 | type | 说明 |
|----------|------|------|
| `(研)` | 研究生 | 如 `(研)01全球问题研究(13人) 06333 ...` |
| `◇` | 研究生 | 如 `◇关国瑞 讲座 (第3周)` |
| `借用` | 借用 | 如 `借用陶露丝 开会 (第6周)` |
| 其余 | 本科 | 包括 `(本)` 开头、`第X周考试占用`、无前缀等 |

### 3.2 各类型特有字段

不同类型会额外携带不同字段，使用前请 **检查字段是否存在**（`key in dict`）。

#### 本科（600 条）

| 字段 | 类型 | 覆盖率 | 说明 |
|------|------|--------|------|
| `name` | string | 100% | 课程名称 |
| `teacher` | string | 81% | 授课教师，多人用英文逗号分隔 |
| `classes` | string | 84% | 上课班级 |
| `seq` | string | 81% | 课程序号，如 `"01"` |
| `student_count` | int | 81% | 选课人数 |
| `course_code` | string | 81% | 课程代码，如 `"05786"` |
| `weeks` | string | 99% | 4 条系统占位记录无此字段 |
| `weeks_list` | int[] | 99% | 同上 |

#### 研究生（232 条）

研究生有两种子格式，字段组合不同：

**子格式 A**：`(研)` 开头，有标准排课信息（167 条）

| 字段 | 类型 | 说明 |
|------|------|------|
| `name` | string | 课程名称 |
| `teacher` | string | 授课教师 |
| `classes` | string | 上课班级 |
| `seq` / `student_count` / `course_code` | — | 部分记录有（有人数格式），部分无 |

**子格式 B**：`◇` 开头（65 条）

| 字段 | 类型 | 说明 |
|------|------|------|
| `teacher` | string | 负责人 |
| `activity` | string | 活动名称，如"讲座"、"复试" |
| `department` | string | 院系（仅 27% 有） |
| `name` | string | 无法解析时的兜底字段 |

#### 借用（344 条）

| 字段 | 类型 | 覆盖率 | 说明 |
|------|------|--------|------|
| `teacher` | string | 100% | 借用人 |
| `activity` | string | 100% | 借用事由，可能为空字符串 `""` |

---

## 4. 字段取值范围

| 字段 | 范围 |
|------|------|
| `day_index` | 0 ~ 6 |
| `start_period` / `end_period` | 1 ~ 13 |
| `weeks_list` 元素 | 1 ~ 19（学期周次） |
| `type` | `"本科"` / `"研究生"` / `"借用"` |
| `capacity` | 字符串，如 `"85"` |

---

## 5. 使用示例

### Python

```python
import json

with open('整学期.json', 'r', encoding='utf-8') as f:
    data = json.load(f)

# 遍历所有教室
for cr in data['classrooms']:
    room = cr['room_code']  # "N204"

    # 遍历该教室课程
    for c in cr['schedule']:
        # 公共字段——所有类型都有
        day = c['day']              # "星期一"
        start = c['start_period']  # 1
        end = c['end_period']      # 4
        weeks = c['weeks_list']    # [1,2,...,17]

        # 按类型取特有字段
        if c['type'] == '本科':
            name = c.get('name', '')
            teacher = c.get('teacher', '')
        elif c['type'] == '研究生':
            name = c.get('name', '') or c.get('activity', '')
            teacher = c.get('teacher', '')
        elif c['type'] == '借用':
            teacher = c.get('teacher', '')
            activity = c.get('activity', '')

# 按教室查课表
room_map = {cr['room_code']: cr for cr in data['classrooms']}
n204 = room_map['N204']
```

### TypeScript

```typescript
interface CourseRecord {
  raw: string;
  type: '本科' | '研究生' | '借用';
  day: string;
  day_index: number;
  start_period: number;
  end_period: number;
  period: number;
  weeks: string;
  weeks_list: number[];
  // 本科 & 研究生(研)
  name?: string;
  teacher?: string;
  classes?: string;
  seq?: string;
  student_count?: number;
  course_code?: string;
  // 研究生(◇) & 借用
  activity?: string;
  department?: string;  // 仅研究生(◇)
}

interface Classroom {
  room_code: string;
  room_name: string;
  campus: string;
  room_type: string;
  capacity: string;
  course_count: number;
  schedule: CourseRecord[];
}

interface SemesterData {
  title: string;
  classrooms: Classroom[];
}
```

---

## 6. 注意事项

1. **`raw` 是最完整的字段**。所有解析字段都从 `raw` 提取，如有疑问以 `raw` 为准。
2. **特有字段不一定存在**。使用 `.get(key, default)` 或 `key in dict` 检查，不要假设字段一定有值。
3. **`period` 是向后兼容字段**，新代码请用 `start_period` / `end_period`。
4. **同一课程可能有多条记录**。同一门课在同一天的不同节次段（如第1-2节和第7-9节）会被拆成多条记录。
5. **`weeks_list` 已展开**。无需再次解析 `weeks` 字符串，直接用 `weeks_list` 判断某周是否有课。
6. **4 条本科记录无 `weeks`/`weeks_list`**。这是系统占位数据（如"教室资源时间屏蔽"），通过 `'weeks' in record` 判断即可。
7. **`capacity` 是字符串**。需要数字时请 `int(record['capacity'])`。
