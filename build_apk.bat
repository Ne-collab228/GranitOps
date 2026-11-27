@echo off
rem Пересборка APK (release). Требуются Godot 4.7.2 и Android SDK из C:\Users\user\Tools.
set GODOT_ANDROID_KEYSTORE_RELEASE_PATH=C:/Users/user/GranitOps/release.keystore
set GODOT_ANDROID_KEYSTORE_RELEASE_USER=granit
set GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD=granit2026
"C:\Users\user\Tools\godot\bin\Godot_v4.7.2-stable_win64_console.exe" --headless --path "%~dp0." --export-release "Android arm64" build/GranitOps-arm64.apk
echo.
echo Готово: %~dp0build\GranitOps-arm64.apk
pause
