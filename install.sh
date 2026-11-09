#!/usr/bin/env bash
# 安装 xc 命令：把本仓库激活为全局 Dart 包（executables: xc）。
#
# 用法：
#   ./install.sh            激活并把 $HOME/.pub-cache/bin 写进 shell 配置（已存在则跳过）
#   ./install.sh --print    只打印需要加进 PATH 的那一行，不改任何文件
set -euo pipefail
cd "$(dirname "$0")"

find_dart() {
  local c
  for c in \
    "$(command -v dart 2>/dev/null || true)" \
    "${FLUTTER_ROOT:+$FLUTTER_ROOT/bin/dart}" \
    "${HOME:-}/development/flutter/bin/dart" \
    "${HOME:-}/flutter/bin/dart" \
    /opt/homebrew/bin/dart \
    /usr/local/bin/dart
  do
    if [ -n "${c:-}" ] && [ -x "$c" ]; then
      printf '%s' "$c"
      return 0
    fi
  done
  return 1
}

if ! DART="$(find_dart)"; then
  echo "找不到 dart：先安装 Flutter SDK，或把它加进 PATH" >&2
  exit 127
fi

echo "→ 使用 dart: $DART"
"$DART" pub global activate --source path . | tail -3

PUB_BIN="$HOME/.pub-cache/bin"
LINE="export PATH=\"\$PATH\":\"$PUB_BIN\""

if [ "${1:-}" = "--print" ]; then
  echo "$LINE"
  exit 0
fi

case ":${PATH}:" in
  *":$PUB_BIN:"*)
    echo "✔ $PUB_BIN 已在 PATH 中，直接运行 xc 即可"
    exit 0
    ;;
esac

SHELL_RC="$HOME/.zshrc"
[ -n "${BASH_VERSION:-}" ] && [ -f "$HOME/.bashrc" ] && SHELL_RC="$HOME/.bashrc"

if grep -qs "pub-cache/bin" "$SHELL_RC"; then
  echo "✔ $SHELL_RC 里已有 pub-cache/bin"
else
  printf '\n# Dart pub global executables (xc)\n%s\n' "$LINE" >> "$SHELL_RC"
  echo "✔ 已把 pub-cache/bin 写进 $SHELL_RC"
fi

echo
echo "重开终端（或 source $SHELL_RC）后，在任意 App 工程目录执行："
echo "  xc          # 干净重建 + 检查"
echo "  xc run      # 启动 App"
