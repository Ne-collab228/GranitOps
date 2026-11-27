#!/bin/sh
# Запуск Godot с окном в виртуальном X-сервере (Linux-контейнер). Аргументы прокидываются в godot.
# Пример: tools/run_x.sh --path . --resolution 960x540 -- --test --touch --preset=0
# Скриншоты — в ~/.local/share/GranitOps. Переменная GODOT — путь к godot (по умолчанию из PATH).
G="${GODOT:-godot}"
export LIBGL_ALWAYS_SOFTWARE="${LIBGL_ALWAYS_SOFTWARE:-1}"
exec xvfb-run -a -s "-screen 0 1280x720x24" "$G" --rendering-method gl_compatibility "$@"
