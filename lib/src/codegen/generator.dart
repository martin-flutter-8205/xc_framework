import 'dart:io';

/// 极简代码生成器（无第三方依赖，按约定扫描源码）。
///
/// 每个页面一个 `xxx_page_com.dart`：`XxxModel`（状态 + 业务）+ `XxxView` +
/// `XxxComponent`，生成器产出 **part 文件** `xxx_page_com.g.dart`：
///
/// 1. 状态接管子类 `_$XxxModelImpl extends XxxModel`：把 Model 里声明的字段
///    （`var userName = '未登录';`）用「Atom + getter / setter」接管（虚分发）；
///    标了 `@gignore` 的字段不生成，声明即实现、天然只读；
/// 2. 工厂 `createXxxModel()`：Component 的 `createModel()` 返回它才有响应式；
/// 3. 意图工厂 `XxxModelIntents`：按 `@gaction` 方法签名生成 `static Action`，
///    View 只从这里拿 Action（Model 里不写 `static Action`，写了报 `[ERROR]`）；
/// 4. `createXxxModelDispatcher(model)`：**switch 强匹配**——
///    `case Action(name: 'Xxx.onYyy', payload: [final String a, ...])` 直接按
///    函数签名解构位置参数，名字/个数/类型对不上落到 default 抛错。
///
/// **只有标 `@gaction` 的方法有意图工厂、也才进 switch**：普通方法就是普通函数
/// （内部流转直接调），不进 switch、View 也 dispatch 不到。
///
/// 另外为整个包产出 `lib/gen/generated_routes.g.dart`（路由名 → `(RouteArgs) => Component`）。
class Generator {
  Generator({required this.root});

  final String root;

  List<String> run() {
    final List<String> logs = <String>[];
    for (final Directory packageDir in _businessPackages()) {
      final String packageName = _baseName(packageDir.path);
      final Directory routeDir = Directory('${packageDir.path}/lib/src/route');
      final List<File> pageFiles = _pageFiles(routeDir);
      if (pageFiles.isEmpty) {
        continue;
      }
      // 路由名常量（如 LoginRoutes.page）可能放在单独的 routes 文件里，需扫全目录
      final Map<String, String> constants = _routeConstants(
        _dartFiles(routeDir),
      );
      final List<_Page> pages = <_Page>[];
      int partCount = 0;

      for (final File file in pageFiles) {
        final String source = file.readAsStringSync();
        final _Page? page = _parsePage(
          source,
          file.path,
          constants,
          packageDir.path,
        );
        if (page != null) {
          pages.add(page);
        }
        final _PageModel? model = _parsePageModel(source, file.path, logs);
        if (model != null) {
          _writePart(file, model);
          partCount++;
          final String partDirective =
              "part '${_baseName(file.path).replaceAll('.dart', '.g.dart')}';";
          if (!source.contains(partDirective)) {
            logs.add(
              '[WARN] ${_baseName(file.path)} 缺少 $partDirective，生成产物不会参与编译',
            );
          }
        }
      }

      final Directory outputDir = Directory('${packageDir.path}/lib/gen')
        ..createSync(recursive: true);
      _writeRoutes(outputDir, packageName, pages);
      logs.add(
        '[$packageName] ${pages.length} routes, $partCount part files -> lib/gen/generated_routes.g.dart',
      );
    }
    if (logs.isEmpty) {
      logs.add('no *_page_com.dart found under $root/packages');
    }
    return logs;
  }

  // ---------------- 扫描 ----------------

  Iterable<Directory> _businessPackages() {
    final Directory packagesDir = Directory('$root/packages');
    if (!packagesDir.existsSync()) {
      return <Directory>[];
    }
    final List<Directory> dirs =
        packagesDir.listSync().whereType<Directory>().toList()
          ..sort((Directory a, Directory b) => a.path.compareTo(b.path));
    return dirs.where(
      (Directory dir) => Directory('${dir.path}/lib/src/route').existsSync(),
    );
  }

  List<File> _dartFiles(Directory dir) {
    final List<File> files =
        dir
            .listSync(recursive: true)
            .whereType<File>()
            .where(
              (File file) =>
                  file.path.endsWith('.dart') && !file.path.endsWith('.g.dart'),
            )
            .toList()
          ..sort((File a, File b) => a.path.compareTo(b.path));
    return files;
  }

