import 'package:flutter/material.dart';

/// 页面注解：`@GRoute('login-page')`，路由名唯一标识一个页面。
class GRoute {
  const GRoute(this.name);

  final String name;
}

/// 路由构造器：收到本次跳转的参数，返回页面 Widget。
typedef ComponentBuilder = Widget Function(RouteArgs args);

/// 一次跳转携带的全部入参：query（Map）+ extra（任意对象）。
///
/// - [query]：查询参数的 Map，push 时显式传入，也可写成 `'login-page?from=home'`；
/// - extra：任意类型的附加值，不进 URL，适合传已加载好的实体、回调等不可序列化的东西。
///
/// query 键值先天弱类型，用 `[]` / [value] / [text] 直接读，取不到或类型不符给 null；
/// extra 的类型在编译期未知，**只能经 [extraAs] 显式声明类型**，由框架做一次强校验。
/// 框架不做任何「猜类型」的隐式转换，也不会把 extra 当成 Map 混进 query 里查。
@immutable
class RouteArgs {
  const RouteArgs({
    this.query = const <String, Object?>{},
    Object? extra,
  }) : _extra = extra;

  /// 无参跳转。
  static const RouteArgs empty = RouteArgs();

  final Map<String, Object?> query;

  /// 任意类型的附加值：类型未知，只能经 [extraAs] 取出。
  final Object? _extra;

  bool get isEmpty => query.isEmpty && _extra == null;

  bool get isNotEmpty => !isEmpty;

  /// 是否带了 extra（可选的 extra 先判这里，再 [extraAs]）。
  bool get hasExtra => _extra != null;

  /// 查 query：`route['from']`。
  Object? operator [](String key) => query[key];

  bool has(String key) => query[key] != null;

  /// 带类型读取 query 里的值，类型不符返回 null：`route.value<int>('tab')`。
  ///
  /// extra 的类型校验走 [extraAs]。
  T? value<T>(String key) {
    final Object? raw = query[key];
    return raw is T ? raw : null;
  }

  /// 一律转成字符串（UI 展示常用）：`route.text('from')`。
  String? text(String key) {
    final Object? raw = query[key];
    return raw == null ? null : '$raw';
  }

  /// extra 的唯一入口：显式声明类型，框架当场做一次强校验。
  ///
  /// ```dart
  /// final OrderDraft draft = route.extraAs<OrderDraft>();
  /// ```
  ///
  /// 没带 extra、或运行期类型与声明不一致，都抛 [RouteExtraError]——
  /// 这是业务侧漏校验的编程错误，不要 try/catch 兜底；
  /// extra 本身可选时，先用 [hasExtra] 判断。
  T extraAs<T>() {
    final Object? raw = _extra;
    if (raw is T) {
      return raw;
    }
    throw RouteExtraError(expected: T, actual: raw);
  }

  /// 合并：`other` 里的键覆盖当前 query，extra 以 `other` 为准。
  ///
  /// 「路由名里带的查询串」与「push 时显式传入的参数」就是靠它叠加的。
  RouteArgs merge(RouteArgs other) {
    if (other.isEmpty) {
      return this;
    }
    return RouteArgs(
      query: <String, Object?>{...query, ...other.query},
      extra: other._extra ?? _extra,
    );
  }

  /// 解析 `a=1&b=2` 形式的查询串（自动 URL 解码）。
  static Map<String, Object?> parseQuery(String raw) {
    final Map<String, Object?> result = <String, Object?>{};
    for (final String pair in raw.split('&')) {
      if (pair.isEmpty) {
        continue;
      }
      final int split = pair.indexOf('=');
      final String key = Uri.decodeComponent(split < 0 ? pair : pair.substring(0, split));
      final String value = split < 0 ? '' : Uri.decodeComponent(pair.substring(split + 1));
      result[key] = value;
    }
    return result;
  }

  @override
  String toString() => 'RouteArgs(query: $query, extra: $_extra)';
}

/// extra 强校验失败：没携带，或运行期类型与业务侧声明的不一致。
///
/// 说明业务侧没校验就取值，属于编程错误，所以继承 [Error] 而不是 [Exception]。
class RouteExtraError extends Error {
  RouteExtraError({required this.expected, required this.actual});

  /// 业务侧声明的类型。
  final Type expected;

  /// 实际携带的值；null 表示本次跳转没带 extra。
  final Object? actual;

