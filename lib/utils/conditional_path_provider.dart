// 条件导入：path_provider
// 在非Web平台导出 path_provider，在Web平台导出 stub

export 'package:path_provider/path_provider.dart'
    if (dart.library.html) 'web/path_provider_stub.dart';
