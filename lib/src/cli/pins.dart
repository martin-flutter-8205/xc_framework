/// 依赖版本守卫：所有依赖声明必须写精确版本号，不许出现 `^` / `~>` / `>=` / `any`。
///
/// 覆盖三类清单：
/// - `pubspec.yaml` 的 dependencies / dev_dependencies / dependency_overrides
/// - `Gemfile` 的 gem 行（iOS 构建工具链）
/// - `Podfile` 的 pod 行
///
/// 判断标准是「声明是否唯一确定一个版本」，而不是 lock 文件是否在场：
/// lock 只是某次解析结果的快照，删掉（`xc --fresh`）或换机器就没了。
library;

import 'dart:io';

import 'fs.dart';
import 'project.dart' show stripComment;

/// 一条不合规的依赖声明。
class PinIssue {
  PinIssue({
    required this.file,
    required this.line,
    required this.name,
    required this.spec,
    required this.reason,
  });

  /// 相对工程根的路径。
  final String file;
  final int line;
  final String name;

  /// 原样的版本写法（空字符串表示没写）。
  final String spec;
  final String reason;

  @override
  String toString() => '$file:$line  $name  $spec  $reason';
}

/// `1.2.3` / `1.2.3+4` / `1.2.3-dev.1`：唯一确定一个版本。
final RegExp _exact = RegExp(r'^\d+\.\d+\.\d+(?:[-+][0-9A-Za-z.\-]+)?$');

const Set<String> _depSections = <String>{
  'dependencies',
  'dev_dependencies',
  'dependency_overrides',
};

/// 扫一个 App 工程（含它 path 依赖到的框架包）的全部依赖清单。
List<PinIssue> checkPins(
  String appRoot, {
  List<String> extraDirs = const <String>[],
}) {
  final List<PinIssue> issues = <PinIssue>[];
  final Set<String> visited = <String>{};
  final List<String> dirs = <String>[appRoot, ...extraDirs];

  void visit(String dir) {
    final String key = _canonical(dir);
    if (!visited.add(key)) return;

    final String pubspec = join(dir, 'pubspec.yaml');
    if (File(pubspec).existsSync()) {
      final String yaml = File(pubspec).readAsStringSync();
      issues.addAll(_scanPubspec(yaml, _show(appRoot, pubspec)));
      // 跟随 path 依赖：框架包在工程目录之外，也得守同一条规矩
      for (final String dep in _pathDeps(yaml)) {
        visit(join(dir, dep));
      }
    }

    final String gemfile = join(dir, 'Gemfile');
    if (File(gemfile).existsSync()) {
      issues.addAll(
        _scanGemfile(File(gemfile).readAsLinesSync(), _show(appRoot, gemfile)),
      );
    }

    final String podfile = join(dir, 'Podfile');
    if (File(podfile).existsSync()) {
      issues.addAll(
        _scanPodfile(File(podfile).readAsLinesSync(), _show(appRoot, podfile)),
      );
    }
  }

  for (final String dir in dirs) {
    visit(dir);
  }
  // 平台目录里的清单（iOS 的 Gemfile/Podfile 可能放在 ios/ 下）
  for (final String dir in <String>[...dirs]) {
    for (final String platform in <String>['ios', 'macos']) {
      visit(join(dir, platform));
    }
  }

  issues.sort((PinIssue a, PinIssue b) {
    final int byFile = a.file.compareTo(b.file);
    return byFile != 0 ? byFile : a.line.compareTo(b.line);
  });
  return issues;
}

String _show(String root, String path) {
  final String base = _canonical(root);
  final String target = _canonical(path);
  if (inside(base, target)) return relative(base, target);
  // 框架仓库通常与 App 平级，按兄弟目录显示更好读
  final String parent = _canonical(dirname(base));
  if (parent != base && inside(parent, target)) return relative(parent, target);
  return target;
}

/// 折叠 `.` 与 `..`：同一个文件经不同相对路径进来时必须是同一个 key。
String _canonical(String path) {
  final String abs = normalize(File(path).absolute.path);
  final bool rooted = abs.startsWith('/');
  final List<String> parts = <String>[];
  for (final String seg in abs.split('/')) {
    if (seg.isEmpty || seg == '.') continue;
    if (seg == '..') {
      if (parts.isNotEmpty) parts.removeLast();
      continue;
    }
    parts.add(seg);
  }
  return rooted ? '/${parts.join('/')}' : parts.join('/');
}

// ───────────────────────────── pubspec.yaml ─────────────────────────────

