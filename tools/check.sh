#!/bin/sh
# Проверка, что все скрипты компилируются (до запуска окна теста — иначе окно висит на загрузке).
G="C:/Users/user/Tools/godot/bin/Godot_v4.7.2-stable_win64_console.exe"
timeout 200 "$G" --headless --path "$(dirname "$0")/.." --import >/dev/null 2>&1
OUT=$(timeout 90 "$G" --headless --path "$(dirname "$0")/.." --quit-after 60 2>&1 | grep -E "SCRIPT ERROR|Parse Error|Failed to load" -A1)
if [ -n "$OUT" ]; then echo "$OUT" | head -20; exit 1; fi
echo "scripts ok"
