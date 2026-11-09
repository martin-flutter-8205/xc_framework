/// 终端输出：颜色、缩进日志、耗时与体积格式化。
library;

import 'dart:io';

const String _reset = '\x1B[0m';
const String _bold = '1';
const String _dim = '2';
const String _red = '31';
const String _green = '32';
const String _yellow = '33';
const String _cyan = '36';

bool get useColor =>
    stdout.hasTerminal &&
    Platform.environment['NO_COLOR'] == null &&
    Platform.environment['TERM'] != 'dumb';

String paint(String code, String text) =>
    useColor ? '\x1B[${code}m$text$_reset' : text;

String bold(String text) => paint(_bold, text);
String dim(String text) => paint(_dim, text);
String red(String text) => paint(_red, text);
String green(String text) => paint(_green, text);
String yellow(String text) => paint(_yellow, text);
String cyan(String text) => paint(_cyan, text);

void blank() => stdout.writeln('');
void bullet(String text) => stdout.writeln('  $text');
void info(String text) => stdout.writeln('  $text');
void step(String text) => stdout.writeln('  ${dim('·')} $text');
void warn(String text) => stdout.writeln('  ${yellow('!')} $text');
void hint(String text) => stdout.writeln('  ${dim('→ $text')}');
void ok(String text) => stdout.writeln('${green('✔')} $text');

String size(int bytes) {
  if (bytes < 1024) return '$bytes B';
  const List<String> units = <String>['KB', 'MB', 'GB'];
  double value = bytes / 1024;
  int unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  return '${value.toStringAsFixed(value >= 10 ? 0 : 1)} ${units[unit]}';
}

String duration(Duration d) {
  if (d.inMilliseconds < 1000) return '${d.inMilliseconds}ms';
  if (d.inSeconds < 60)
    return '${(d.inMilliseconds / 1000).toStringAsFixed(1)}s';
  return '${d.inMinutes}m${d.inSeconds % 60}s';
}

/// 可预期的失败：打印一句话，退出码 1（参数错误用 64）。
class XcFailure implements Exception {
  XcFailure(this.message);
  final String message;
  @override
  String toString() => message;
}