  /// 页面文件约定：`xxx_page_com.dart`。
  List<File> _pageFiles(Directory dir) {
    if (!dir.existsSync()) {
      return <File>[];
    }
    final List<File> files =
        dir
            .listSync(recursive: true)
            .whereType<File>()
            .where((File file) => file.path.endsWith('_page_com.dart'))
            .toList()
          ..sort((File a, File b) => a.path.compareTo(b.path));
    return files;
  }

  /// 收集 `class XxxRoutes { static const String page = 'login-page'; }` 常量，
  /// 让 `@GRoute(LoginRoutes.page)` 也能解析成真实路由名。
  Map<String, String> _routeConstants(List<File> files) {
    final Map<String, String> constants = <String, String>{};
    final RegExp classReg = RegExp(r'^class\s+(\w+)', multiLine: true);
    final RegExp constReg = RegExp(
      r"static\s+const\s+String\s+(\w+)\s*=\s*'([^']*)'",
    );
    for (final File file in files) {
      String currentClass = '';
      for (final String line in file.readAsLinesSync()) {
        final Match? classMatch = classReg.firstMatch(line.trim());
        if (classMatch != null) {
          currentClass = classMatch.group(1)!;
        }
        final Match? constMatch = constReg.firstMatch(line);
        if (constMatch != null && currentClass.isNotEmpty) {
          constants['$currentClass.${constMatch.group(1)}'] = constMatch.group(
            2,
          )!;
        }
      }
    }
    return constants;
  }

  _Page? _parsePage(
    String source,
    String filePath,
    Map<String, String> constants,
    String packageDir,
  ) {
    final RegExp annotation = RegExp(
      r"@GRoute\(\s*(?:'([^']+)'|([A-Za-z_][\w.]*))\s*\)",
    );
    final Match? match = annotation.firstMatch(source);
    if (match == null) {
      return null;
    }
    final String? routeName = match.group(1) ?? constants[match.group(2)];
    if (routeName == null) {
      return null;
    }
    final Match? classMatch = RegExp(r'class\s+(\w+)\s+extends\s+Component<')
        .firstMatch(source.substring(match.end));
    if (classMatch == null) {
      return null;
    }
    final String importPath = filePath.substring('${packageDir}/lib/'.length);
    return _Page(
      name: routeName,
      className: classMatch.group(1)!,
      importPath: importPath,
    );
  }

  /// 取 `class Xxx { ... }` 的类体（按花括号配平）。
  String? _classBody(String source, String className) {
    final Match? match = RegExp('class\\s+$className\\b[^{]*\\{')
        .firstMatch(source);
    if (match == null) {
      return null;
    }
    int depth = 0;
    for (int i = match.end - 1; i < source.length; i++) {
      final String ch = source[i];
      if (ch == '{') {
        depth++;
      } else if (ch == '}') {
        depth--;
        if (depth == 0) {
          return source.substring(match.end, i);
        }
      }
    }
    return null;
  }

