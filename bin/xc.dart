import 'package:xc_framework/xc_framework.dart';

/// 全局命令 `xc` 的入口。
///
/// 安装：
///   dart pub global activate --source path ~/Desktop/code/xc_framework
/// 之后在任意 App 工程目录执行 `xc` 或 `xc run`。
Future<void> main(List<String> args) => runXc(args);
