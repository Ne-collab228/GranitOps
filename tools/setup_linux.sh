#!/bin/bash
# Установка окружения для сборки Операции «Гранит» в Linux-контейнере (Ubuntu/Debian, root). Идемпотентно.
set -euo pipefail
T=/opt/granit-tools
GODOT_VER=4.7.2
REL=https://github.com/godotengine/godot/releases/download/$GODOT_VER-stable
PROJ="$(cd "$(dirname "$0")/.." && pwd)"
JAVA_HOME_17=/usr/lib/jvm/java-17-openjdk-amd64
SDK=$T/android-sdk
TPL=$HOME/.local/share/godot/export_templates/$GODOT_VER.stable
mkdir -p "$T/dl"

# 1. Godot
if [ ! -x "$T/godot/Godot_v${GODOT_VER}-stable_linux.x86_64" ]; then
  curl -fsSL -o "$T/dl/godot.zip" "$REL/Godot_v${GODOT_VER}-stable_linux.x86_64.zip"
  mkdir -p "$T/godot" && unzip -o -q "$T/dl/godot.zip" -d "$T/godot"
  chmod +x "$T/godot/Godot_v${GODOT_VER}-stable_linux.x86_64"
fi
ln -sf "$T/godot/Godot_v${GODOT_VER}-stable_linux.x86_64" /usr/local/bin/godot

# 2. Шаблоны экспорта (только Android) через HTTP Range
if [ ! -f "$TPL/android_release.apk" ] || [ ! -f "$TPL/android_source.zip" ] || [ ! -f "$TPL/version.txt" ]; then
  python3 -I "$PROJ/tools/remote_zip.py" "$REL/Godot_v${GODOT_VER}-stable_export_templates.tpz" extract "$TPL" \
    android_release.apk android_debug.apk android_source.zip version.txt
fi

# 3. JDK 17
if [ ! -x "$JAVA_HOME_17/bin/java" ]; then
  apt-get update -y
  apt-get install -y openjdk-17-jdk-headless unzip
fi

# 4. Android SDK
if [ ! -x "$SDK/cmdline-tools/latest/bin/sdkmanager" ]; then
  curl -fsSL -o "$T/dl/cmdtools.zip" https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip
  mkdir -p "$SDK/cmdline-tools" && rm -rf "$SDK/cmdline-tools/tmp"
  unzip -q -o "$T/dl/cmdtools.zip" -d "$SDK/cmdline-tools/tmp"
  rm -rf "$SDK/cmdline-tools/latest"; mv "$SDK/cmdline-tools/tmp/cmdline-tools" "$SDK/cmdline-tools/latest"
  rmdir "$SDK/cmdline-tools/tmp"
fi
if [ ! -d "$SDK/build-tools/34.0.0" ] || [ ! -d "$SDK/platforms/android-34" ] || [ ! -d "$SDK/platform-tools" ]; then
  yes | JAVA_HOME=$JAVA_HOME_17 "$SDK/cmdline-tools/latest/bin/sdkmanager" --sdk_root="$SDK" \
    "platform-tools" "build-tools;34.0.0" "platforms;android-34" >/dev/null || [ $? -eq 141 ] || true
fi

# 5. Python-пакеты
python3 -c "import numpy, PIL, scipy" 2>/dev/null || pip install --break-system-packages numpy pillow scipy

# 6/7. Отладочный ключ и настройки редактора (release.keystore НЕ создаётся)
if [ ! -f "$T/debug.keystore" ]; then
  "$JAVA_HOME_17/bin/keytool" -genkeypair -keystore "$T/debug.keystore" -alias androiddebugkey -storepass android \
    -keypass android -keyalg RSA -keysize 2048 -validity 10000 -dname "CN=Android Debug,O=Android,C=US"
fi
F=$HOME/.config/godot/editor_settings-4.7.tres
[ -f "$F" ] || godot --headless --editor --quit >/dev/null 2>&1 || true
set_key(){ if grep -q "^$1 =" "$F"; then sed -i "s|^$1 = .*|$1 = $2|" "$F"; else sed -i "/^\[resource\]/a $1 = $2" "$F"; fi; }
set_key export/android/debug_keystore "\"$T/debug.keystore\""
set_key export/android/debug_keystore_user '"androiddebugkey"'
set_key export/android/debug_keystore_pass '"android"'
set_key export/android/java_sdk_path "\"$JAVA_HOME_17\""
set_key export/android/android_sdk_path "\"$SDK\""

rm -rf "$T/dl"
echo "Готово. Проверка: godot --version; cd $PROJ && godot --headless --path . --import"
