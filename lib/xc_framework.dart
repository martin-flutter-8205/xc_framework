/// xc 框架：运行时包（xc_platform / xc_ui）与命令行工具。
///
/// App 工程通过 path / git 依赖 `packages/xc_platform` 与 `packages/xc_ui`；
/// 命令行 `xc` 通过 `dart pub global activate --source path <本仓库>` 安装。
library;

export 'src/cli/cli.dart' show runXc;
export 'src/codegen/generator.dart' show Generator;
