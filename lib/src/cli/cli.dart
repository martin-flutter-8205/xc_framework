/// `xc` 命令实现：在 App 工程里做 clean / deps / gen / assets / check / run。
library;

import 'dart:io';

import '../codegen/generator.dart';
import 'assets.dart';
import 'console.dart';
import 'fs.dart';
import 'pins.dart';
import 'project.dart';
import 'toolchain.dart';

const String xcVersion = '0.1.0';

const List<String> _defaultSteps = <String>[
  'clean',
  'deps',
  'gen',
  'assets',
  'check',
];

const Map<String, String> _labels = <String, String>{
  'clean': '清理构建产物与依赖缓存',
  'deps': '重新安装依赖',
  'gen': '重新生成代码产物',
  'assets': '刷新资源清单',
  'pin': '依赖版本检查',
  'check': '静态分析 + 全部测试',
  'run': '启动 App',
};

Future<void> runXc(List<String> argv) async {
  final _Args args;
  try {
    args = _Args.parse(argv);
  } on XcFailure catch (e) {
    stderr.writeln('${red('✘')} ${e.message}');
    stderr.writeln(dim('用 xc --help 查看用法'));
    exit(64);
  }

  if (args.help) {
    stdout.writeln(_usage());
    return;
  }
  if (args.version) {
    stdout.writeln('xc $xcVersion');
    return;
  }

  final Project project;
  final Toolchain toolchain;
  try {
    project = Project.discover(dir: args.dir);
    toolchain = Toolchain.discover();
  } on XcFailure catch (e) {
    stderr.writeln('${red('✘')} ${e.message}');
    exit(1);
  }

  stdout.writeln('${bold('xc $xcVersion')} ${dim('· 响彻星空工程运维')}');
  stdout.writeln(dim('工程 ${project.root}  (${project.appName})'));
  stdout.writeln(dim('业务包 ${project.packageDirs.length} 个'));

  final Stopwatch total = Stopwatch()..start();
  final List<String> steps = args.steps;
  try {
    for (int i = 0; i < steps.length; i++) {
      final String stepName = steps[i];
      final String label = _labels[stepName] ?? stepName;
      final String counter = steps.length > 1
          ? dim('  ${i + 1}/${steps.length}')
          : '';
      blank();
      stdout.writeln('${cyan('▸')} ${bold(label)}$counter');
      final Stopwatch watch = Stopwatch()..start();
      await _dispatch(stepName, project, toolchain, args);
      ok('$label ${dim(duration(watch.elapsed))}');
    }
  } on XcFailure catch (e) {
    blank();
    stderr.writeln('${red('✘')} ${e.message}');
    exit(1);
  }

  blank();
  stdout.writeln('${green('完成')} ${dim(duration(total.elapsed))}');
}

Future<void> _dispatch(
  String stepName,
  Project project,
  Toolchain toolchain,
  _Args args,
) async {
  switch (stepName) {
    case 'clean':
      await _clean(project, args);
    case 'deps':
      await _deps(project, toolchain, args);
    case 'gen':
      await _gen(project, args);
    case 'assets':
      await refreshAssets(project, dryRun: args.dryRun);
    case 'pin':
      await _pin(project, args);
    case 'check':
      await _check(project, toolchain, args);
    case 'run':
      await _run(project, toolchain, args);
    default:
      throw XcFailure('未知步骤：$stepName');
  }
}

// ─────────────────────────────── clean ───────────────────────────────

const List<String> _cleanTargets = <String>[
  'build',
  '.dart_tool',
  '.flutter-plugins',
  '.flutter-plugins-dependencies',
  '.packages',
  'ios/Pods',
  'ios/.symlinks',
  'ios/Flutter/ephemeral',
  'macos/Pods',
  'macos/Flutter/ephemeral',
  'android/.gradle',
  'android/.cxx',
  'android/app/.cxx',
  'android/local.properties',
  'windows/flutter/ephemeral',
  'linux/flutter/ephemeral',
];

