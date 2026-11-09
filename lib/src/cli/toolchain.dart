/// Flutter / Dart 工具链探测与子进程执行。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'console.dart';
import 'fs.dart';

class Toolchain {
  Toolchain(this.flutter);

  /// flutter 可执行文件绝对路径。
  final String flutter;

  String get binDir => dirname(flutter);

  /// 优先用 flutter 自带的 dart，避免 PATH 里没有 dart。
  String get dart {
    final String sibling = join(
      binDir,
      Platform.isWindows ? 'dart.bat' : 'dart',
    );
    return File(sibling).existsSync() ? sibling : 'dart';
  }

  static Toolchain discover() {
    final List<String> candidates = <String>[
      if (Platform.environment['FLUTTER_ROOT'] != null)
        join(
          join(Platform.environment['FLUTTER_ROOT']!, 'bin'),
          Platform.isWindows ? 'flutter.bat' : 'flutter',
        ),
      which('flutter') ?? '',
      join(join(_home, 'development/flutter/bin'), 'flutter'),
      join(join(_home, 'flutter/bin'), 'flutter'),
      join(join(_home, 'fvm/default/bin'), 'flutter'),
      '/opt/homebrew/bin/flutter',
      '/usr/local/bin/flutter',
    ];
    for (final String path in candidates) {
      if (path.isEmpty) continue;
      if (File(path).existsSync()) return Toolchain(path);
    }
    throw XcFailure('找不到 flutter。把 flutter 加进 PATH，或设置 FLUTTER_ROOT 后重试。');
  }

  /// 子进程环境：flutter bin 进 PATH；有代理时补 NO_PROXY（flutter_tester 要连本机 websocket）。
  Map<String, String> get env {
    final Map<String, String> env = Map<String, String>.from(
      Platform.environment,
    );
    final String sep = Platform.isWindows ? ';' : ':';
    final String path = env['PATH'] ?? '';
    env['PATH'] = path.isEmpty ? binDir : '$binDir$sep$path';

    final String proxy =
        env['HTTP_PROXY'] ??
        env['http_proxy'] ??
        env['HTTPS_PROXY'] ??
        env['https_proxy'] ??
        '';
    if (proxy.isNotEmpty) {
      final Set<String> noProxy = (env['NO_PROXY'] ?? env['no_proxy'] ?? '')
          .split(',')
          .map((String e) => e.trim())
          .where((String e) => e.isNotEmpty)
          .toSet();
      noProxy.addAll(<String>['127.0.0.1', 'localhost', '::1']);
      final String joined = noProxy.join(',');
      env['NO_PROXY'] = joined;
      env['no_proxy'] = joined;
    }
    return env;
  }

  /// 跑命令：成功返回输出；失败打印输出并抛 XcFailure。
  ///
  /// [echo] 为真时实时透传子进程输出（pub get / test 这类有进度信息的命令）。
  Future<String> run(
    List<String> cmd, {
    required String cwd,
    bool dryRun = false,
    bool echo = false,
  }) async {
    final String printable = cmd
        .map((String c) => c.contains(' ') ? '"$c"' : c)
        .join(' ');
    if (dryRun) {
      bullet('${dim('\$ $printable')}  ${dim('(dry-run)')}');
      return '';
    }
    if (!echo) bullet(dim('\$ $printable'));

    final Process process;
    try {
      process = await Process.start(
        cmd.first,
        cmd.skip(1).toList(),
        workingDirectory: cwd,
        environment: env,
      );
    } on ProcessException catch (e) {
      throw XcFailure('无法执行 $printable：${e.message}');
    }

    final StringBuffer buffer = StringBuffer();
    final List<Future<void>> drained = <Future<void>>[];
    void pipe(Stream<List<int>> stream) {
      final Completer<void> done = Completer<void>();
      drained.add(done.future);
      stream
          .transform(utf8.decoder)
          .listen(
            (String chunk) {
              buffer.write(chunk);
              if (echo) stdout.write(chunk);
            },
            onError: (Object _) {
              if (!done.isCompleted) done.complete();
            },
            onDone: () {
              if (!done.isCompleted) done.complete();
            },
          );
    }

    pipe(process.stdout);
    pipe(process.stderr);
    final int code = await process.exitCode;
    await Future.wait(drained);

    if (code != 0) {
      if (!echo) {
        final String out = buffer.toString().trimRight();
        if (out.isNotEmpty) stderr.writeln(out);
      }
      throw XcFailure('命令失败（exit $code）：$printable');
    }
    return buffer.toString();
  }
}

String get _home =>
    Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '';
