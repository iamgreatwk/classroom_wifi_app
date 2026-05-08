// 条件导入：platformViewRegistry
// 仅在 Web 平台可用，其他平台使用 stub 实现

export 'web/platform_view_stub.dart'
    if (dart.library.html) 'web/platform_view_real.dart';
