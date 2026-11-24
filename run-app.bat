@echo off
echo ========================================
echo My Tour App - Build and Run
echo ========================================
echo.

REM Check if device is connected
adb devices | findstr "device" >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo ERROR: No Android device connected
    echo Please connect your device via USB or wireless debugging
    pause
    exit /b 1
)

echo Device connected:
adb devices
echo.

echo Step 1: Getting Flutter dependencies...
call flutter pub get
if %ERRORLEVEL% NEQ 0 (
    echo ERROR: Failed to get dependencies
    pause
    exit /b 1
)
echo.

echo Step 2: Building and running app...
echo This may take a few minutes on first build...
echo.

call flutter run
