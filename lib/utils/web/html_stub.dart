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

class HtmlDocument {
  AnchorElement createElement(String tag) => AnchorElement();
  dynamic get body => _Body();
}

class _Body {
  void append(dynamic element) {}
  void removeChild(dynamic element) {}
}

final html = HtmlDocument();