List<PinIssue> _scanPubspec(String yaml, String display) {
  final List<String> lines = yaml.split('\n');
  final List<PinIssue> issues = <PinIssue>[];
  String? section;

  for (int i = 0; i < lines.length; i++) {
    final String line = stripComment(lines[i]);
    final String text = line.trim();
    if (text.isEmpty) continue;
    final int indent = line.length - line.trimLeft().length;

    if (indent == 0) {
      final String key = text.endsWith(':')
          ? text.substring(0, text.length - 1).trim()
          : '';
      section = _depSections.contains(key) ? key : null;
      continue;
    }
    if (section == null || indent != 2) continue;

    final int colon = text.indexOf(':');
    if (colon <= 0) continue;
    final String name = text.substring(0, colon).trim();
    final String inline = _unquote(text.substring(colon + 1).trim());

    // 收集该依赖的子行（path / git / sdk / version 都在这层）
    final List<String> child = <String>[];
    for (int j = i + 1; j < lines.length; j++) {
      final String sub = stripComment(lines[j]);
      if (sub.trim().isEmpty) continue;
      if (sub.length - sub.trimLeft().length <= 2) break;
      child.add(sub.trim());
    }

    final bool local = child.any(
      (String c) =>
          c.startsWith('path:') || c.startsWith('git:') || c.startsWith('sdk:'),
    );
    if (local) continue; // 本地源码 / SDK 来源，版本由仓库或 SDK 决定

    String? spec = inline.isEmpty ? null : inline;
    for (final String c in child) {
      if (c.startsWith('version:')) spec = _unquote(c.substring(8).trim());
    }

    final String? reason = _judge(spec);
    if (reason != null) {
      issues.add(
        PinIssue(
          file: display,
          line: i + 1,
          name: name,
          spec: spec ?? '',
          reason: reason,
        ),
      );
    }
  }
  return issues;
}

/// 取出 pubspec 里所有 path 依赖的相对路径。
List<String> _pathDeps(String yaml) {
  final List<String> result = <String>[];
  final RegExp re = RegExp(r'^\s+path:\s*(.+)$', multiLine: true);
  for (final RegExpMatch m in re.allMatches(yaml)) {
    final String value = _unquote(m.group(1)!.trim());
    if (value.isNotEmpty) result.add(value);
  }
  return result;
}

// ─────────────────────────────── Gemfile ───────────────────────────────

List<PinIssue> _scanGemfile(List<String> lines, String display) {
  final List<PinIssue> issues = <PinIssue>[];
  final RegExp gem = RegExp(r'''^\s*gem\s+['"]([^'"]+)['"]\s*(.*)$''');
  final RegExp quoted = RegExp(r'''['"]([^'"]+)['"]''');

  for (int i = 0; i < lines.length; i++) {
    final String line = stripComment(lines[i]);
    if (line.trim().isEmpty) continue;
    final RegExpMatch? m = gem.firstMatch(line);
    if (m == null) continue;

    final String name = m.group(1)!;
    final String rest = m.group(2)!.trim();
    if (rest.startsWith(':path') || rest.startsWith(':git')) continue;

    final List<String> specs = quoted
        .allMatches(rest)
        .map((RegExpMatch q) => q.group(1)!)
        .toList();
    if (specs.isEmpty) {
      issues.add(
        PinIssue(
          file: display,
          line: i + 1,
          name: name,
          spec: '',
          reason: '没写版本号（等于任意版本）',
        ),
      );
      continue;
    }
    for (final String spec in specs) {
      final String? reason = _judge(spec);
      if (reason != null) {
        issues.add(
          PinIssue(
            file: display,
            line: i + 1,
            name: name,
            spec: spec,
            reason: reason,
          ),
        );
      }
    }
  }
  return issues;
}

// ─────────────────────────────── Podfile ───────────────────────────────

List<PinIssue> _scanPodfile(List<String> lines, String display) {
  final List<PinIssue> issues = <PinIssue>[];
  final RegExp pod = RegExp(r'''^\s*pod\s+['"]([^'"]+)['"]\s*(.*)$''');
  final RegExp quoted = RegExp(r'''['"]([^'"]+)['"]''');

  for (int i = 0; i < lines.length; i++) {
    final String line = stripComment(lines[i]);
    if (line.trim().isEmpty) continue;
    final RegExpMatch? m = pod.firstMatch(line);
    if (m == null) continue;

    final String name = m.group(1)!;
    final String rest = m.group(2)!.trim();
    if (rest.contains(':path') ||
        rest.contains(':git') ||
        rest.contains(':podspec'))
      continue;

    final List<String> specs = quoted
        .allMatches(rest)
        .map((RegExpMatch q) => q.group(1)!)
        .toList();
    if (specs.isEmpty) {
      issues.add(
        PinIssue(
          file: display,
          line: i + 1,
          name: name,
          spec: '',
          reason: '没写版本号（等于任意版本）',
        ),
      );
      continue;
    }
    final String? reason = _judge(specs.first);
    if (reason != null) {
      issues.add(
        PinIssue(
          file: display,
          line: i + 1,
          name: name,
          spec: specs.first,
          reason: reason,
        ),
      );
    }
  }
  return issues;
}

// ─────────────────────────────── 公共判断 ───────────────────────────────

/// 合规返回 null，否则返回原因。
String? _judge(String? spec) {
  if (spec == null || spec.isEmpty || spec == 'any' || spec == '*') {
    return '没写版本号（等于任意版本）';
  }
  if (_exact.hasMatch(spec)) return null;
  return '范围约束，应改成精确版本';
}

String _unquote(String value) {
  if (value.length >= 2) {
    if (value.startsWith('"') && value.endsWith('"'))
      return value.substring(1, value.length - 1);
    if (value.startsWith("'") && value.endsWith("'"))
      return value.substring(1, value.length - 1);
  }
  return value;
}
