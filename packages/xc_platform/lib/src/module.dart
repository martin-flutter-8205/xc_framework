import 'package:flutter/widgets.dart';

import 'route.dart';

/// Module：业务包对外唯一出口，声明路由表、全局 overlay、启动同步任务。
abstract class Module {
  String get name;

  Map<String, ComponentBuilder> get routes;

  Widget? get overlay => null;

  Future<void>? get syncTask => null;
}

class ModuleRegistry {
  ModuleRegistry._();

  static final Map<String, Module> _modules = <String, Module>{};

  static List<Module> get modules => List<Module>.unmodifiable(_modules.values);

  static void install(Module module) {
    assert(!_modules.containsKey(module.name), 'module ${module.name} 重复注册');
    _modules[module.name] = module;
    RouteTable.register(module.routes);
  }

  static Future<void> runSyncTasks() async {
    for (final Module module in _modules.values) {
      final Future<void>? task = module.syncTask;
      if (task != null) {
        await task;
      }
    }
  }

  static List<Widget> get overlays => <Widget>[
        for (final Module module in _modules.values)
          if (module.overlay != null) module.overlay!,
      ];

  static void reset() {
    _modules.clear();
    RouteTable.clear();
  }
}