Future<void> _clean(Project project, _Args args) async {
  int count = 0;
  int freed = 0;

  for (final String base in project.codeDirs) {
    for (final String target in _cleanTargets) {
      final String path = join(base, target);
      final FileSystemEntityType type = FileSystemEntity.typeSync(path);
      if (type == FileSystemEntityType.notFound) continue;
      if (!inside(project.root, path)) {
        warn('跳过越界路径 $path');
        continue;
      }
      final int bytes = sizeOf(path);
      final String shown = relative(project.root, path);
      if (args.dryRun) {
        bullet('$shown  ${dim(size(bytes))}  ${dim('(dry-run)')}');
      } else {
        deleteEntity(path);
        bullet('$shown  ${dim(size(bytes))}');
      }
      count++;
      freed += bytes;
    }
  }

  if (args.fresh) {
    for (final String base in project.codeDirs) {
      final String lock = join(base, 'pubspec.lock');
      if (!File(lock).existsSync()) continue;
      if (!args.dryRun) File(lock).deleteSync();
      bullet('${relative(project.root, lock)}  ${dim('版本锁定已解除')}');
      count++;
    }
  }

  if (count == 0) {
    info('没有可清理的产物，工程已经是干净的');
  } else {
    info('清理 $count 项，释放 ${size(freed)}${args.dryRun ? '（未真正删除）' : ''}');
  }
  if (!args.fresh && count > 0) hint('想连 pubspec.lock 一起重置，加 --fresh');
}

// ─────────────────────────────── deps ───────────────────────────────

Future<void> _deps(Project project, Toolchain toolchain, _Args args) async {
  final String verb = args.upgrade ? 'upgrade' : 'get';
  // 不用 workspace：每个包各自解析，才能在包目录里直接 analyze / test。
  for (final String dir in project.codeDirs) {
    step('flutter pub $verb  ${dim(relative(project.root, dir))}');
    await toolchain.run(
      <String>[toolchain.flutter, 'pub', verb],
      cwd: dir,
      dryRun: args.dryRun,
    );
  }
  if (args.upgrade) hint('--upgrade 已按最新兼容版本重解析');
}

// ─────────────────────────────── gen ───────────────────────────────

Future<void> _gen(Project project, _Args args) async {
  final int pages = findFiles(
    join(project.root, 'packages'),
    (String name) => name.endsWith('_page_com.dart'),
  ).length;
  step('扫描页面文件  ${dim('$pages 个')}');

  if (!File(join(project.root, '.dart_tool/package_config.json'))
          .existsSync() &&
      !args.dryRun) {
    throw XcFailure('依赖尚未安装（缺 .dart_tool/package_config.json），先执行 xc deps');
  }
  if (args.dryRun) {
    bullet(
      dim(
        '(dry-run) 会生成 ${pages} 个 part 文件与各包 lib/gen/generated_routes.g.dart',
      ),
    );
    return;
  }

  final List<String> logs = Generator(root: project.root).run();
  for (final String line in logs) {
    line.startsWith('[ERROR]')
        ? warn(line.replaceFirst('[ERROR] ', ''))
        : info(line);
  }
  if (logs.any((String line) => line.startsWith('[ERROR]'))) {
    throw XcFailure('生成器报了源码约定错误，先修掉再跑');
  }
  final int outputs = findFiles(
    project.root,
    (String name) => name.endsWith('.g.dart'),
  ).length;
  info('产物 $outputs 个 .g.dart');
}

// ─────────────────────────────── check ───────────────────────────────

Future<void> _pin(Project project, _Args args) async {
  final List<PinIssue> issues = checkPins(project.root);
  if (issues.isEmpty) {
    info('依赖全部写死精确版本（pubspec.yaml / Gemfile / Podfile）');
    return;
  }
  for (final PinIssue issue in issues) {
    warn(
      '${issue.file}:${issue.line}  ${issue.name}  ${dim(issue.spec)} ${issue.reason}',
    );
  }
  throw XcFailure(
    '${issues.length} 处依赖没固定版本：'
    '去掉 ^ / ~> / >= / any，写成 1.2.3 这样的精确版本',
  );
}

