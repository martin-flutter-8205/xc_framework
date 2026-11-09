/// xc_platform：业务无关的框架层，只做四件事。
///
/// 1. Atom 字段级响应式（内核是 mobx 的 Observable）+ Obs 最小重建
/// 2. Action 派发 + @gaction 处理器
/// 3. Component 三件套基类（Component / View / Model）+ 页面四态
/// 4. Module 装配、路由表、声明式网络层
///
/// 不含任何 UI 组件（加载/空/错误骨架、TabBar 等）：那些在 `xc_ui`。
library;

export 'src/action.dart';
export 'src/atom.dart';
export 'src/component.dart';
export 'src/module.dart';
export 'src/model.dart';
export 'src/obs.dart';
export 'src/page_state.dart';
export 'src/request_task.dart';
export 'src/route.dart';

// mobx 内核里业务/测试用得上的部分（`action` 与框架的 Action 重名，不导出）。
export 'package:mobx/mobx.dart'
    show Computed, ObservableList, ObservableMap, Reaction, ReactionDisposer, autorun, reaction;
