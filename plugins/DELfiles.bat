@echo off
for /f "delims=" %%i in ('dir/b/s/a-d^|findstr/ev "\.db"') do del /F %%i
pause