  /// 状态字段解析：只看 Model 类体里「顶层」的声明行（方法体内部一律跳过）。
  ///
  /// - `var userName = '未登录';`   -> String，初值 '未登录'
  /// - `String? error;`             -> String?，初值 null
  /// - `late final appTitle = 'x';` + `@gignore` -> 跳过，声明即实现、只读
  List<_StateField> _parseStateFields(
    String body,
    String filePath,
    List<String> logs,
  ) {
    final List<_StateField> fields = <_StateField>[];
    bool pendingIgnore = false;
    int depth = 0;
    for (final String rawLine in body.split('\n')) {
      String line = rawLine.trim();
      final bool topLevel = depth == 0;
      int delta = 0;
      for (final int rune in line.runes) {
        final String ch = String.fromCharCode(rune);
        if (ch == '{') {
          delta++;
        } else if (ch == '}') {
          delta--;
        }
      }

      if (topLevel &&
          line.isNotEmpty &&
          !line.startsWith('//') &&
          !line.startsWith('/*')) {
        bool ignore = false;
        final Match? annotation = RegExp(r'^@(\w+)(?:\([^)]*\))?\s*(.*)$')
            .firstMatch(line);
        if (annotation != null) {
          if (annotation.group(1) == 'gignore') {
            ignore = true;
          }
          final String rest = annotation.group(2)!.trim();
          if (rest.isEmpty) {
            // 注解单独一行，作用于下一行字段
            pendingIgnore = ignore;
            depth += delta;
            continue;
          }
          line = rest;
        }
        if (!ignore) {
          ignore = pendingIgnore;
        }
        if (annotation != null || pendingIgnore) {
          pendingIgnore = false;
        }

        final _StateField? field = _parseFieldLine(line);
        if (field != null && !ignore) {
          if (field.type == null) {
            logs.add(
              '[WARN] ${_baseName(filePath)}: 状态字段 ${field.name} 无法推断类型，'
              '请写显式类型（如 String userName）或用可推断的字面量默认值，已跳过接管',
            );
          } else {
            if (field.isFinal) {
              logs.add(
                '[WARN] ${_baseName(filePath)}: 状态字段 ${field.name} 声明为 final，'
                'Model 业务方法里将无法赋值（编译期报错）',
              );
            }
            fields.add(field);
          }
        }
      }
      depth += delta;
    }
    return fields;
  }

  /// 单行字段声明解析。返回 null 表示这不是状态声明（方法、赋值、注解等）。
  ///
  /// 解析方式：去掉 `;` -> 在顶层 `=` 处切开（跳过 == / => / 字符串）-> 左侧去修饰词，
  /// 最后一个 token 是字段名，前面的是类型（可能含泛型里的空格）。
  _StateField? _parseFieldLine(String line) {
    String text = line.trim();
    if (!text.endsWith(';') || text.contains('(') || text.contains(')')) {
      return null;
    }
    text = text.substring(0, text.length - 1).trim();

    int eq = -1;
    int depth = 0;
    String? quote;
    for (int i = 0; i < text.length; i++) {
      final String ch = text[i];
      if (quote != null) {
        if (ch == quote) {
          quote = null;
        }
        continue;
      }
      if (ch == "'" || ch == '"') {
        quote = ch;
        continue;
      }
      if ('<([{'.contains(ch)) {
        depth++;
      } else if ('>)]}'.contains(ch)) {
        depth--;
      } else if (ch == '=' && depth == 0) {
        final String prev = i > 0 ? text[i - 1] : '';
        final String next = i + 1 < text.length ? text[i + 1] : '';
        if (prev == '=' || prev == '!' || next == '=' || next == '>') {
          continue;
        }
        eq = i;
        break;
      }
    }
    final String left = (eq == -1 ? text : text.substring(0, eq)).trim();
    final String? init = eq == -1 ? null : text.substring(eq + 1).trim();
    if (left.isEmpty) {
      return null;
    }

    final List<String> tokens = left
        .split(RegExp(r'\s+'))
        .where((String t) => t.isNotEmpty)
        .toList();
    const Set<String> modifiers = <String>{
      'late',
      'final',
      'var',
      'const',
      'static',
      'covariant',
      'external',
    };
    bool isFinal = false;
    int start = 0;
    while (start < tokens.length && modifiers.contains(tokens[start])) {
      if (tokens[start] == 'final') {
        isFinal = true;
      }
      if (tokens[start] == 'const' ||
          tokens[start] == 'static' ||
          tokens[start] == 'external') {
        return null; // 这些不是实例状态字段
      }
      start++;
    }
    if (start >= tokens.length) {
      return null;
    }
    final String name = tokens.last;
    if (!RegExp(r'^[A-Za-z_]\w*$').hasMatch(name)) {
      return null;
    }
    final String? declaredType = tokens.length - 1 > start
        ? tokens.sublist(start, tokens.length - 1).join(' ')
        : null;
    final String? type =
        declaredType ?? (init == null ? null : _inferType(init));
    return _StateField(name: name, type: type, init: init, isFinal: isFinal);
  }

