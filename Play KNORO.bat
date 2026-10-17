@echo off
title KNORO
cd /d "%~dp0"
echo KNORO hazirlaniyor (yeni dosyalar varsa ilk acilis biraz surebilir)...
"engine\Godot_v4.7.2-stable_win64_console.exe" --headless --path game --import >nul 2>&1
start "" "engine\Godot_v4.7.2-stable_win64.exe" --path game %*
