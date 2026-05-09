// 条件导入：share_plus
// 在非Web平台导出 share_plus，在Web平台导出 stub

export 'package:share_plus/share_plus.dart'
    if (dart.library.html) 'web/share_stub.dart';
