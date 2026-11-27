#!/bin/sh
# Сборка APK на Linux. Использование: tools/build_apk.sh [release|debug] [выходной.apk]
# Переменные: GODOT (путь к godot, иначе из PATH), GRANIT_LOG_TOKEN (токен журналов; иначе файл
# /opt/granit-tools/log_token; нет токена — журналы пишутся, но не отправляются).
# Для release нужен release.keystore в корне (alias granit; пароль — GRANIT_KS_PASS или по умолчанию из CLAUDE.md).
# Токен кладётся в res://log_token.cfg (в git не попадает) и удаляется сразу после сборки.
MODE="${1:-release}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
G="${GODOT:-godot}"
OUT="${2:-$ROOT/build/GranitOps-arm64.apk}"
CFG="$ROOT/log_token.cfg"
TOKEN="${GRANIT_LOG_TOKEN:-}"
if [ -z "$TOKEN" ] && [ -r /opt/granit-tools/log_token ]; then
  TOKEN="$(tr -d ' \r\n' < /opt/granit-tools/log_token)"
fi
trap 'rm -f "$CFG"' EXIT INT TERM
if [ -n "$TOKEN" ]; then
  ( umask 077; printf '[log]\ntoken="%s"\nrepo="Ne-collab228/GranitOps"\nbranch="logs"\n' "$TOKEN" > "$CFG" )
else
  rm -f "$CFG"
  echo "Токен журналов не найден: журналы не будут отправляться."
fi
mkdir -p "$ROOT/build"
cd "$ROOT" || exit 1
if [ "$MODE" = "debug" ]; then
  "$G" --headless --path . --export-debug "Android arm64" "$OUT"
else
  export GODOT_ANDROID_KEYSTORE_RELEASE_PATH="$ROOT/release.keystore"
  export GODOT_ANDROID_KEYSTORE_RELEASE_USER="granit"
  export GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD="${GRANIT_KS_PASS:-granit2026}"
  "$G" --headless --path . --export-release "Android arm64" "$OUT"
fi
RC=$?
rm -f "$CFG"
echo "Готово: $OUT (код $RC)"
exit $RC