  /// 从字面量初值推断类型；推不出来返回 null（外层会 WARN 并跳过）。
  String? _inferType(String expr) {
    final String e = expr.trim();
    if (e.startsWith("'") || e.startsWith('"')) {
      return 'String';
    }
    if (e == 'true' || e == 'false') {
      return 'bool';
    }
    if (RegExp(r'^-?\d+$').hasMatch(e)) {
      return 'int';
    }
    if (RegExp(r'^-?\d+\.\d+$').hasMatch(e)) {
      return 'double';
    }
    return null;
  }

  /// 只认 `@gaction()` 标注的方法（注解是类，必须带空参数列表）。
  ///
  /// 没标注的方法一律视为普通函数：不解析、不进 switch、dispatch 不到。
  List<_Method> _parseActions(String body) {
    final RegExp methodReg = RegExp(
      r'@gaction(?:\s*\(\s*\))?\s*(?:@[\w.]+(?:\([^)]*\))?\s*)*'
      r'(?:Future<void>|void|[\w<>?]+)\s+(\w+)\(([^)]*)\)',
    );
    return <_Method>[
      for (final Match match in methodReg.allMatches(body))
        _Method(name: match.group(1)!, params: _parseParams(match.group(2)!)),
    ];
  }

  _PageModel? _parsePageModel(
    String source,
    String filePath,
    List<String> logs,
  ) {
    final Match? modelMatch = RegExp(r'class\s+(\w+)\s+extends\s+WModel')
        .firstMatch(source);
    if (modelMatch == null) {
      return null;
    }
    final String modelClass = modelMatch.group(1)!;
    final String? body = _classBody(source, modelClass);
    final List<_StateField> fields = body == null
        ? <_StateField>[]
        : _parseStateFields(body, filePath, logs);
    final List<_Method> methods = body == null
        ? <_Method>[]
        : _parseActions(body);
    // 意图工厂由生成器统一产出（XxxModelIntents），Model 里再手写一份就等于两份真相
    if (body != null && RegExp(r'static\s+Action\s+\w+\s*\(').hasMatch(body)) {
      logs.add(
        '[ERROR] ${_baseName(filePath)}: $modelClass 里不要手写 static Action 意图——'
        '意图工厂已由生成器按 @gaction 方法签名产出（${modelClass}Intents）',
      );
    }
    if (fields.isEmpty && methods.isEmpty) {
      return null;
    }
    return _PageModel(
      modelClass: modelClass,
      dispatcherName: 'create${modelClass}Dispatcher',
      intentClass: '${modelClass}Intents',
      fields: fields,
      methods: methods,
    );
  }

  List<_Param> _parseParams(String raw) {
    String body = raw.trim();
    bool named = false;
    bool optionalPositional = false;
    if (body.startsWith('{') && body.endsWith('}')) {
      named = true;
      body = body.substring(1, body.length - 1);
    } else if (body.startsWith('[') && body.endsWith(']')) {
      optionalPositional = true;
      body = body.substring(1, body.length - 1);
    }
    if (body.trim().isEmpty) {
      return <_Param>[];
    }
    final List<String> parts = _splitTopLevel(body);
    final List<_Param> params = <_Param>[];
    for (final String part in parts) {
      String text = part.trim();
      if (text.isEmpty) {
        continue;
      }
      // 去默认值：`int page = 1`
      final int eq = text.indexOf('=');
      if (eq != -1) {
        text = text.substring(0, eq).trim();
      }
      text = text.replaceFirst(RegExp(r'^required\s+'), '');
      final List<String> tokens = text
          .split(RegExp(r'\s+'))
          .where((String t) => t.isNotEmpty)
          .toList();
      if (tokens.length < 2) {
        continue;
      }
      final String name = tokens.last;
      final String type = tokens.sublist(0, tokens.length - 1).join(' ');
      params.add(
        _Param(name: name, type: type, named: named || optionalPositional),
      );
    }
    return params;
  }

