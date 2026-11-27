@echo off
rem Пересборка APK (release). Требуются Godot 4.7.2 и Android SDK из C:\Users\user\Tools.
set GODOT_ANDROID_KEYSTORE_RELEASE_PATH=C:/Users/user/GranitOps/release.keystore
set GODOT_ANDROID_KEYSTORE_RELEASE_USER=granit
set GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD=granit2026
rem Токен журналов (GitHub) берётся из переменной GRANIT_LOG_TOKEN; файл с ним создаётся на время сборки и удаляется.
if defined GRANIT_LOG_TOKEN (
  > "%~dp0log_token.cfg" echo [log]
  >> "%~dp0log_token.cfg" echo token="%GRANIT_LOG_TOKEN%"
  >> "%~dp0log_token.cfg" echo repo="Ne-collab228/GranitOps"
  >> "%~dp0log_token.cfg" echo branch="logs"
) else (
  echo Токен GRANIT_LOG_TOKEN не задан: журналы не будут отправляться.
)
"C:\Users\user\Tools\godot\bin\Godot_v4.7.2-stable_win64_console.exe" --headless --path "%~dp0." --export-release "Android arm64" build/GranitOps-arm64.apk
del "%~dp0log_token.cfg" 2>nul
echo.
echo Готово: %~dp0build\GranitOps-arm64.apk
pause
