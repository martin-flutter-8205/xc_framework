# xc_framework

「响彻星空」的框架仓库：**运行时包 + 全局 CLI**。App 工程（`xc_app`）通过 path / git 依赖这里的包，通过 `xc` 命令做工程运维，两边互不侵入。

```
xc_framework/
├── bin/xc.dart                       # 全局命令入口（executables: xc）
├── lib/src/cli/                      # CLI：工程发现 / clean / deps / gen / assets / check / run
├── lib/src/codegen/generator.dart    # 注解驱动代码生成器（扫 *_page_com.dart）
└── packages/
    ├── xc_platform/                  # 内核：Atom(Observable) / Obs(Observer) / Action / Component / 路由 / Module
    └── xc_ui/                        # UI 组件：Loading/Empty/Error 骨架、KeepAlive、XcBottomTabBar、XcTheme
```

## 安装

```bash
cd ~/Desktop/code/xc_framework
./install.sh          # dart pub global activate --source path . + 把 pub-cache/bin 写进 shell 配置
```

重开终端后，在**任意 App 工程目录**（有 `pubspec.yaml` + `lib/main.dart`）就能用 `xc`。

也可以手动装：`dart pub global activate --source path ~/Desktop/code/xc_framework`，再把 `$HOME/.pub-cache/bin` 加进 `PATH`。

## 命令

| 命令 | 作用 |
| --- | --- |
| `xc` | 干净重建：clean → deps → gen → assets → check |
| `xc run [flutter 参数]` | 重建后启动；缺平台工程时按 `-d` 自动补齐（`-d chrome` 补 web，默认 android+ios），临时目录生成、不覆盖 `lib/` |
| `xc gen` | 扫描 `packages/*` 下的 `*_page_com.dart`，产出 part 文件与各包 `lib/gen/generated_routes.g.dart` |
| `xc assets` | 按包刷新 `lib/gen/assets_gen.dart` 常量（业务包自动带 `packages/<包名>/` 前缀） |
| `xc pin` | 依赖版本守卫：`pubspec.yaml` / `Gemfile` / `Podfile` 必须写精确版本，`^` `~>` `>=` 直接报错 |
| `xc check` | 先跑 `pin`，再每个包 `flutter analyze` + 有测试的包 `flutter test` |
| `xc --fresh` | clean 时连 `pubspec.lock` 一起删 |
| `xc -n` / `-v` / `--upgrade` / `--dir <path>` | dry-run / 完整输出 / pub upgrade / 指定工程目录 |

工程根是从当前目录向上找「有 `pubspec.yaml` + `lib/main.dart`」的目录，所以 `packages/xxx` 里执行也不会认错。

## 响应式内核：mobx

`xc_platform` 不再自己实现依赖收集，`Atom` 是 mobx `Observable` 的薄封装：

| 框架 API | 实际实现 |
| --- | --- |
| `Atom<T>` | `mobx.Observable<T>`（组合，判等用 `identical`） |
| `Obs(builder:)` | `flutter_mobx` 的 `Observer` |
| `computed(() => ...)` | `mobx.Computed<T>` |
| `atom<T>()` / `WModel.autoDispose` | 创建 / 释放入口，业务无感 |

两个关键处理：

1. **setter 内部包 `runInAction`**：mobx 默认不允许在 action 外写 observable，包一层后业务仍然直接写 `userName = 'xxx';`。
2. **释放门**：`Atom.dispose()` 后 setter 直接返回，避免已释放的 Model 还能把界面改活（mobx 的 Observable 没有显式销毁入口）。

业务代码不出现任何 mobx API：Model 里只写 `var userName = '未登录';`，Atom 和读写器都由生成器产出。

### 版本锁死

规则只有一条：**依赖声明必须唯一确定一个版本**。写在 pubspec / Gemfile / Podfile 里的那一刻就固定，不靠 lock 文件兜底。

```yaml
# xc_platform/pubspec.yaml
mobx: 2.7.0
flutter_mobx: 2.4.0
provider: 6.1.5+1     # flutter_mobx 的转发依赖，一并锁住
```

```ruby
# xc_app/Gemfile（iOS 构建工具链）
ruby "3.4.5"
gem "cocoapods", "1.16.2"
gem "cocoapods-core", "1.16.2"
gem "xcodeproj", "1.28.1"
```

为什么不靠 lock：`pubspec.lock` / `Gemfile.lock` 只是**某一次解析结果的快照**，`xc --fresh` 会删掉它，删掉后重新解析走的是 pubspec 里的区间约束——写 `^2.5.0` 就可能悄悄上到 2.7.x。区别在于：

| 写法 | 换机器 / 删 lock 后 |
| --- | --- |
| `mobx: ^2.5.0` | 解析到当时最新的 2.x，行为可能变 |
| `mobx: 2.7.0` | 只能是 2.7.0，装不上就明确报错 |

例外只有下面几类，它们本来就不该有版本号：`sdk: flutter`（版本由 Flutter SDK 决定）、`path:` / `git:` 本地源码依赖（版本由那个仓库决定），以及 `environment: sdk: ^3.13.0` 这类**环境约束**（钉死 SDK 会让工程在别的 Dart 版本上直接不可用）。

守卫由 `xc pin` 执行，`xc check` 的第一步就是它——扫 App 根、`packages/*`、以及 path 依赖到的框架包，发现 `^` / `~>` / `>=` / `any` / 干脆不写版本就报错并中止：

```
! Gemfile:11  xcodeproj  ~> 1.28 范围约束，应改成精确版本
! xc_framework/packages/xc_platform/pubspec.yaml:19  provider  ^6.1.5 范围约束，应改成精确版本
✘ 2 处依赖没固定版本：去掉 ^ / ~> / >= / any，写成 1.2.3 这样的精确版本
```

升级流程因此变成人工动作：改 pubspec / Gemfile 里的版本号 → `xc` → 30 例测试全绿 → 提交（`pubspec.lock` 与 `Gemfile.lock` 一起提交，它们记录传递依赖的实际落点）。

## 与 App 的关系

```
xc_framework/packages/xc_platform  ←path/git←  xc_app（及它的业务包）
xc_framework/packages/xc_ui        ←path/git←
```

框架不认识 App，也不依赖业务包。升级框架只需改这里的版本，App 侧 `xc --upgrade` 重新解析。
