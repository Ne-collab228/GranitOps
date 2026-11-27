#!/bin/sh
# Проверка, что все скрипты компилируются (до запуска окна теста — иначе окно висит на загрузке).
# Linux: godot из PATH или $GODOT. Windows (sh из MSYS): прежний путь.
# Код возврата: 0 — ок, 1 — ошибки в скриптах, 2 — нет Godot.
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if [ -n "$GODOT" ]; then
  G="$GODOT"
elif command -v godot >/dev/null 2>&1; then
  G="godot"
elif [ -x "C:/Users/user/Tools/godot/bin/Godot_v4.7.2-stable_win64_console.exe" ]; then
  G="C:/Users/user/Tools/godot/bin/Godot_v4.7.2-stable_win64_console.exe"
else
  echo "Godot не найден: задайте GODOT или положите godot в PATH"; exit 2
fi
LOG="$(mktemp)"
PAT="SCRIPT ERROR|Parse Error|Failed to load script|Failed to compile|Compile Error|Failed to instantiate|Could not parse global class"
# импорт нужен для регистрации новых классов и ресурсов; ошибки скриптов смотрим и здесь, и после запуска
timeout 300 "$G" --headless --path "$ROOT" --import >"$LOG" 2>&1
timeout 120 "$G" --headless --path "$ROOT" --quit-after 60 >>"$LOG" 2>&1
OUT=$(grep -E "$PAT" -A1 "$LOG" | head -30)
rm -f "$LOG"
if [ -n "$OUT" ]; then
  echo "$OUT"; echo "ОШИБКИ в скриптах"; exit 1
fi
echo "scripts ok"
