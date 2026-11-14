@echo off
rem Runs a dedicated server (SERVER.md) on Windows: no window, no sound.
rem Lines typed here are server commands (help, list, say, kick, ban, op,
rem whitelist, save-all, stop). Type "stop" to save the world and stop:
rem closing this window or Ctrl+C stops it without saving the last minutes.
rem
rem   tools\run_server.bat
rem   tools\run_server.bat --port 25570 --world survival2
rem
rem server.properties is made in the current folder on the first start
rem (or where --config says). Godot: %GODOT%, else godot.exe on the PATH.
setlocal
set "ROOT=%~dp0.."
if "%GODOT%"=="" set "GODOT=godot.exe"
set "CONFIG=--config "%CD%\server.properties""
echo %* | findstr /C:"--config" >nul && set "CONFIG="
if exist "%ROOT%\project.godot" (
	"%GODOT%" --headless --path "%ROOT%" -- --server %CONFIG% %*
) else (
	"%GODOT%" --headless -- --server %CONFIG% %*
)
endlocal
