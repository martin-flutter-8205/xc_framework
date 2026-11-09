import 'package:flutter/widgets.dart';
import 'package:flutter_mobx/flutter_mobx.dart';

/// Obs：把构建期读到的 `Atom`（mobx Observable）变成重建依赖。
///
/// 只有依赖变化才重建这一小块 UI——这是「最小重建」的落点，也是 View 里
/// 唯一需要包的一层：`build` 直接返回 `Obs(builder: ...)`。
///
/// 内部就是 `flutter_mobx` 的 `Observer`，依赖收集与重建时机交给 mobx：
/// 同一个 tick 内多次写状态，Flutter 会把 `setState` 合并到下一帧，不会多画。
class Obs extends StatelessWidget {
  const Obs({super.key, required this.builder});

  final WidgetBuilder builder;

  @override
  Widget build(BuildContext context) => Observer(builder: builder);
}
