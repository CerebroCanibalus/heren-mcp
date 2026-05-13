import tempfile
import os
import shutil
import sys

# Add paths
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "src"))

from heren.core.godot_server import GodotServer

# Crear proyecto temporal
project = tempfile.mkdtemp()
with open(os.path.join(project, "project.godot"), "w") as f:
    f.write('[application]\nconfig/name="Test"\n')

import subprocess

# Probar ejecutar Godot directamente para ver output
print("Probando Godot directamente...")
cmd = [
    r"D:\Mis Juegos\Godot\Godot_v4.6.1-stable_win64.exe",
    "--headless",
    "--script", os.path.join(os.path.dirname(__file__), "..", "src", "heren", "server", "heren_server.gd"),
    "--project", os.path.join(project, "project.godot"),
    "--port", "9092"
]

print(f"Comando: {' '.join(cmd)}")
process = subprocess.Popen(
    cmd,
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
    text=True,
    encoding="utf-8"
)

# Leer output por 10 segundos
import time
start = time.time()
while time.time() - start < 10:
    import select
    # Leer stdout
    import sys
    output = process.stdout.readline()
    if output:
        print(f"STDOUT: {output.strip()}")
    error = process.stderr.readline()
    if error:
        print(f"STDERR: {error.strip()}")
    if process.poll() is not None:
        break
    time.sleep(0.1)

process.terminate()
print("Proceso terminado")

shutil.rmtree(project, ignore_errors=True)
