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
    "--script", r"D:\Mis Juegos\GodotMCP\heren-mcp\benchmarks\test_simple_server.gd"
]

print("Iniciando servidor simple...")
process = subprocess.Popen(
    cmd,
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
    text=True,
    encoding="utf-8"
)

# Esperar a que esté listo
print("Esperando 3 segundos...")
time.sleep(3)

# Verificar puerto
sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
sock.settimeout(2)
result = sock.connect_ex(("127.0.0.1", 9110))
if result == 0:
    print("Puerto 9110 ABIERTO!")
    sock.close()
    
    # Enviar request
    try:
        with socket.create_connection(("127.0.0.1", 9110), timeout=5) as s:
            s.sendall(b"GET / HTTP/1.1\r\n\r\n")
            response = b""
            while True:
                chunk = s.recv(4096)
                if not chunk:
                    break
                response += chunk
        print(f"Response: {response.decode('utf-8')}")
    except Exception as e:
        print(f"Error: {e}")
else:
    print(f"Puerto 9110 CERRADO (error: {result})")
    sock.close()

# Leer output
import threading

def read_output(pipe, label):
    try:
        data = pipe.read()
        if data:
            for line in data.split('\n'):
                if line.strip():
                    print(f"{label}: {line.strip()}")
    except:
        pass

stdout_thread = threading.Thread(target=read_output, args=(process.stdout, "STDOUT"))
stderr_thread = threading.Thread(target=read_output, args=(process.stderr, "STDERR"))
stdout_thread.start()
stderr_thread.start()

stdout_thread.join(timeout=3)
stderr_thread.join(timeout=3)

print("Terminando...")
process.terminate()
process.wait(timeout=5)
print("Listo")
