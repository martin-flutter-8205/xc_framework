import 'package:flutter/material.dart';

/// 页面保活：tab 切换不重建，滚动位置由 PageStorage 保留。
class KeepAliveWrapper extends StatefulWidget {
  const KeepAliveWrapper({super.key, required this.child, this.keepAlive = true});

  final Widget child;
  final bool keepAlive;

  @override
  State<KeepAliveWrapper> createState() => _KeepAliveWrapperState();
}

class _KeepAliveWrapperState extends State<KeepAliveWrapper> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => widget.keepAlive;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}
