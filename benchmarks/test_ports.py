import subprocess
import tempfile
import os
import time
import socket

# Probar con diferentes puertos
for test_port in [8080, 9000, 15000, 50000]:
    project = tempfile.mkdtemp()
    with open(os.path.join(project, "project.godot"), "w") as f:
        f.write("[application]\nconfig/name=\"Test\"\n")
    
    # Crear script GD dinámico con el puerto
    script_path = os.path.join(tempfile.gettempdir(), f"test_server_{test_port}.gd")
    with open(script_path, "w") as f:
        f.write(f'''extends MainLoop
var server: TCPServer
func _initialize():
	server = TCPServer.new()
	var err = server.listen({test_port}, "127.0.0.1")
	print("Port {test_port}: listen() = " + str(err))
	if err == OK:
		print('{{"status": "ready", "port": {test_port}}}')
		OS.delay_msec(2000)
	print("Done")
func _process(delta: float) -> bool:
	return true
''')
    
    cmd = [
        r"D:\Mis Juegos\Godot\Godot_v4.6.1-stable_win64.exe",
        "--headless",
        "--path", project,
        "--script", script_path
    ]
    
    print(f"\n=== Probando puerto {test_port} ===")
    process = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    time.sleep(3)
    
    # Verificar puerto
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock.settimeout(2)
    result = sock.connect_ex(("127.0.0.1", test_port))
    sock.close()
    
    print(f"connect_ex result: {result}")
    
    if result == 0:
        print(f"✅ Puerto {test_port} ABIERTO!")
    else:
        print(f"❌ Puerto {test_port} CERRADO (error: {result})")
    
    process.terminate()
    process.wait(timeout=5)
    
    # Leer output
    stdout, stderr = process.communicate(timeout=5)
    for line in stdout.split('\n'):
        if line.strip():
            print(f"OUT: {line.strip()}")
    
    import shutil
    shutil.rmtree(project, ignore_errors=True)
    os.remove(script_path)
    
    time.sleep(1)

print("\n=== Prueba completada ===")
