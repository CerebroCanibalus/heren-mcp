import socket

# Crear socket y verificar modo
sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
print(f"Blocking mode: {sock.getblocking()}")
print(f"Timeout: {sock.gettimeout()}")

# Intentar conexión
result = sock.connect_ex(("127.0.0.1", 9110))
print(f"connect_ex result: {result}")
print(f"Error name: {socket.errorcode.get(result, 'Unknown')}")

sock.close()

# Probar con un puerto que sabemos que está abierto (si hay alguno)
import subprocess
# Intentar conectar a un servicio conocido
for port in [80, 443, 22]:
    try:
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        sock.settimeout(2)
        result = sock.connect_ex(("127.0.0.1", port))
        print(f"Port {port}: {result}")
        sock.close()
    except Exception as e:
        print(f"Port {port}: Error - {e}")
