/// xc_ui：业务无关的 UI 组件层。
///
/// 只放「长什么样」，不放「数据怎么来」：
///
/// 1. 页面骨架组件：加载中 / 空 / 错误（四态里除内容态外的三块）
/// 2. [KeepAliveWrapper]：tab 切换不重建
/// 3. [XcBottomTabBar]：底部 tab 栏（纯受控组件，选中项由外部传入）
/// 4. [XcTheme]：深空主题，主壳与业务包共用一套配色
///
/// 组件一律不读 Model、不持有 dispatcher——状态归 Model，装配归 Component，
/// UI 只接收「已算好的值 + 回调」。
library;

export 'src/bottom_tab_bar.dart';
export 'src/hint_views.dart';
export 'src/keep_alive_wrapper.dart';
export 'src/theme.dart';
