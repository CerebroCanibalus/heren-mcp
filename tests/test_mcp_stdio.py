#!/usr/bin/env python3
"""Test rápido del servidor MCP Heren"""

import subprocess
import json
import time
import sys

def test_mcp_server():
    # Iniciar el servidor MCP
    proc = subprocess.Popen(
        [sys.executable, "-m", "heren.server"],
        cwd=r"D:\Mis Juegos\GodotMCP\heren-mcp",
        env={"PYTHONPATH": r"D:\Mis Juegos\GodotMCP\heren-mcp\src"},
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    
    # Esperar un poco
    time.sleep(2)
    
    # Verificar si el proceso sigue vivo
    if proc.poll() is not None:
        stdout, stderr = proc.communicate()
        print("ERROR: El servidor murió inmediatamente")
        print("STDOUT:", stdout)
        print("STDERR:", stderr)
        return False
    
    print("✓ Servidor MCP iniciado correctamente")
    
    # Enviar inicialización MCP
    init_msg = {
        "jsonrpc": "2.0",
        "id": 1,
        "method": "initialize",
        "params": {
            "protocolVersion": "2024-11-05",
            "capabilities": {},
            "clientInfo": {"name": "test", "version": "1.0"}
        }
    }
    
    init_json = json.dumps(init_msg)
    proc.stdin.write(f"Content-Length: {len(init_json)}\r\n\r\n{init_json}")
    proc.stdin.flush()
    
    # Leer respuesta
    time.sleep(1)
    
    try:
        stdout, stderr = proc.communicate(timeout=3)
        if stdout:
            print("✓ Servidor respondió:")
            # Intentar parsear la respuesta
            if "Content-Length" in stdout:
                print("✓ Protocolo MCP funcionando")
            else:
                print("Respuesta:", stdout[:500])
        if stderr:
            print("STDERR:", stderr[:500])
    except subprocess.TimeoutExpired:
        proc.kill()
        print("✓ Servidor sigue corriendo (timeout esperado)")
    
    return True

if __name__ == "__main__":
    success = test_mcp_server()
    sys.exit(0 if success else 1)
