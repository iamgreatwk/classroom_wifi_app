// 非 Web 平台：提供 dart:html 的 stub 实现

class Blob {
  Blob(List<dynamic> data, [String? type]) {}
}

class Url {
  static String createObjectUrlFromBlob(Blob blob) => '';
  static void revokeObjectUrl(String url) {}
}

class AnchorElement {
  String? href;
  String? download;
  String style = '';
  void click() {}
  void remove() {}
}

// ImageElement 类
class ImageElement {
  String src = '';
  final ImageElementStyle style = ImageElementStyle();
  bool draggable = false;
}

// ImageElement 的 style 属性
class ImageElementStyle {
  String width = '';
  String height = '';
  String objectFit = '';
  String display = '';
}

// 模拟可调用类，返回 ImageElement
class _ImageElementFactory {
  ImageElement call() => ImageElement();
}

// 模拟可调用类，返回 Blob
class _BlobFactory {
  Blob call(List<dynamic> data, [String? type]) => Blob(data, type);
}

class HtmlDocument {
  AnchorElement createElement(String tag) => AnchorElement();
  dynamic get body => _Body();

  // 工厂函数
  final _ImageElementFactory ImageElement = _ImageElementFactory();
  final _BlobFactory Blob = _BlobFactory();

  // 静态类成员
  final UrlClass Url = UrlClass();
}

// 模拟 dart:html 的 Url 类（作为实例成员）
class UrlClass {
  String createObjectUrlFromBlob(Blob blob) => '';
  void revokeObjectUrl(String url) {}
}

class _Body {
  final List<dynamic> children = [];
  void append(dynamic element) {}
  void removeChild(dynamic element) {}
}

// 模拟 dart:html 的 document 全局对象
class _Document {
  _Body get body => _Body();
}

final html = HtmlDocument();
final document = _Document();
