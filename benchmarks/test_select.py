import socket
import select

# Probar conexión con select
sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
sock.setblocking(0)  # Non-blocking para ver comportamiento
try:
    result = sock.connect_ex(("127.0.0.1", 9110))
    print(f"Non-blocking connect_ex: {result}")
    
    # Usar select para esperar
    readable, writable, errors = select.select([], [sock], [sock], 2)
    if writable:
        print("Socket is writable - connection succeeded")
    if errors:
        print("Socket has errors")
except Exception as e:
    print(f"Error: {e}")
finally:
    sock.close()

# Ahora probar con Godot corriendo
import subprocess
import tempfile
import os
import time

project = tempfile.mkdtemp()
with open(os.path.join(project, "project.godot"), "w") as f:
    f.write("[application]\nconfig/name=\"Test\"\n")

cmd = [
    r"D:\Mis Juegos\Godot\Godot_v4.6.1-stable_win64.exe",
    "--headless",
    "--path", project,
    "--script", r"D:\Mis Juegos\GodotMCP\heren-mcp\benchmarks\test_simple_server.gd"
]

print("\nIniciando Godot...")
process = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
time.sleep(4)

# Probar con select
print("\nProbando con select...")
sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
sock.settimeout(3)
result = sock.connect_ex(("127.0.0.1", 9110))
print(f"connect_ex: {result}")

if result == 0:
    print("✓ Conexión exitosa!")
    sock.sendall(b"GET / HTTP/1.1\r\n\r\n")
    response = sock.recv(1024)
    print(f"Response: {response.decode()}")
elif result == 10035:
    print("⚠ Conexión en progreso (non-blocking)")
    # Esperar con select
    import select
    readable, writable, errors = select.select([], [sock], [sock], 3)
    if writable:
        print("✓ Socket listo para escritura - conexión exitosa")
        sock.sendall(b"GET / HTTP/1.1\r\n\r\n")
        response = sock.recv(1024)
        print(f"Response: {response.decode()}")
    else:
        print("✗ Timeout o error")
else:
    print(f"✗ Error de conexión: {result}")

sock.close()
process.terminate()
process.wait(timeout=5)

import shutil
shutil.rmtree(project, ignore_errors=True)