  /// 按顶层逗号切分（跳过泛型、括号、字符串里的逗号）。
  List<String> _splitTopLevel(String body) {
    final List<String> parts = <String>[];
    final StringBuffer buffer = StringBuffer();
    int depth = 0;
    String? quote;
    for (final int rune in body.runes) {
      final String ch = String.fromCharCode(rune);
      if (quote != null) {
        buffer.write(ch);
        if (ch == quote) {
          quote = null;
        }
        continue;
      }
      if (ch == "'" || ch == '"') {
        quote = ch;
        buffer.write(ch);
        continue;
      }
      if ('<([{'.contains(ch)) {
        depth++;
      } else if ('>)]}'.contains(ch)) {
        depth--;
      }
      if (ch == ',' && depth == 0) {
        parts.add(buffer.toString());
        buffer.clear();
      } else {
        buffer.write(ch);
      }
    }
    if (buffer.isNotEmpty) {
      parts.add(buffer.toString());
    }
    return parts;
  }

  // ---------------- 输出 ----------------

  /// 与页面文件同目录、同名的 part 产物：`home_page_com.dart` -> `home_page_com.g.dart`
  void _writePart(File pageFile, _PageModel model) {
    final String fileName = _baseName(pageFile.path);
    final String modelClass = model.modelClass;
    final StringBuffer out = StringBuffer()
      ..writeln('// GENERATED CODE - DO NOT MODIFY BY HAND')
      ..writeln('// 由 xc_codegen 生成：dart run xc_codegen')
      ..writeln("part of '$fileName';");

    if (model.fields.isNotEmpty) {
      out
        ..writeln()
        ..writeln('/// $modelClass 的状态接管实现：Model 里声明的每个状态字段')
        ..writeln('/// 在这里被 Atom 接管（读走 getter 订阅、写走 setter 通知）。')
        ..writeln('/// 标了 @gignore 的字段不生成，保持声明原样、天然只读。')
        ..writeln('class _\$${modelClass}Impl extends $modelClass {');
      for (final _StateField field in model.fields) {
        final String type = field.type!;
        final String init = field.init ?? 'null';
        out.writeln(
          '  late final Atom<$type> _${field.name} = atom<$type>($init);',
        );
      }
      for (final _StateField field in model.fields) {
        final String type = field.type!;
        out
          ..writeln()
          ..writeln('  @override')
          ..writeln('  $type get ${field.name} => _${field.name}.value;')
          ..writeln('  @override')
          ..writeln(
            '  set ${field.name}($type value) => _${field.name}.value = value;',
          );
      }
      out
        ..writeln('}')
        ..writeln()
        ..writeln('/// 供 Component.createModel 使用：返回状态接管实现。')
        ..writeln('$modelClass create$modelClass() => _\$${modelClass}Impl();');
    }

    if (model.methods.isNotEmpty) {
      // 意图工厂：Model 里不写 static Action，View 从这里拿
      out
        ..writeln()
        ..writeln('/// $modelClass 的意图工厂：按 @gaction 方法签名生成，参数顺序 = payload 顺序。')
        ..writeln('///')
        ..writeln(
          '/// View 只从这里拿 Action：`dispatch(${model.intentClass}.submit(...))`；',
        )
        ..writeln('/// Model 里不写 static Action（写了生成器会报 [ERROR]）。')
        ..writeln('abstract final class ${model.intentClass} {');
      for (final _Method method in model.methods) {
        final String params = method.params
            .map((_Param p) => '${p.type} ${p.name}')
            .join(', ');
        final String args = method.params.map((_Param p) => p.name).join(', ');
        out.writeln(
          "  static Action ${_intentName(method.name)}($params) => "
          "Action('$modelClass.${method.name}', <Object?>[$args]);",
        );
      }
      out.writeln('}');

      out
        ..writeln()
        ..writeln(
          '/// $modelClass 的 dispatch：switch 按 Action 名 + payload 列表做签名强匹配。',
        )
        ..writeln('///')
        ..writeln('/// 只有标注 @gaction 的业务方法才生成分支；普通方法不进 switch。')
        ..writeln('/// payload 是位置参数列表，顺序与 @gaction 方法的参数声明顺序一致；')
        ..writeln('/// 名字、个数或类型对不上都会落到 default 抛错，不会静默穿透。')
        ..writeln(
          '/// 由 Component 持有（`Component.dispatcher`），Model 自己拿不到 dispatch。',
        )
        ..writeln(
          'Dispatcher ${model.dispatcherName}($modelClass model) => (Action action) {',
        )
        ..writeln('      switch (action) {');
      for (final _Method method in model.methods) {
        final String pattern = method.params
            .map((_Param p) => 'final ${p.type} ${p.name}')
            .join(', ');
        final String args = method.params
            .map((_Param p) => p.named ? '${p.name}: ${p.name}' : p.name)
            .join(', ');
        out
          ..writeln(
            "        case Action(name: '$modelClass.${method.name}', payload: [$pattern]):",
          )
          ..writeln('          model.${method.name}($args);');
      }
      out
        ..writeln('        default:')
        ..writeln(
          "          throw ArgumentError.value(action.name, 'action', '未注册的 Action');",
        )
        ..writeln('      }')
        ..writeln('    };');
    }

    final String target = pageFile.path.replaceAll(
      RegExp(r'\.dart$'),
      '.g.dart',
    );
    File(target).writeAsStringSync(out.toString());
  }

