import subprocess
import tempfile
import os

# Crear proyecto temporal
project = tempfile.mkdtemp()
with open(os.path.join(project, "project.godot"), "w") as f:
    f.write('[application]\nconfig/name="Test"\n')

cmd = [
    r"D:\Mis Juegos\Godot\Godot_v4.6.1-stable_win64.exe",
    "--headless",
    "--path", project,
    "--script", r"D:\Mis Juegos\GodotMCP\heren-mcp\benchmarks\test_simple.gd"
]

print(f"Ejecutando: {' '.join(cmd)}")
result = subprocess.run(cmd, capture_output=True, text=True, timeout=10)
print(f"Return code: {result.returncode}")
print(f"STDOUT: {result.stdout}")
print(f"STDERR: {result.stderr}")
