#!/bin/sh
# Подготовка Linux-контейнера (Debian/Ubuntu): всё, что нужно для проверки скриптов и тестов с окном.
# Идемпотентно: повторный запуск ничего не ломает и не переустанавливает готовое.
# Godot, шаблоны экспорта Android, JDK 17 и Android SDK ставит tools/setup_linux.sh (он же вызывает этот скрипт)
# (godot в /usr/local/bin, SDK в /opt/granit-tools) — здесь они только проверяются.
SUDO=""
[ "$(id -u)" = "0" ] || SUDO="sudo"

# Виртуальный X-сервер и программный OpenGL (Mesa llvmpipe) — для tools/run_x.sh
PKGS="xvfb xauth libgl1-mesa-dri libgl1 libglx-mesa0 libegl1 libgles2 libxcursor1 libxi6 libxrandr2 libxinerama1 libpulse0"
MISSING=""
for p in $PKGS; do
  dpkg -s "$p" >/dev/null 2>&1 || MISSING="$MISSING $p"
done
if [ -n "$MISSING" ]; then
  echo "Устанавливаю:$MISSING"
  $SUDO apt-get update -qq
  # ставим по одному: если пакета нет в этом дистрибутиве, остальные всё равно поставятся
  for p in $MISSING; do
    $SUDO apt-get install -y -qq --no-install-recommends "$p" || echo "пропущен пакет $p"
  done
else
  echo "Пакеты xvfb/mesa уже установлены"
fi

command -v xvfb-run >/dev/null 2>&1 || { echo "ОШИБКА: xvfb-run не найден"; exit 1; }
if command -v godot >/dev/null 2>&1; then
  echo "Godot: $(godot --version 2>/dev/null | head -1)"
else
  echo "ВНИМАНИЕ: godot не найден в PATH (задайте GODOT=/путь/к/godot)"
fi
if [ -d /opt/granit-tools/android-sdk ]; then
  echo "Android SDK: /opt/granit-tools/android-sdk"
else
  echo "ВНИМАНИЕ: Android SDK не найден (нужен только для экспорта APK)"
fi
