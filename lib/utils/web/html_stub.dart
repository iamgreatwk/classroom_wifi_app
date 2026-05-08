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

// ImageElement 类 - 可通过 ImageElementCtor() 构造
class ImageElement {
  String src = '';
  String style = '';
  bool draggable = false;
}

// 模拟构造函数 - 可被调用返回 ImageElement
class ImageElementCtor {
  ImageElement call() => ImageElement();
}

class HtmlDocument {
  AnchorElement createElement(String tag) => AnchorElement();
  dynamic get body => _Body();

  // ImageElement 作为可调用对象
  final ImageElementCtor ImageElement = ImageElementCtor();
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