  @override
  String toString() => actual == null
      ? 'RouteExtraError: 本次跳转没有携带 extra，却按 $expected 取用'
      : 'RouteExtraError: extra 实际是 ${actual.runtimeType}，与声明的 $expected 不一致';
}

/// 全局路由表：各业务包在 Module 里声明，主壳启动时统一注册。
///
/// 路由名就是 `@GRoute` 里的常量，精确匹配；参数只走 [RouteArgs] 的 query / extra。
class RouteTable {
  RouteTable._();

  static final Map<String, ComponentBuilder> _routes = <String, ComponentBuilder>{};

  static void register(Map<String, ComponentBuilder> routes) => _routes.addAll(routes);

  /// 构造页面：`name` 可带查询串（`'login-page?from=home'`），`args` 里的同名键优先。
  static Widget? create(String name, {RouteArgs args = RouteArgs.empty}) {
    final int queryStart = name.indexOf('?');
    final ComponentBuilder? builder = _routes[_pathOf(name)];
    if (builder == null) {
      return null;
    }
    final RouteArgs inline = queryStart < 0
        ? RouteArgs.empty
        : RouteArgs(query: RouteArgs.parseQuery(name.substring(queryStart + 1)));
    return builder(inline.merge(args));
  }

  static bool has(String name) => _routes.containsKey(_pathOf(name));

  static int get size => _routes.length;

  static void clear() => _routes.clear();

  /// 路由名里的查询串不参与匹配。
  static String _pathOf(String name) {
    final int queryStart = name.indexOf('?');
    return queryStart < 0 ? name : name.substring(0, queryStart);
  }
}

/// 跨包跳转只认路由名常量，实现包之间互不 import。
class XcRouter {
  XcRouter._();

  /// 打开页面，返回值是 `pop` 时带回来的结果。
  ///
  /// ```dart
  /// await XcRouter.push(context, OrderRoutes.page);                          // 无参
  /// await XcRouter.push(context, OrderRoutes.page, query: {'from': 'home'});  // 查询参数
  /// await XcRouter.push<OrderResult>(context, OrderRoutes.page,
  ///     extra: draft);                                                       // 任意对象
  /// ```
  ///
  /// `extra` 传什么类型都行，页面侧必须用 `route.extraAs<T>()` 声明类型后才能用。
  static Future<T?> push<T>(
    BuildContext context,
    String routeName, {
    Map<String, Object?> query = const <String, Object?>{},
    Object? extra,
  }) {
    final RouteArgs args = RouteArgs(query: query, extra: extra);
    final Widget? page = RouteTable.create(routeName, args: args);
    assert(page != null, 'route not registered: $routeName');
    if (page == null) {
      return Future<T?>.value();
    }
    return Navigator.of(context).push<T>(
      MaterialPageRoute<T>(
        builder: (_) => page,
        // 顺带写进 RouteSettings：埋点、`XcRouter.argsOf(context)` 都能拿到
        settings: RouteSettings(name: routeName, arguments: args),
      ),
    );
  }

  /// 用新页面替换当前页面：启动页 → 主框架这种「进过就不该再回来」的跳转用它。
  ///
  /// ```dart
  /// XcRouter.replace<void>(context, IndexRoutes.page);   // 启动页不留栈
  /// ```
  ///
  /// 语义与 [push] 一致（同样支持 query / extra、同样从路由表构造），
  /// 区别只有一条：新页面顶掉当前页，返回键不会再回到被替换的页面。
  static Future<T?> replace<T>(
    BuildContext context,
    String routeName, {
    Map<String, Object?> query = const <String, Object?>{},
    Object? extra,
  }) {
    final RouteArgs args = RouteArgs(query: query, extra: extra);
    final Widget? page = RouteTable.create(routeName, args: args);
    assert(page != null, 'route not registered: $routeName');
    if (page == null) {
      return Future<T?>.value();
    }
    return Navigator.of(context).pushReplacement<T, Object?>(
      MaterialPageRoute<T>(
        builder: (_) => page,
        settings: RouteSettings(name: routeName, arguments: args),
      ),
    );
  }

  /// 从当前路由取参数（弹窗、中间层等拿不到 Component 的 `route` 时用）。
  static RouteArgs argsOf(BuildContext context) {
    final Object? arguments = ModalRoute.of(context)?.settings.arguments;
    return arguments is RouteArgs ? arguments : RouteArgs.empty;
  }

  static void pop<T>(BuildContext context, [T? result]) => Navigator.of(context).pop<T>(result);
}
