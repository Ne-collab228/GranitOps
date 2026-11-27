#!/bin/sh
# Замер нагрузки по пресетам: sh tools/bench.sh [пресеты...]  (по умолчанию 0 и 2)
G="C:/Users/user/Tools/godot/bin/Godot_v4.7.2-stable_win64_console.exe"
cd "$(dirname "$0")/.."
for p in ${@:-0 2}; do
	echo "== пресет $p"
	timeout 120 "$G" --path . --rendering-method gl_compatibility --resolution 802x360 --position 20,40 -- --bench --preset=$p 2>&1 | grep -E "^BENCH|SCRIPT ERROR"
done
