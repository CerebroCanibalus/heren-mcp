@echo off
set GODOT=D:\Mis Juegos\Godot\Godot_v4.5-stable_win64.exe
set PROJECT=D:\Mis Juegos\GodotMCP\heren-mcp\fixtures\empty_project
"%GODOT%" --headless --path "%PROJECT%" --script res://addons/heren/tests/run_tests.gd
