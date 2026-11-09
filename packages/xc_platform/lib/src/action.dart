typedef Dispatcher = void Function(Action action);

/// Action：一次「状态变更意图」的声明式描述。
///
/// `payload` 是**位置参数列表**，顺序与目标 `@gaction` 方法的参数声明顺序一致。
/// 生成的 dispatch 用 `switch` + `payload` 解构做「函数签名强匹配」：
/// 名字或参数个数/类型对不上，直接落到 `default` 抛错，不会静默穿透。
///
/// 例：`LoginModelIntents.submit(phone, code)` -> `Action('LoginModel.onSubmit', [phone, code])`
/// （意图工厂由 xc_codegen 按 `@gaction` 方法签名生成，Model 里不手写）
class Action {
  const Action(this.name, [this.payload = const <Object?>[]]);

  final String name;

  /// 位置参数列表（不是键值对）。
  final List<Object?> payload;

  @override
  String toString() => 'Action($name, $payload)';
}

/// 标注 Model 上可被 dispatch 命中的业务方法（纯标记，无运行时行为）。
///
/// 规则很简单：
/// - **业务方法**（View 要 dispatch 到的）必须标注，否则不会进生成的 switch；
/// - **普通方法**（内部辅助、只在本类里调）就是普通函数，不加注解；
/// 意图工厂由生成器产出（`XxxModelIntents`），Model 里手写 `static Action` 会报 `[ERROR]`。
///
/// 注解是类，必须写 `@gaction()`（不带括号 CFE 会报「不是常量」）。
class gaction {
  const gaction();
}

/// 标注 Model 里的一个状态字段：生成器跳过它，不生成 Atom 接管代码。
///
/// 字段保持声明原样（`late final` 只读），适合放不参与响应式的常量型展示值：
/// ```dart
/// @gignore
/// late final appTitle = 'xc 架构复刻';
/// ```
class Gignore {
  const Gignore();
}

/// 以常量形式提供注解实例，这样 `@gignore` 不带括号也能用。
const Gignore gignore = Gignore();
