/// 资源清单：扫描 pubspec 声明的 assets，为每个包生成类型安全常量。
///
/// 关键机制（实测）：依赖包自己声明的 assets 会被打进 App 的 bundle，但
/// bundle 内路径带 `packages/<包名>/` 前缀；App 包是 root，不带前缀。
/// 生成常量时直接写好真实路径，UI 代码里不用拼前缀。
library;

import 'dart:io';

import 'console.dart';
import 'fs.dart';
import 'project.dart';

Future<void> refreshAssets(Project project, {required bool dryRun}) async {
  final List<AssetPackage> packages = project.assetPackages;
  if (packages.isEmpty) {
    info('没有任何包在 pubspec 里声明 assets，跳过');
    hint('在包的 flutter: 下加 assets: 后重跑，会自动产出常量清单');
    return;
  }

  for (final AssetPackage pkg in packages) {
    final List<String> files = _resolve(pkg);
    _warnUndeclared(pkg, files);

    if (files.isEmpty) {
      info('${pkg.member} 声明的目录里没有文件');
      continue;
    }

    final String className = '${_pascal(pkg.name)}Assets';
    final String content = _render(pkg, files, className);
    final String outPath = join(pkg.dir, 'lib/gen/assets_gen.dart');
    final File out = File(outPath);
    final bool same = out.existsSync() && out.readAsStringSync() == content;
    final String shown = relative(project.root, outPath);

    if (dryRun) {
      bullet('$shown  ${dim('${files.length} 个资源 (dry-run)')}');
      continue;
    }
    out.parent.createSync(recursive: true);
    if (same) {
      bullet('$shown  ${dim('未变化')}');
      continue;
    }
    out.writeAsStringSync(content);
    bullet('$shown  ${dim('${files.length} 个资源')}');
    info(
      '类名 $className，前缀 ${pkg.bundlePrefix.isEmpty ? '无（App 包）' : pkg.bundlePrefix}',
    );
  }

  hint('新增/删除资源后重跑本命令；运行时替换图片需 hot restart，改代码 hot reload 即可');
}

List<String> _resolve(AssetPackage pkg) {
  final Set<String> files = <String>{};
  for (final String entry in pkg.declared) {
    final String abs = join(pkg.dir, normalize(entry));
    final FileSystemEntityType type = FileSystemEntity.typeSync(abs);
    if (type == FileSystemEntityType.directory) {
      for (final FileSystemEntity e in Directory(
        abs,
      ).listSync(recursive: true)) {
        if (e is! File) continue;
        final String rel = relative(pkg.dir, e.path);
        if (_isAsset(rel)) files.add(rel);
      }
    } else if (type == FileSystemEntityType.file) {
      files.add(normalize(entry));
    } else {
      throw XcFailure('pubspec 声明的资源不存在：$entry（${pkg.member}/pubspec.yaml）');
    }
  }
  final List<String> sorted = files.toList()..sort();
  return sorted;
}

bool _isAsset(String rel) {
  final String name = rel.split('/').last;
  if (name.isEmpty || name.startsWith('.')) return false;
  if (name == '.DS_Store' || name == '.gitkeep') return false;
  return true;
}

void _warnUndeclared(AssetPackage pkg, List<String> declaredFiles) {
  final String assetsRoot = join(pkg.dir, 'assets');
  if (!Directory(assetsRoot).existsSync()) return;
  final Set<String> declared = declaredFiles.toSet();
  final List<String> missing = <String>[];
  for (final FileSystemEntity e in Directory(
    assetsRoot,
  ).listSync(recursive: true)) {
    if (e is! File) continue;
    final String rel = relative(pkg.dir, e.path);
    if (!_isAsset(rel)) continue;
    if (!declared.contains(rel)) missing.add(rel);
  }
  if (missing.isEmpty) return;
  missing.sort();
  warn('${missing.length} 个资源未在 pubspec 声明，运行时加载会失败：');
  for (final String path in missing.take(6)) {
    bullet(yellow(path));
  }
  if (missing.length > 6) bullet(dim('…还有 ${missing.length - 6} 个'));
}

String _render(AssetPackage pkg, List<String> files, String className) {
  final Map<String, String> names = <String, String>{};
  final Set<String> used = <String>{};
  for (final String path in files) {
    String name = _constName(path);
    if (!used.add(name)) {
      final String ext = path.contains('.') ? path.split('.').last : 'file';
      name = '$name${_pascal(ext)}';
      used.add(name);
    }
    names[path] = name;
  }

  final StringBuffer b = StringBuffer();
  b.writeln('// GENERATED CODE - DO NOT MODIFY BY HAND');
  b.writeln('// 由 `xc assets` 生成，来源 ${pkg.name}/pubspec.yaml');
  b.writeln();
  b.writeln('/// ${pkg.name} 已声明的静态资源。');
  b.writeln('///');
  b.writeln('/// 值是 bundle 内真实路径；业务包带 `packages/${pkg.name}/` 前缀，');
  b.writeln('/// 这样包内测试与装进 App 后都能加载。');
  b.writeln('abstract final class $className {');
  for (final String path in files) {
    b.writeln(
      "  static const String ${names[path]} = '${pkg.bundlePrefix}$path';",
    );
  }
  b.writeln();
  b.writeln('  /// 全部资源，可用于 AssetBundle 预热。');
  b.writeln('  static const List<String> all = <String>[');
  for (final String path in files) {
    b.writeln('    ${names[path]},');
  }
  b.writeln('  ];');
  b.writeln('}');
  return b.toString();
}

String _constName(String path) {
  final String withoutRoot = path.startsWith('assets/')
      ? path.substring(7)
      : path;
  final List<String> parts = withoutRoot.split('/');
  final String file = parts.removeLast();
  final int dot = file.lastIndexOf('.');
  final String base = dot > 0 ? file.substring(0, dot) : file;
  final String pascal = <String>[...parts, base].map(_pascal).join();
  if (pascal.isEmpty) return 'asset';
  return pascal[0].toLowerCase() + pascal.substring(1);
}

String _pascal(String input) {
  final List<String> words = input
      .split(RegExp(r'[^A-Za-z0-9]+'))
      .where((String w) => w.isNotEmpty)
      .toList();
  return words.map((String w) => w[0].toUpperCase() + w.substring(1)).join();
}
