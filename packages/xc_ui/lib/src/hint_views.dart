import 'package:flutter/material.dart';

/// 空态：请求成功但没有数据，可带一个重试入口。
class EmptyHintView extends StatelessWidget {
  const EmptyHintView({super.key, this.text = '暂无数据', this.onRetry});

  final String text;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(text, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
            if (onRetry != null) TextButton(onPressed: onRetry, child: const Text('重试')),
          ],
        ),
      );
}

/// 错误态：文案一般直接给用户看，配一个重试入口。
class ErrorHintView extends StatelessWidget {
  const ErrorHintView({super.key, required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(message, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            if (onRetry != null) TextButton(onPressed: onRetry, child: const Text('重试')),
          ],
        ),
      );
}

/// 加载态：整页只留一个转圈，内容区不渲染。
class LoadingView extends StatelessWidget {
  const LoadingView({super.key, this.size = 20});

  final double size;

  @override
  Widget build(BuildContext context) => Center(
        child: SizedBox(
          width: size,
          height: size,
          child: const CircularProgressIndicator(strokeWidth: 2),
        ),
      );
}
