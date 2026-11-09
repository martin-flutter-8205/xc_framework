import 'package:flutter/foundation.dart';

import 'atom.dart';
import 'page_state.dart';

/// Model：一个页面一个类，装三样东西（概念上分三段，代码上不拆）。
///
/// 1. 状态：字段直接声明在 Model 里（`var userName = '未登录';`），
///    Atom 与 getter / setter 由 xc_codegen 生成的「接管子类」提供；
/// 2. 业务：`@gaction()` 方法，唯一能改状态的地方——**只有它们进生成的 switch**，
///    同时也由生成器产出意图工厂 `XxxModelIntents`（Model 里不写 `static Action`）；
/// 3. 普通方法：不加注解，就是普通函数，内部流转直接调，dispatch 不到。
///
/// 注意：Model 不持有 dispatch。派发能力由 Component 持有的 [ActionBus]
/// 负责，View 是唯一的使用方；Model 内部流转直接调方法即可。
///
/// 生命周期也在这里，规则只有两条：
///
/// - [init] **必须重写**：基类不给默认实现，逼着每个 Model 想清楚首屏要做什么；
/// - [dispose] **不要重写**：释放入口由基类独占（`@nonVirtual`），子类要清理就重写
///   [onDispose]，不用调 `super`，Atom / 登记过的 disposable 一律由 [autoDispose] 兜底。
///
/// ```dart
/// class OrderModel extends WModel {
///   final StreamSubscription<Tick> _sub = ...;
///
///   @override
///   void init() {
///     _sub.listen(onTick);
///     addDisposable(_sub.cancel);   // 想自动释放就登记一下
///     loadOrders();                 // 首屏请求：进来就拉
///   }
///
///   @override
///   void onDispose() {
///     // 只写框架不知道的业务侧清理；不用也不能调 super
///     _sub.pause();
///   }
/// }
/// ```
abstract class WModel {
  final List<Atom<dynamic>> _atoms = <Atom<dynamic>>[];

  /// 需要在 dispose 时自动释放的资源（订阅、Timer、Controller…）。
  final List<VoidCallback> _disposables = <VoidCallback>[];

  bool _initialized = false;
  bool _disposed = false;

  /// 页面四态：**Model 自己的状态**，和字段级 Atom 一样随 Model 释放。
  ///
  /// 懒创建：页面真正读它、或业务方法第一次切态时才建，建好就登记进 [_atoms]，
  /// 由 [autoDispose] 统一收尾——不需要 Component 插手，也不需要谁注入。
  ///
  /// ```dart
  /// pageState.loading();
  /// final res = await Api.load().resume();
  /// pageState.content();
  /// ```
  PageState? _pageState;

  PageState get pageState => _pageState ??= _createPageState();

  PageState _createPageState() {
    assert(!_disposed, 'Model 已释放，不能再创建页面态');
    final PageState created = PageState();
    _atoms.add(created); // 复用 autoDispose 的统一释放
    return _pageState = created;
  }

  /// 初始化指针：只有 [init] 完整跑完才为 `true`；init 抛错或 dispose 后为 `false`。
  ///
  /// 用来确认「这个 Model 是不是已经初始化成功、现在能不能用」，
  /// 比如异步回调里先判一下再动状态。
  bool get initialized => _initialized;

  /// 是否已经释放；释放后的 Model 不再接受初始化，也不该再被读写。
  bool get disposed => _disposed;

  /// 初始化钩子：**子类必须重写**，框架不提供空实现。
  ///
  /// 这里放首屏要做的事：订阅、预置状态、拉起第一个请求。只跑一次，
  /// 由框架在页面挂载时调（见 [ensureInitialized]），不用自己调。
  ///
  /// 写成抽象而不是空实现，是为了不给「这个页面要不要初始化」留模糊地带——
  /// 哪怕什么都不做，也显式写一个空方法（`void init() {}`），一眼能看出是有意为之。
  @protected
  void init();

  /// 释放钩子：子类**可选**重写，只写框架不知道的业务侧清理。
  ///
  /// 不要调 `super.onDispose()`（父类是空实现），也不用管 Atom 和
  /// [addDisposable] 登记过的资源——它们由 [dispose] 里的 [autoDispose] 兜底，
  /// 就算这里抛异常也照样跑完（见 [dispose] 的 `finally`）。
  @protected
  void onDispose() {}

  /// 框架调用：保证 [init] 只跑一次，并维护初始化指针。
  ///
  /// - 已初始化 → 直接返回 `true`，不重复跑；
  /// - 已释放 → 返回 `false`，释放后的 Model 不再初始化；
  /// - [init] 抛错 → 异常继续上抛，指针保持 `false`，可以修好后重试。
  bool ensureInitialized() {
    if (_disposed) {
      return false;
    }
    if (_initialized) {
      return true;
    }
    init();
    _initialized = true;
    return true;
  }

  /// 声明字段级 Atom（生成的接管子类据此把字段变成可观察的）。
  Atom<T> atom<T>(T initial) {
    assert(!_disposed, 'Model 已释放，不能再创建 Atom');
    final Atom<T> created = Atom<T>(initial);
    _atoms.add(created);
    return created;
  }

  /// 登记一个「随 Model 一起释放」的资源，[autoDispose] 时自动调用。
  ///
  /// 已经释放过了就直接执行，避免晚到的资源漏掉。
  @protected
  void addDisposable(VoidCallback dispose) {
    if (_disposed) {
      dispose();
      return;
    }
    _disposables.add(dispose);
  }

  /// 释放入口：**框架调用，子类不要重写**（`@nonVirtual`，重写了分析器会报）。
  ///
  /// 释放顺序：子类的 [onDispose] → [autoDispose]（Atom + 登记过的 disposable）。
  /// [onDispose] 用 `try/finally` 包着，它抛异常也不会让 Atom 的订阅漏掉——
  /// 这就是「不管子类写没写清理，父类都兜底」的落点；同时保证幂等，
  /// 重复 dispose 不会把资源释放两次。
  @nonVirtual
  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _initialized = false; // 指针复位：这个 Model 已经不可用
    try {
      onDispose();
    } finally {
      autoDispose();
    }
  }

  /// 自动释放：Atom 与登记过的 disposable 统一收尾。
  ///
  /// 内部实现，子类**不要重写**；要写清理就重写 [onDispose]。
  /// 单个 disposable 抛错也不会挡住后续收尾（`try/finally` 里清空并释放 Atom）。
  @protected
  @nonVirtual
  void autoDispose() {
    try {
      for (final VoidCallback disposable in _disposables) {
        disposable();
      }
    } finally {
      _disposables.clear();
      for (final Atom<dynamic> atom in _atoms) {
        atom.dispose();
      }
      _atoms.clear();
    }
  }
}
