/// 文件系统小工具：路径、体积、递归查找、安全删除。
library;

import 'dart:io';

String join(String a, String b) {
  if (b.isEmpty) return a;
  final String sep = Platform.pathSeparator;
  final String left = a.endsWith(sep) ? a.substring(0, a.length - 1) : a;
  return '$left$sep${b.replaceAll('/', sep)}';
}

String dirname(String path) {
  final String sep = Platform.pathSeparator;
  final int i = path.lastIndexOf(sep);
  if (i <= 0) return path;
  return path.substring(0, i);
}

String normalize(String path) => path.replaceAll('\\', '/');

String relative(String from, String to) {
  final String f = normalize(from);
  final String t = normalize(to);
  if (t == f) return '.';
  return t.startsWith('$f/') ? t.substring(f.length + 1) : t;
}

bool inside(String parent, String child) {
  final String p = normalize(parent);
  final String c = normalize(child);
  return c == p || c.startsWith(p.endsWith('/') ? p : '$p/');
}

int sizeOf(String path) {
  final FileSystemEntityType type = FileSystemEntity.typeSync(path);
  if (type == FileSystemEntityType.file) {
    try {
      return File(path).lengthSync();
    } on FileSystemException {
      return 0;
    }
  }
  if (type != FileSystemEntityType.directory) return 0;
  int total = 0;
  try {
    for (final FileSystemEntity e in Directory(
      path,
    ).listSync(recursive: true, followLinks: false)) {
      if (e is File) {
        try {
          total += e.lengthSync();
        } on FileSystemException {
          // 只为显示体积，权限问题忽略
        }
      }
    }
  } on FileSystemException {
    // 同上
  }
  return total;
}

void deleteEntity(String path) {
  final FileSystemEntityType type = FileSystemEntity.typeSync(path);
  if (type == FileSystemEntityType.directory) {
    Directory(path).deleteSync(recursive: true);
  } else if (type == FileSystemEntityType.file ||
      type == FileSystemEntityType.link) {
    File(path).deleteSync();
  }
}

/// 递归找文件（跳过 .dart_tool / build / .git）。
List<String> findFiles(String dir, bool Function(String name) test) {
  final List<String> found = <String>[];
  void walk(Directory d) {
    for (final FileSystemEntity e in d.listSync(followLinks: false)) {
      final String name = e.path.split(Platform.pathSeparator).last;
      if (e is Directory) {
        if (name == '.dart_tool' || name == 'build' || name == '.git') continue;
        walk(e);
      } else if (e is File && test(name)) {
        found.add(e.path);
      }
    }
  }

  if (Directory(dir).existsSync()) walk(Directory(dir));
  return found;
}

/// 复制目录（只用于把 flutter create 的平台壳搬进来）。
void copyDirectory(String from, String to) {
  Directory(to).createSync(recursive: true);
  for (final FileSystemEntity e in Directory(
    from,
  ).listSync(followLinks: false)) {
    final String name = e.path.split(Platform.pathSeparator).last;
    final String target = join(to, name);
    if (e is Directory) {
      copyDirectory(e.path, target);
    } else if (e is File) {
      e.copySync(target);
    } else if (e is Link) {
      Link(target).createSync(e.targetSync());
    }
  }
}

/// 按 PATH 找可执行文件。
String? which(String name) {
  final String path = Platform.environment['PATH'] ?? '';
  final List<String> exts = Platform.isWindows
      ? <String>['.bat', '.exe', '']
      : <String>[''];
  for (final String dir in path.split(Platform.isWindows ? ';' : ':')) {
    if (dir.isEmpty) continue;
    for (final String ext in exts) {
      final String candidate = join(dir, '$name$ext');
      if (File(candidate).existsSync()) return candidate;
    }
  }
  return null;
}
