import subprocess
import tempfile
import os
import time
import socket

# Crear proyecto temporal
project = tempfile.mkdtemp()
with open(os.path.join(project, "project.godot"), "w") as f:
    f.write("[application]\nconfig/name=\"Test\"\n")

cmd = [
    r"D:\Mis Juegos\Godot\Godot_v4.6.1-stable_win64.exe",
    "--headless",
    "--path", project,
    "--script", r"D:\Mis Juegos\GodotMCP\heren-mcp\src\heren\server\heren_server.gd",
    "--",
    "--project", os.path.join(project, "project.godot"),
    "--port", "9102"
]

print("Iniciando servidor...")
process = subprocess.Popen(
    cmd,
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
    text=True,
    encoding="utf-8"
)

# Esperar
print("Esperando 5 segundos...")
time.sleep(5)

# Verificar con netstat
print("Verificando puertos...")
result = subprocess.run(["netstat", "-an"], capture_output=True, text=True)
for line in result.stdout.split('\n'):
    if '9102' in line:
        print(f"NETSTAT: {line.strip()}")

# Verificar con Get-Process
print("\nVerificando proceso...")
result = subprocess.run(["powershell", "-Command", "Get-Process | Where-Object {$_.ProcessName -like '*godot*'} | Select-Object Id, ProcessName, Path"], capture_output=True, text=True)
print(result.stdout)

print("\nTerminando...")
process.terminate()
process.wait(timeout=5)
print("Listo")
