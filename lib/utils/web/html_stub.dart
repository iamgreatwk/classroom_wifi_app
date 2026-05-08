// 非 Web 平台：提供 dart:html 的 stub 实现

class Blob {
  Blob(List<dynamic> data, [String? type]) {}
}

class Url {
  static String createObjectUrlFromBlob(Blob blob) => '';
  static void revokeObjectUrl(String url) {}
}

// ignore: camel_case_types
class _AnchorElementImpl {
  String? href;
  String? download;
  String style = '';
  
  _AnchorElementImpl({this.href});
  
  void click() {}
  void remove() {}
  void setAttribute(String name, String value) {
    if (name == 'download') download = value;
  }
}

// 对外暴露的类型别名
typedef AnchorElement = _AnchorElementImpl;

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

// 模拟可调用类，返回 AnchorElement（支持命名参数）
class _AnchorElementFactory {
  _AnchorElementImpl call({String? href}) => _AnchorElementImpl(href: href);
}

class HtmlDocument {
  _AnchorElementImpl createElement(String tag) => _AnchorElementImpl();
  dynamic get body => _Body();

  // 工厂函数
  final _ImageElementFactory ImageElement = _ImageElementFactory();
  final _BlobFactory Blob = _BlobFactory();
  final _AnchorElementFactory AnchorElement = _AnchorElementFactory();

  // 静态类成员
  final UrlClass Url = UrlClass();

  // document 对象
  final _Document document = _Document();
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
