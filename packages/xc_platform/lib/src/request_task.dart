/// 声明式网络层：构造 RequestTask 只是「描述请求」，`.resume()` 才真正执行。
///
/// ```dart
/// final json = await LoginApi.submitLogin(phone: p, code: c).resume();
/// ```
class RequestTask<T> {
  RequestTask(this.route, {required this.decode, this.params = const <String, Object?>{}});

  final String route;
  final Map<String, Object?> params;
  final T Function(Map<String, Object?> raw) decode;

  Future<T> resume() async {
    final Map<String, Object?> raw = await XcHttp.instance.send(route, params);
    return decode(raw);
  }
}

/// 网络底层抽象：默认本地 Mock，接后端时 `XcHttp.install(RealClient())` 换掉。
abstract class XcHttpClient {
  Future<Map<String, Object?>> send(String route, Map<String, Object?> params);
}

class XcHttp {
  XcHttp._();

  static XcHttpClient instance = const MockXcHttpClient();

  static void install(XcHttpClient client) => instance = client;
}

/// 本地联调用的假服务端：按 route 返回固定报文，保证 demo 离线可跑。
class MockXcHttpClient implements XcHttpClient {
  const MockXcHttpClient({this.latency = const Duration(milliseconds: 80)});

  final Duration latency;

  @override
  Future<Map<String, Object?>> send(String route, Map<String, Object?> params) async {
    await Future<void>.delayed(latency);
    switch (route) {
      // 启动页：拿 App 名、标语与倒计时秒数（真实后端这里是「启动配置」）
      case r'app$boot':
        return <String, Object?>{
          'code': 0,
          'data': <String, Object?>{
            'appName': '响彻星空',
            'slogan': '让声音抵达星空',
            'countdown': 3,
          },
        };
      default:
        return <String, Object?>{'code': 404, 'message': 'route not mocked: $route'};
    }
  }
}
