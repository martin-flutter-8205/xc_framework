import 'package:flutter/material.dart';

/// 底部 Tab 的一项描述：未选中/选中图标、文案、可选角标。
@immutable
class XcTabItem {
  const XcTabItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    this.badge = 0,
  });

  final IconData icon;
  final IconData activeIcon;
  final String label;

  /// 角标数字，`<= 0` 不显示，超过 99 显示 `99+`。
  final int badge;
}

/// 底部 Tab 栏：纯受控组件——选中项与切换回调都由外部给，自己不存状态。
///
/// 视觉是「深空玻璃底 + 选中发光」：颜色全部取自 Theme，换主题不用改组件。
///
/// ```dart
/// XcBottomTabBar(
///   items: const <XcTabItem>[
///     XcTabItem(icon: Icons.home_outlined, activeIcon: Icons.home_rounded, label: '首页'),
///   ],
///   currentIndex: model.currentIndex,
///   onChanged: (int index) => dispatch(IndexModelIntents.tabChanged(index)),
/// );
/// ```
class XcBottomTabBar extends StatelessWidget {
  const XcBottomTabBar({
    super.key,
    required this.items,
    required this.currentIndex,
    required this.onChanged,
  }) : assert(items.length > 0, 'tab 至少一项');

  final List<XcTabItem> items;
  final int currentIndex;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: 0.96),
        border: Border(
          top: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.25)),
        ),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 64,
          child: Row(
            children: <Widget>[
              for (int i = 0; i < items.length; i++)
                Expanded(
                  child: _TabButton(
                    item: items[i],
                    selected: i == currentIndex,
                    onTap: () => onChanged(i),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TabButton extends StatelessWidget {
  const _TabButton({required this.item, required this.selected, required this.onTap});

  final XcTabItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final Color active = scheme.primary;
    final Color inactive = scheme.onSurfaceVariant;
    final Color tint = selected ? active : inactive;

    return InkResponse(
      onTap: onTap,
      radius: 42,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Stack(
            clipBehavior: Clip.none,
            children: <Widget>[
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOut,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: selected ? active.withValues(alpha: 0.14) : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: selected
                      ? <BoxShadow>[
                          BoxShadow(color: active.withValues(alpha: 0.45), blurRadius: 14, spreadRadius: 1),
                        ]
                      : null,
                ),
                child: Icon(
                  selected ? item.activeIcon : item.icon,
                  size: 22,
                  color: tint,
                ),
              ),
              if (item.badge > 0)
                Positioned(
                  right: 2,
                  top: -3,
                  child: _BadgeView(count: item.badge),
                ),
            ],
          ),
          const SizedBox(height: 2),
          AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 180),
            style: TextStyle(
              fontSize: 11,
              height: 1.1,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              color: tint,
            ),
            child: Text(item.label),
          ),
        ],
      ),
    );
  }
}

class _BadgeView extends StatelessWidget {
  const _BadgeView({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Container(
      constraints: const BoxConstraints(minWidth: 16),
      height: 16,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: scheme.error,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: scheme.surface, width: 1.5),
      ),
      child: Text(
        count > 99 ? '99+' : '$count',
        style: TextStyle(fontSize: 10, height: 1, color: scheme.onError, fontWeight: FontWeight.w600),
      ),
    );
  }
}
