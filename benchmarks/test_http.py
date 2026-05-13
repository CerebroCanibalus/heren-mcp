import subprocess
import tempfile
import os
import time
import json

# Crear proyecto temporal
project = tempfile.mkdtemp()
with open(os.path.join(project, "project.godot"), "w") as f:
    f.write("[application]\nconfig/name=\"Test\"\n")

# Crear escena de prueba
scene_path = os.path.join(project, "test_scene.tscn")
with open(scene_path, "w") as f:
    f.write("[gd_scene load_steps=1 format=3]\n\n[node name=\"Root\" type=\"Node2D\"]\n")

cmd = [
    r"D:\Mis Juegos\Godot\Godot_v4.6.1-stable_win64.exe",
    "--headless",
    "--path", project,
    "--script", r"D:\Mis Juegos\GodotMCP\heren-mcp\src\heren\server\heren_server.gd",
    "--",
    "--project", os.path.join(project, "project.godot"),
    "--port", "9098"
]

print("Iniciando servidor...")
process = subprocess.Popen(
    cmd,
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
    text=True,
    encoding="utf-8",
    bufsize=1
)

# Leer output hasta que esté listo
print("Esperando ready...")
for line in iter(process.stdout.readline, ''):
    print(f"STDOUT: {line.strip()}")
    if '"status": "ready"' in line:
        break

print("Servidor listo! Enviando request...")

# Enviar request HTTP
import socket

request_data = {
    "operation": "get_scene_tree",
    "params": {"scene_path": scene_path}
}

body = json.dumps(request_data)
request = f"POST /execute HTTP/1.1\r\n"
request += f"Host: 127.0.0.1:9098\r\n"
request += f"Content-Type: application/json\r\n"
request += f"Content-Length: {len(body)}\r\n"
request += f"Connection: close\r\n"
request += f"\r\n"
request += body

with socket.create_connection(("127.0.0.1", 9098), timeout=10) as sock:
    sock.sendall(request.encode("utf-8"))
    
    response = b""
    while True:
        chunk = sock.recv(4096)
        if not chunk:
            break
        response += chunk

response_text = response.decode("utf-8")
print(f"Response: {response_text[:500]}")

# Enviar quit
quit_request = f"POST /execute HTTP/1.1\r\n"
quit_request += f"Host: 127.0.0.1:9098\r\n"
quit_request += f"Content-Type: application/json\r\n"
quit_request += f"Content-Length: 28\r\n"
quit_request += f"Connection: close\r\n"
quit_request += f"\r\n"
quit_request += '{"operation": "quit", "params": {}}'

with socket.create_connection(("127.0.0.1", 9098), timeout=5) as sock:
    sock.sendall(quit_request.encode("utf-8"))

print("Proceso terminado")
process.wait(timeout=5)
