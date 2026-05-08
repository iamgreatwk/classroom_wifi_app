// 非 Web 平台：提供 dart:html 的 stub 实现

// ignore: camel_case_types
class _BlobImpl {
  _BlobImpl(List<dynamic> data, [String? type]) {}
}

typedef Blob = _BlobImpl;

// ignore: camel_case_types
class _UrlImpl {
  static String createObjectUrlFromBlob(Blob blob) => '';
  static void revokeObjectUrl(String url) {}
}

typedef Url = _UrlImpl;

// ignore: camel_case_types
class _AnchorElementImpl {
  String? href;
  String? download;
  final AnchorElementStyle style = AnchorElementStyle();
  
  _AnchorElementImpl({this.href});
  
  void click() {}
  void remove() {}
  void setAttribute(String name, String value) {
    if (name == 'download') download = value;
  }
}

// AnchorElement 的 style 属性
class AnchorElementStyle {
  String display = '';
}

// 对外暴露的类型别名
typedef AnchorElement = _AnchorElementImpl;

// ignore: camel_case_types
class _ImageElementImpl {
  String src = '';
  final ImageElementStyle style = ImageElementStyle();
  bool draggable = false;
}

typedef ImageElement = _ImageElementImpl;

// ImageElement 的 style 属性
class ImageElementStyle {
  String width = '';
  String height = '';
  String objectFit = '';
  String display = '';
}

// 模拟可调用类，返回 ImageElement
class _ImageElementFactory {
  _ImageElementImpl call() => _ImageElementImpl();
}

// 模拟可调用类，返回 Blob
class _BlobFactory {
  _BlobImpl call(List<dynamic> data, [String? type]) => _BlobImpl(data, type);
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
  final _UrlClass Url = _UrlClass();

  // document 对象
  final _Document document = _Document();
}

// 模拟 dart:html 的 Url 类（作为实例成员）
class _UrlClass {
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
