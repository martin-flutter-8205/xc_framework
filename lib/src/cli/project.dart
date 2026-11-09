/// App 工程模型：根目录、业务包、资源声明。
///
/// 约定：App 根目录有 `pubspec.yaml` + `lib/main.dart`。
/// 业务包来源有两处：
///
/// 1. 根目录 `xc.yaml` 的 `workspace:` 清单（推荐）——业务包与框架包都是独立
///    git 仓库时，在这里声明本机检出目录，`xc gen / assets / check` 才知道去哪扫；
/// 2. 根目录 `packages/<name>/`（兼容旧布局，存在就自动纳入）。
library;

import 'dart:io';

import 'console.dart';
import 'fs.dart';

class Project {
  Project._({required this.root, required this.appName});

  /// App 根目录（绝对路径）。
  final String root;

  /// pubspec 里的 name，用于 flutter create --project-name。
  final String appName;

  String get pubspecPath => join(root, 'pubspec.yaml');

  /// 从当前目录（或指定目录）向上找 App 根。
  ///
  /// 判据：同时存在 `pubspec.yaml` 与 `lib/main.dart`。业务包没有 main.dart，
  /// 所以不会在 `packages/xxx` 里被误认成 App。
  static Project discover({String? dir}) {
    String current = normalize(
      Directory(dir ?? Directory.current.path).absolute.path,
    );
    for (int i = 0; i < 8; i++) {
      final File pubspec = File(join(current, 'pubspec.yaml'));
      if (pubspec.existsSync() &&
          File(join(current, 'lib/main.dart')).existsSync()) {
        final String yaml = pubspec.readAsStringSync();
        return Project._(
          root: current,
          appName: parseYamlScalar(yaml, 'name') ?? _baseName(current),
        );
      }
      final String up = dirname(current);
      if (up == current) break;
      current = up;
    }
    throw XcFailure(
      '当前目录不在 Flutter App 工程内（没找到 pubspec.yaml + lib/main.dart）。\n'
      '  请在 App 根目录执行，或用 --dir 指定工程目录。',
    );
  }

  /// App 依赖的代码包目录（绝对路径，去重后按路径排序）。
  ///
  /// 来源：`xc.yaml` 的 `workspace:` 清单 + 旧布局的 `packages/*`，
  /// 只保留带 `pubspec.yaml` 的目录。
  List<String> get packageDirs {
    final Set<String> dirs = <String>{};
    for (final String member in _workspaceMembers()) {
      final String dir = normalize(join(root, member));
      if (File(join(dir, 'pubspec.yaml')).existsSync()) {
        dirs.add(dir);
      }
    }
    final Directory packagesDir = Directory(join(root, 'packages'));
    if (packagesDir.existsSync()) {
      for (final Directory d in packagesDir.listSync().whereType<Directory>()) {
        final String dir = normalize(d.path);
        if (File(join(dir, 'pubspec.yaml')).existsSync()) {
          dirs.add(dir);
        }
      }
    }
    return dirs.toList()..sort();
  }

  /// 解析根目录 `xc.yaml` 里 `workspace:` 段的 `- ../xxx` 条目。
  List<String> _workspaceMembers() {
    final File manifest = File(join(root, 'xc.yaml'));
    if (!manifest.existsSync()) return <String>[];
    final List<String> members = <String>[];
    bool inWorkspace = false;
    for (final String raw in manifest.readAsStringSync().split('\n')) {
      final String line = stripComment(raw);
      if (line.trim().isEmpty) continue;
      final String t = line.trim();
      final int indent = line.length - line.trimLeft().length;
      if (indent == 0) {
        inWorkspace = t == 'workspace:';
        continue;
      }
      if (!inWorkspace || !t.startsWith('- ')) continue;
      String value = t.substring(2).trim();
      value = value.replaceAll('"', '').replaceAll("'", '');
      if (value.isNotEmpty) members.add(value);
    }
    return members;
  }

  /// 需要一起清理 / 分析 / 测试的目录（App 根 + 业务包）。
  List<String> get codeDirs => <String>[root, ...packageDirs];

  /// 有实际测试用例的包。
  List<String> get testDirs => codeDirs
      .where(
        (String dir) =>
            Directory(join(dir, 'test')).existsSync() &&
            findFiles(
              join(dir, 'test'),
              (String name) => name.endsWith('_test.dart'),
            ).isNotEmpty,
      )
      .toList();

  /// 读本工程的资源声明（每个包各自声明）。
  List<AssetPackage> get assetPackages {
    final List<AssetPackage> result = <AssetPackage>[];
    for (final String dir in codeDirs) {
      final File pubspec = File(join(dir, 'pubspec.yaml'));
      if (!pubspec.existsSync()) continue;
      final String yaml = pubspec.readAsStringSync();
      final List<String> declared = parseAssetEntries(yaml);
      if (declared.isEmpty) continue;
      result.add(
        AssetPackage(
          dir: dir,
          name: parseYamlScalar(yaml, 'name') ?? _baseName(dir),
          member: relative(root, dir),
          declared: declared,
          isApp: dir == root,
        ),
      );
    }
    return result;
  }
}

class AssetPackage {
  AssetPackage({
    required this.dir,
    required this.name,
    required this.member,
    required this.declared,
    required this.isApp,
  });

  final String dir;
  final String name;
  final String member;
  final List<String> declared;

  /// App 包是 bundle 的 root，资源路径不带前缀；业务包带 `packages/<name>/`。
  final bool isApp;

  String get bundlePrefix => isApp ? '' : 'packages/$name/';
}

/// 扫 pubspec 的顶格 `flutter:` 段里的 `assets:` 条目。
List<String> parseAssetEntries(String yaml) {
  final List<String> entries = <String>[];
  bool inFlutter = false;
  bool inAssets = false;
  int assetsIndent = -1;

  for (final String raw in yaml.split('\n')) {
    final String line = stripComment(raw);
    if (line.trim().isEmpty) continue;
    final int indent = line.length - line.trimLeft().length;
    final String t = line.trim();

    // 顶格键决定当前顶层段；只认顶格 flutter:，忽略 environment 下缩进的同名键。
    if (indent == 0) {
      inFlutter = t == 'flutter:';
      inAssets = false;
      assetsIndent = -1;
      continue;
    }
    if (!inFlutter) continue;

    if (!inAssets) {
      if (t == 'assets:') {
        inAssets = true;
        assetsIndent = indent;
      }
      continue;
    }
    if (indent <= assetsIndent) {
      inAssets = false;
      continue;
    }
    if (!t.startsWith('- ')) continue;

    String value = t.substring(2).trim();
    if (value.startsWith('path:')) value = value.substring(5).trim();
    value = value.replaceAll('"', '').replaceAll("'", '');
    if (value.isNotEmpty) entries.add(value);
  }
  return entries;
}

String? parseYamlScalar(String yaml, String key) {
  final RegExp re = RegExp('^$key:\\s*(.+)\$', multiLine: true);
  final RegExpMatch? match = re.firstMatch(yaml);
  if (match == null) return null;
  return match.group(1)!.trim().replaceAll('"', '').replaceAll("'", '');
}

String stripComment(String line) {
  final int i = line.indexOf('#');
  if (i < 0) return line;
  final String head = line.substring(0, i);
  if ("'".allMatches(head).length.isOdd || '"'.allMatches(head).length.isOdd)
    return line;
  return head;
}

String _baseName(String path) {
  final String normalized = normalize(path);
  final int i = normalized.lastIndexOf('/');
  return i < 0 ? normalized : normalized.substring(i + 1);
}
