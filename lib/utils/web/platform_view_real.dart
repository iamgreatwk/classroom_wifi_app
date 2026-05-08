// Web 平台：导出真实的 platformViewRegistry
// ignore: avoid_web_libraries_in_flutter
import 'dart:ui_web' as ui_web;

/// 注册平台视图工厂 - Web 平台真实实现
void registerViewFactory(String viewType, dynamic Function(int viewId) factory) {
  // ignore: undefined_prefixed_name
  ui_web.platformViewRegistry.registerViewFactory(viewType, factory);
}