Future<void> _check(Project project, Toolchain toolchain, _Args args) async {
  await _pin(project, args);

  int failed = 0;
  for (final String dir in project.codeDirs) {
    step('flutter analyze  ${dim(relative(project.root, dir))}');
    try {
      await toolchain.run(
        <String>[toolchain.flutter, 'analyze'],
        cwd: dir,
        dryRun: args.dryRun,
      );
    } on XcFailure {
      failed++;
    }
  }
  if (failed > 0) throw XcFailure('$failed 个包 analyze 没通过');

  final List<String> testDirs = project.testDirs;
  if (testDirs.isEmpty) {
    warn('没有任何包带测试用例');
    return;
  }
  int testFailed = 0;
  for (final String dir in testDirs) {
    step('flutter test  ${dim(relative(project.root, dir))}');
    try {
      await toolchain.run(
        <String>[toolchain.flutter, 'test'],
        cwd: dir,
        dryRun: args.dryRun,
        echo: true,
      );
    } on XcFailure {
      testFailed++;
    }
  }
  if (testFailed > 0) throw XcFailure('$testFailed 个包的测试没通过');
  info('${testDirs.length} 个包全部通过');
}

// ─────────────────────────────── run ───────────────────────────────

Future<void> _run(Project project, Toolchain toolchain, _Args args) async {
  await _ensurePlatforms(project, toolchain, args);
  step('flutter run ${args.runArgs.join(' ')}');
  await toolchain.run(
    <String>[toolchain.flutter, 'run', ...args.runArgs],
    cwd: project.root,
    dryRun: args.dryRun,
    echo: true,
  );
}

/// 缺平台工程时自动补齐。
///
/// 目标平台按 `-d` 推断：`-d chrome` 补 web，`-d macos` 补 macos，
/// 其余（真机 / iOS 模拟器 / 不指定）补 android + ios。
///
/// 在临时目录跑 `flutter create` 再只拷平台目录，避免它覆盖 lib/main.dart
/// 和现有 pubspec。
Future<void> _ensurePlatforms(
  Project project,
  Toolchain toolchain,
  _Args args,
) async {
  final List<String> wanted = _targetPlatforms(args.runArgs);
  final List<String> missing = wanted
      .where((String p) => !Directory(join(project.root, p)).existsSync())
      .toList();
  if (missing.isEmpty) return;

  info('补齐平台工程：${missing.join('、')}');
  final Directory temp = Directory.systemTemp.createTempSync('xc_scaffold_');
  try {
    await toolchain.run(
      <String>[
        toolchain.flutter,
        'create',
        '--platforms=${missing.join(',')}',
        '--project-name',
        project.appName,
        '--org',
        'com.xc',
        '--no-pub',
        temp.path,
      ],
      cwd: temp.path,
      dryRun: args.dryRun,
    );
    if (args.dryRun) {
      bullet(dim('(dry-run) 会把 ${missing.join('、')} 拷进工程'));
      return;
    }
    for (final String platform in missing) {
      copyDirectory(join(temp.path, platform), join(project.root, platform));
      bullet('$platform/  ${dim('已就位')}');
    }
  } finally {
    if (temp.existsSync()) temp.deleteSync(recursive: true);
  }
}

/// 从 `-d/--device-id` 推断要补哪些平台。
List<String> _targetPlatforms(List<String> runArgs) {
  String? device;
  for (int i = 0; i < runArgs.length; i++) {
    final String arg = runArgs[i];
    if (arg == '-d' || arg == '--device-id') {
      if (i + 1 < runArgs.length) device = runArgs[i + 1];
    } else if (arg.startsWith('-d=')) {
      device = arg.substring(3);
    } else if (arg.startsWith('--device-id=')) {
      device = arg.substring('--device-id='.length);
    }
  }
  if (device == null) return <String>['android', 'ios'];
  if (device.contains('chrome') || device.contains('web'))
    return <String>['web'];
  if (device.contains('macos')) return <String>['macos'];
  if (device.contains('windows')) return <String>['windows'];
  if (device.contains('linux')) return <String>['linux'];
  return <String>['android', 'ios'];
}

