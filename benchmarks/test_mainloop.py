import subprocess
import tempfile
import os
import time

# Crear proyecto temporal
project = tempfile.mkdtemp()
with open(os.path.join(project, "project.godot"), "w") as f:
    f.write('[application]\nconfig/name="Test"\n')

cmd = [
    r"D:\Mis Juegos\Godot\Godot_v4.6.1-stable_win64.exe",
    "--headless",
    "--path", project,
    "--script", r"D:\Mis Juegos\GodotMCP\heren-mcp\src\heren\server\heren_server.gd",
    "--port", "9095"
]

print(f"Ejecutando servidor...")
print(f"Comando: {' '.join(cmd)}")

process = subprocess.Popen(
    cmd,
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
    text=True,
    encoding="utf-8"
)

# Esperar output por 15 segundos
start = time.time()
while time.time() - start < 15:
    if process.poll() is not None:
        print(f"Proceso terminó con código: {process.returncode}")
        break
    
    # Leer stdout (non-blocking)
    line = process.stdout.readline()
    if line:
        print(f"STDOUT: {line.strip()}")
    
    # Leer stderr
    err_line = process.stderr.readline()
    if err_line:
        print(f"STDERR: {err_line.strip()}")
    
    time.sleep(0.5)

process.terminate()
print("Proceso terminado")
