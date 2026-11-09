import 'atom.dart';

/// 页面四态：加载中 / 空 / 错误 / 内容。
///
/// 四态只描述「这一屏现在长什么样」，不描述业务数据本身——
/// 业务数据仍然放在 Model 的字段里，页面态只负责决定渲染哪一支骨架。
enum PageStatus { loading, empty, error, content }

/// 一次页面态快照：状态 + 该状态要展示的文案（空态提示 / 错误信息）。
///
/// 用不可变值整体替换，保证 View 读到的 status 与 message 永远配套。
class PageSnapshot {
  const PageSnapshot(this.status, [this.message]);

  final PageStatus status;
  final String? message;

  @override
  String toString() => 'PageSnapshot($status, $message)';
}

/// 页面态：`WModel.pageState` 就是它——状态归 Model，生命周期随 Model 一起释放。
///
/// 写入口只有 Model（业务分支里切态），View 只读，Component 完全不参与。
///
/// 它本身就是一个 [Atom]，所以在 `Obs` 构建期读 `status` / `message` / `value`
/// 就会订阅，切态只重建 Obs 包住的那一层（也就是 View.build 返回的那层多态 Scaffold）。
///
/// ```dart
/// // Model 里（WModel 自带的成员）
/// pageState.loading();
/// pageState.content();
/// pageState.empty('暂无订单');
/// pageState.fail('网络异常');
/// ```
class PageState extends Atom<PageSnapshot> {
  PageState({PageStatus initial = PageStatus.content, String? message})
      : super(PageSnapshot(initial, message));

  PageStatus get status => value.status;

  String? get message => value.message;

  /// 加载态：整页只留骨架（LoadingView），内容区不渲染。
  void loading() => _move(PageStatus.loading);

  /// 空态：请求成功但没有数据，可带一句提示文案。
  void empty([String? hint]) => _move(PageStatus.empty, hint);

  /// 错误态：请求失败，文案一般直接给用户看。
  void fail(String message) => _move(PageStatus.error, message);

  /// 内容态：正常渲染业务内容。
  void content() => _move(PageStatus.content);

  void _move(PageStatus next, [String? message]) {
    if (value.status == next && value.message == message) {
      return; // 同态同文案不通知，避免无意义重建
    }
    value = PageSnapshot(next, message);
  }
}