// ─────────────────────────────── 参数 ───────────────────────────────

class _Args {
  _Args({
    required this.steps,
    required this.runArgs,
    this.dir,
    this.help = false,
    this.version = false,
    this.dryRun = false,
    this.fresh = false,
    this.upgrade = false,
  });

  final List<String> steps;
  final List<String> runArgs;
  final String? dir;
  final bool help;
  final bool version;
  final bool dryRun;
  final bool fresh;
  final bool upgrade;

  static _Args parse(List<String> argv) {
    final List<String> steps = <String>[];
    final List<String> runArgs = <String>[];
    String? dir;
    bool help = false;
    bool version = false;
    bool dryRun = false;
    bool fresh = false;
    bool upgrade = false;
    bool afterRun = false;

    for (int i = 0; i < argv.length; i++) {
      final String arg = argv[i];
      if (afterRun) {
        runArgs.add(arg);
        continue;
      }
      switch (arg) {
        case '-h':
        case '--help':
          help = true;
        case '--version':
          version = true;
        case '-n':
        case '--dry-run':
          dryRun = true;
        case '--fresh':
          fresh = true;
        case '--upgrade':
          upgrade = true;
        case '--dir':
          if (i + 1 >= argv.length) throw XcFailure('--dir 需要跟一个目录');
          dir = argv[++i];
        case 'all':
          steps.addAll(_defaultSteps);
        case 'clean':
        case 'deps':
        case 'gen':
        case 'assets':
        case 'pin':
        case 'check':
          steps.add(arg);
        case 'run':
          steps.add('run');
          afterRun = true;
        default:
          if (arg.startsWith('-')) throw XcFailure('未知选项：$arg');
          throw XcFailure('未知命令：$arg');
      }
    }

    final Set<String> seen = <String>{};
    steps.retainWhere(seen.add);
    if (steps.isEmpty) steps.addAll(_defaultSteps);
    return _Args(
      steps: steps,
      runArgs: runArgs,
      dir: dir,
      help: help,
      version: version,
      dryRun: dryRun,
      fresh: fresh,
      upgrade: upgrade,
    );
  }
}

String _usage() =>
    '''
${bold('xc $xcVersion')} ${dim('—— 响彻星空工程运维 CLI（App 工程内运行）')}

${bold('用法')}
  xc                        干净重建：clean → deps → gen → assets → check
  xc <command...>           按给定顺序执行
  xc run [flutter 参数]     重建后启动 App，例如 xc run -d chrome

${bold('命令')}
  clean    清理 build/、.dart_tool/、Pods 等（App + packages/ 下每个业务包）
  deps     安装依赖（App 根一次解析，业务包是 path 依赖）
  gen      扫描 *_page_com.dart 生成 part 文件与各包路由表
  assets   按包刷新 lib/gen/assets_gen.dart 常量
  pin      依赖版本守卫：pubspec / Gemfile / Podfile 必须是精确版本
  check    依赖版本守卫 + flutter analyze + 有测试的包 flutter test
  run      缺对应平台工程时自动补齐（按 -d 推断），然后 flutter run

${bold('选项')}
  -h, --help      显示帮助
      --version   显示版本
  -n, --dry-run   只打印计划，不改动磁盘
      --fresh     clean 时连 pubspec.lock 一起删
      --upgrade   deps 用 pub upgrade 代替 pub get
      --dir <path>  指定 App 根目录（默认从当前目录向上找）

${bold('安装')}
  dart pub global activate --source path <xc_framework 路径>
''';
