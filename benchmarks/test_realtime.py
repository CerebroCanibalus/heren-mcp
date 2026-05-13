import subprocess
import tempfile
import os
import time
import threading

# Crear proyecto temporal
project = tempfile.mkdtemp()
with open(os.path.join(project, "project.godot"), "w") as f:
    f.write("[application]\nconfig/name=\"Test\"\n")

cmd = [
    r"D:\Mis Juegos\Godot\Godot_v4.6.1-stable_win64.exe",
    "--headless",
    "--path", project,
    "--script", r"D:\Mis Juegos\GodotMCP\heren-mcp\src\heren\server\heren_server.gd",
    "--",  # Separator: everything after this goes to the script
    "--project", os.path.join(project, "project.godot"),
    "--port", "9097"
]

print("Ejecutando...")
print(f"Comando: {cmd}")

process = subprocess.Popen(
    cmd,
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
    text=True,
    encoding="utf-8",
    bufsize=1  # Line buffered
)

def read_output(pipe, label):
    """Read output from pipe in background."""
    for line in iter(pipe.readline, ''):
        if line:
            print(f"{label}: {line.strip()}")
    pipe.close()

# Start threads to read output
stdout_thread = threading.Thread(target=read_output, args=(process.stdout, "STDOUT"))
stderr_thread = threading.Thread(target=read_output, args=(process.stderr, "STDERR"))
stdout_thread.daemon = True
stderr_thread.daemon = True
stdout_thread.start()
stderr_thread.start()

# Wait a bit for startup
print("Esperando 8 segundos...")
time.sleep(8)

print("Terminando proceso...")
process.terminate()

# Wait for threads to finish
stdout_thread.join(timeout=2)
stderr_thread.join(timeout=2)

print("Listo")