  void _writeRoutes(
    Directory outputDir,
    String packageName,
    List<_Page> pages,
  ) {
    final StringBuffer out = StringBuffer()
      ..writeln('// GENERATED CODE - DO NOT MODIFY BY HAND')
      ..writeln('// 由 xc_codegen 生成：dart run xc_codegen')
      ..writeln()
      ..writeln("import 'package:xc_platform/xc_platform.dart';")
      ..writeln();
    final List<String> imports =
        pages.map((_Page p) => p.importPath).toSet().toList()..sort();
    for (final String import in imports) {
      out.writeln("import '../$import';");
    }
    out
      ..writeln()
      ..writeln('/// $packageName 的路由表：`Module.routes` 直接引用这里。')
      ..writeln('///')
      ..writeln('/// 每个条目都是一个「参数 -> 页面」的构造器，`route` 由 XcRouter 透传给 Component。')
      ..writeln(
        'final Map<String, ComponentBuilder> routes = <String, ComponentBuilder>{',
      );
    for (final _Page page in pages) {
      out.writeln(
        "  '${page.name}': (RouteArgs route) => ${page.className}(route: route),",
      );
    }
    out.writeln('};');
    File('${outputDir.path}/generated_routes.g.dart')
        .writeAsStringSync(out.toString());
  }

  String _baseName(String path) => path.split(Platform.pathSeparator).last;

  /// 意图名：`onSubmit` -> `submit`，`onPhoneChanged` -> `phoneChanged`；
  /// 不带 `on` 前缀的方法名原样沿用。
  String _intentName(String methodName) {
    final Match? match = RegExp(r'^on([A-Z]\w*)$').firstMatch(methodName);
    if (match == null) {
      return methodName;
    }
    return match.group(1)![0].toLowerCase() + match.group(1)!.substring(1);
  }
}

class _Page {
  _Page({
    required this.name,
    required this.className,
    required this.importPath,
  });

  final String name;
  final String className;
  final String importPath;
}

class _PageModel {
  _PageModel({
    required this.modelClass,
    required this.dispatcherName,
    required this.intentClass,
    required this.fields,
    required this.methods,
  });

  final String modelClass;
  final String dispatcherName;

  /// 意图工厂类名：`LoginModel` -> `LoginModelIntents`（Model 里不再手写）。
  final String intentClass;

  final List<_StateField> fields;
  final List<_Method> methods;
}

/// 一个状态声明：`var userName = '未登录';` -> Atom 接管 + 读写器 `userName`。
class _StateField {
  _StateField({
    required this.name,
    required this.type,
    required this.init,
    required this.isFinal,
  });

  final String name;

  /// 显式类型或从初值推断的类型；null 表示无法推断（调用方 WARN 后跳过）。
  final String? type;

  /// 初值表达式（原样透传给 `atom<T>(...)`）；null 视为 null。
  final String? init;

  final bool isFinal;
}

class _Method {
  _Method({required this.name, required this.params});

  final String name;
  final List<_Param> params;
}

class _Param {
  _Param({required this.name, required this.type, required this.named});

  final String name;
  final String type;

  /// 命名参数（`{required String a}`），调用时用 `a: a`；否则按位置传。
  final bool named;
}
