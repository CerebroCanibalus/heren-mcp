#!/usr/bin/env python3
"""Test completo del protocolo MCP via stdio"""

import subprocess
import json
import time
import sys
import os

def send_message(proc, msg):
    msg_json = json.dumps(msg)
    header = f"Content-Length: {len(msg_json)}\r\n\r\n{msg_json}"
    proc.stdin.write(header)
    proc.stdin.flush()

def read_message(proc):
    headers = {}
    while True:
        line = proc.stdout.readline()
        if line == '\r\n' or line == '\n':
            break
        if ':' in line:
            key, value = line.split(':', 1)
            headers[key.strip().lower()] = value.strip()
    
    if 'content-length' in headers:
        length = int(headers['content-length'])
        body = proc.stdout.read(length)
        return json.loads(body)
    return None

def test_mcp():
    env = os.environ.copy()
    env['PYTHONPATH'] = r"D:\Mis Juegos\GodotMCP\heren-mcp\src"
    
    proc = subprocess.Popen(
        [sys.executable, "-m", "heren.server"],
        cwd=r"D:\Mis Juegos\GodotMCP\heren-mcp",
        env=env,
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        bufsize=1,
    )
    
    time.sleep(2)
    
    if proc.poll() is not None:
        stdout, stderr = proc.communicate()
        print("SERVER DIED IMMEDIATELY")
        print("STDERR:", stderr[-1000:])
        return False
    
    print("Server started")
    
    try:
        # Initialize
        print("Sending initialize...")
        send_message(proc, {
            "jsonrpc": "2.0",
            "id": 1,
            "method": "initialize",
            "params": {
                "protocolVersion": "2024-11-05",
                "capabilities": {},
                "clientInfo": {"name": "test", "version": "1.0"}
            }
        })
        
        response = read_message(proc)
        if response:
            print("Initialize OK:", response.get("id"))
        else:
            print("No initialize response")
            return False
        
        # tools/list
        print("Sending tools/list...")
        send_message(proc, {
            "jsonrpc": "2.0",
            "id": 2,
            "method": "tools/list",
            "params": {}
        })
        
        response = read_message(proc)
        if response and "result" in response:
            tools = response["result"].get("tools", [])
            print(f"Tools listed: {len(tools)}")
            for tool in tools:
                print(f"  - {tool['name']}")
        else:
            print("tools/list failed:", response)
            return False
        
        # Shutdown
        print("Sending shutdown...")
        send_message(proc, {
            "jsonrpc": "2.0",
            "id": 3,
            "method": "shutdown"
        })
        
        proc.stdin.close()
        proc.wait(timeout=5)
        print("Server closed cleanly")
        return True
        
    except Exception as e:
        print(f"Error: {e}")
        proc.kill()
        return False

if __name__ == "__main__":
    success = test_mcp()
    sys.exit(0 if success else 1)
