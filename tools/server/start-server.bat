@echo off
rem Starts the dedicated server of the game in this folder (Windows): double-
rem click this file. No game window: the world runs on its own in this one.
rem Settings: server.properties next to the game (made with explanations on
rem the first start); see SERVER.md.
rem Type server commands here (help, list, say, kick, ban, op, whitelist,
rem save-all). Type "stop" to save the world and stop: closing this window
rem stops the server without saving the last minutes.
rem   start-server.bat [--port N] [--world NAME]
setlocal
cd /d "%~dp0"
set "NAME=Voxel Engine Godot Edition"
set "GAME="
rem The console build (if there is one) keeps this window for its input.
if exist "%NAME%.console.exe" set "GAME=%NAME%.console.exe"
if not defined GAME if exist "%NAME%.exe" set "GAME=%NAME%.exe"
if not defined GAME for %%f in (*.console.exe) do if not defined GAME set "GAME=%%f"
if not defined GAME for %%f in (*.exe) do if not defined GAME set "GAME=%%f"
if not defined GAME (
	echo The game ^(%NAME%.exe^) was not found next to this file
	pause
	exit /b 1
)
title Voxel Engine server
"%GAME%" --headless --server %*
echo.
echo The server stopped.
pause
endlocal
