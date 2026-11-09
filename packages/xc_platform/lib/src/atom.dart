import 'package:mobx/mobx.dart' as mobx;

/// 字段级响应式原子：**内核是 mobx 的 `Observable`**，这里只是一层薄封装。
///
/// 业务代码不直接碰它：Model 里只写 `var userName = '未登录';`，
/// 生成器在 `.g.dart` 里建 `late final Atom<String> _userName = atom<String>('未登录')`，
/// 再用 getter / setter 覆盖字段（虚分发）。所以业务侧看不到任何 mobx API。
///
/// 用组合而不是继承，原因：mobx 的 `Observable` 是 factory 构造，无法 `super(...)`。
/// 包一层不影响依赖收集——读 `value` 时在 `Obs` 的构建上下文里，mobx 照样把
/// 当前 Reaction 记成依赖。
///
/// 判等用 `identical`（与换内核前的行为一致）：值没变就不通知，避免无意义重建。
class Atom<T> {
  Atom(T initial)
    : _observable = mobx.Observable<T>(
        initial,
        equals: (T? a, T? b) => identical(a, b),
      );

  final mobx.Observable<T> _observable;

  bool _disposed = false;

  T get value => _observable.value;

  set value(T next) {
    // Model 释放后写值直接忽略：UI 已经卸载，再通知没有意义，
    // 也避免「已释放的 Model 还能把界面改活」。
    if (_disposed) return;
    // mobx 默认写策略要求在 action 里改 observable；在这里包一层 runInAction，
    // 业务侧就还是 `userName = 'xxx';` 这种直白写法，不用关心 mobx 的约束。
    mobx.runInAction<void>(() {
      _observable.value = next;
    });
  }

  /// mobx 的 `Observable` 没有显式释放入口（依赖在 Obs 卸载时自动解除，
  /// 对象失去引用即被回收）。这里做两件事：
  /// 1. 关掉写入口，复刻「释放后不再通知」的语义；
  /// 2. 让 `WModel.autoDispose` 的统一收尾不用为内核差异分支。
  void dispose() => _disposed = true;

  /// 是否已随 Model 释放。
  bool get disposed => _disposed;

  @override
  String toString() => 'Atom<$T>($value)';
}

/// 派生状态：依赖的 Atom 变了才重算，读 `.value` 拿结果。
///
/// ```dart
/// late final fullName = computed(() => '${first.value} ${last.value}');
/// ```
///
/// 生成器暂时不认 `computed` 字段（它只接管 `var` 声明的状态），
/// 需要用的时候在 Model 里手写一行即可，读它同样会订阅。
mobx.Computed<T> computed<T>(T Function() compute) => mobx.Computed<T>(compute);
