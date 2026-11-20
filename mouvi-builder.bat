@echo off
setlocal
REM Mouvi plugin builder wrapper (Windows).
REM Requires Dart SDK on PATH and project dependencies fetched (`dart pub get` / `flutter pub get`).

set "SCRIPT_DIR=%~dp0"
pushd "%SCRIPT_DIR%"

where dart >nul 2>nul
if %ERRORLEVEL%==0 (
  dart run tool/mouvi_builder.dart %*
  set "CODE=%ERRORLEVEL%"
  popd
  exit /b %CODE%
)

where flutter >nul 2>nul
if %ERRORLEVEL%==0 (
  flutter pub run tool/mouvi_builder.dart %*
  set "CODE=%ERRORLEVEL%"
  popd
  exit /b %CODE%
)

echo Error: Dart SDK not found. Install Dart or Flutter and ensure "dart" is on PATH. 1>&2
popd
exit /b 127
