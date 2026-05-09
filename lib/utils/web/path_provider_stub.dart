// Web平台的path_provider stub实现

class Directory {
  final String path;
  Directory(this.path);
}

Future<Directory> getTemporaryDirectory() async {
  throw UnsupportedError('getTemporaryDirectory is not supported on Web');
}

Future<Directory?> getExternalStorageDirectory() async {
  throw UnsupportedError('getExternalStorageDirectory is not supported on Web');
}

Future<Directory> getApplicationDocumentsDirectory() async {
  throw UnsupportedError('getApplicationDocumentsDirectory is not supported on Web');
}
