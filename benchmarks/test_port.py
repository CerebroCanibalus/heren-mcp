import subprocess
import tempfile
import os
import time
import json
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
    "--port", "9101"
]

print("Iniciando servidor...")
process = subprocess.Popen(
    cmd,
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
    text=True,
    encoding="utf-8"
)

# Simplemente esperar un tiempo fijo
print("Esperando 8 segundos para que el servidor inicie...")
time.sleep(8)

# Verificar puerto
sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
sock.settimeout(2)
result = sock.connect_ex(("127.0.0.1", 9101))
if result == 0:
    print("Puerto 9101 ABIERTO!")
    sock.close()
    
    # Enviar request
    request_data = {
        "operation": "ping",
        "params": {}
    }
    body = json.dumps(request_data)
    request = f"POST /execute HTTP/1.1\r\n"
    request += f"Host: 127.0.0.1:9101\r\n"
    request += f"Content-Type: application/json\r\n"
    request += f"Content-Length: {len(body)}\r\n"
    request += f"Connection: close\r\n"
    request += f"\r\n"
    request += body
    
    try:
        with socket.create_connection(("127.0.0.1", 9101), timeout=5) as s:
            s.sendall(request.encode("utf-8"))
            response = b""
            while True:
                chunk = s.recv(4096)
                if not chunk:
                    break
                response += chunk
        
        print(f"Response: {response.decode('utf-8')}")
    except Exception as e:
        print(f"Error enviando request: {e}")
else:
    print(f"Puerto 9101 CERRADO (error: {result})")
    sock.close()

# Leer output acumulado
import threading

def read_all(pipe, label):
    try:
        data = pipe.read()
        if data:
            for line in data.split('\n'):
                if line.strip():
                    print(f"{label}: {line.strip()}")
    except:
        pass

stdout_thread = threading.Thread(target=read_all, args=(process.stdout, "STDOUT"))
stderr_thread = threading.Thread(target=read_all, args=(process.stderr, "STDERR"))
stdout_thread.start()
stderr_thread.start()

stdout_thread.join(timeout=3)
stderr_thread.join(timeout=3)

print("Terminando proceso...")
process.terminate()
process.wait(timeout=5)
print("Listo")
