@echo off
setlocal
cd /d %~dp0
echo ----Martin's Server Launcher Script by TX----

if "%JAVA_HOME%"=="" (
  echo JAVA_HOME is not set. Point it at a Java 21 installation before starting the server.
  pause
  exit /b 1
)

set "JAVA_EXE=%JAVA_HOME%\bin\java.exe"
if not exist "%JAVA_EXE%" (
  echo JAVA_HOME does not point to a valid Java installation: %JAVA_HOME%
  pause
  exit /b 1
)

set "JAVA_VERSION_FILE=%TEMP%\txmcsv-java-version.txt"
"%JAVA_EXE%" -version 2>"%JAVA_VERSION_FILE%"
for /f "tokens=3" %%v in ('findstr /i "version" "%JAVA_VERSION_FILE%"') do set "JAVA_VERSION=%%~v"
del "%JAVA_VERSION_FILE%" >nul 2>&1
set "JAVA_VERSION=%JAVA_VERSION:"=%"
for /f "tokens=1 delims=." %%m in ("%JAVA_VERSION%") do set "JAVA_MAJOR=%%m"

if not defined JAVA_MAJOR (
  echo Failed to detect the Java version from %JAVA_EXE%
  pause
  exit /b 1
)

if %JAVA_MAJOR% LSS 21 (
  echo Java 21 or newer is required. Current detected version: %JAVA_VERSION%
  pause
  exit /b 1
)

echo Using %JAVA_EXE% ^(Java %JAVA_VERSION%^)
"%JAVA_EXE%" --add-modules=jdk.incubator.vector -Xms2G -Xmx2G ^
  -XX:+UseG1GC -XX:+ParallelRefProcEnabled -XX:MaxGCPauseMillis=200 ^
  -XX:+UnlockExperimentalVMOptions -XX:+DisableExplicitGC -XX:+AlwaysPreTouch ^
  -XX:G1NewSizePercent=30 -XX:G1MaxNewSizePercent=40 -XX:G1HeapRegionSize=8M ^
  -XX:G1ReservePercent=20 -XX:G1HeapWastePercent=5 -XX:G1MixedGCCountTarget=4 ^
  -XX:InitiatingHeapOccupancyPercent=15 -XX:G1MixedGCLiveThresholdPercent=90 ^
  -XX:G1RSetUpdatingPauseTimePercent=5 -XX:SurvivorRatio=32 ^
  -XX:+PerfDisableSharedMem -XX:MaxTenuringThreshold=1 ^
  -jar server.jar -nogui
pause
