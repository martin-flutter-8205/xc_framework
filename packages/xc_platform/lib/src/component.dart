import 'package:flutter/widgets.dart';

import 'action.dart';
import 'model.dart';
import 'route.dart';

/// Component：页面装配体，只做三件事——建 Model、装 dispatch、吐 View。
///
/// 单向数据流：View 只拿 model（只读）+ dispatch（只写）。
/// `dispatch` 由 Component 持有（State 里创建，来自生成的 dispatcher），
/// Model 不持有它——Model 内部流转直接调自己的 @gaction 方法。
///
/// 页面四态不在这里：`WModel.pageState` 是 Model 自己的状态，
/// Component 只负责装配与生命周期，不掺和状态本身。
abstract class Component<M extends WModel> extends StatefulWidget {
  const Component({super.key, this.route = RouteArgs.empty});

  /// 本次跳转带进来的参数（query / extra），只读。
  ///
  /// 子类构造函数写上 `super.route` 即可由路由表注入，
  /// `createModel()` / `buildView()` 里直接用 `route['from']`、`route.extraAs<T>()`。
  final RouteArgs route;

  /// 建议返回生成器提供的 `createXxxModel()`（状态接管实现）。
  M createModel();

  /// 由生成的 dispatcher 提供实现：`createXxxModelDispatcher(model)`。
  ///
  /// 内部是一个 `switch (action)`：按 Action 名 + payload 列表做签名强匹配。
  Dispatcher dispatcher(M model);

  /// 挂载时（Model 的 [WModel.init] 之后）触发一次。
  ///
  /// 首屏数据默认写在 Model.init 里；这里留给「必须经 dispatch 走一次」的初始化，
  /// 比如需要复用 View 同一条 Action 链路的场景。不需要就别写。
  void onInit(M model, Dispatcher dispatch) {}

  /// View 的 build 只做一件事：返回 `Obs`，在 Obs 里按 `model.pageState` 的四态
  /// 多态返回各自的 Scaffold（loading / empty / error / content）。
  Widget buildView(BuildContext context, M model, Dispatcher dispatch);

  @override
  ComponentState<M> createState() => ComponentState<M>();
}

class ComponentState<M extends WModel> extends State<Component<M>> {
  late final M model = widget.createModel();

  /// dispatch 在 Component 手里，只有 View 用得到。
  late final Dispatcher dispatch = widget.dispatcher(model);

  @override
  void initState() {
    super.initState();
    // Model 自己的初始化（子类必写的 init，保证只跑一次，失败会保持 initialized=false）
    model.ensureInitialized();
    widget.onInit(model, dispatch);
  }

  @override
  void dispose() {
    // model.dispose 是基类独占的入口：先跑子类 onDispose，再由 autoDispose 统一收尾
    model.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.buildView(context, model, dispatch);
}
