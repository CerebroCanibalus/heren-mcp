"""
Test end-to-end del GodotDaemon.

Este script prueba:
1. Inicio del daemon
2. Conexión WebSocket
3. Operaciones básicas (ping, health, get_scene_tree)
4. Batch operations
5. Screenshots (si hay display)
6. Detención limpia

Uso:
    python test_daemon.py --project-path "D:/MiProyecto"
"""

import argparse
import logging
import sys
import time

# Setup logging
logging.basicConfig(
    level=logging.DEBUG,
    format="%(asctime)s - %(name)s - %(levelname)s - %(message)s",
    handlers=[logging.StreamHandler(sys.stdout)],
)
logger = logging.getLogger(__name__)


def test_daemon(project_path: str) -> bool:
    """Prueba completa del daemon."""
    
    logger.info("=" * 60)
    logger.info("TEST GODOT DAEMON")
    logger.info("=" * 60)
    
    # Importar aquí para evitar problemas si no está instalado
    from heren.core.session_manager import get_session_manager
    
    session_manager = get_session_manager()
    
    # 1. Iniciar sesión con daemon
    logger.info("\n[1/7] Iniciando sesión con daemon...")
    start_time = time.time()
    
    try:
        session = session_manager.start_session(
            project_path=project_path,
            use_daemon=True,
            use_server=False
        )
        session_id = session.id
        init_time = time.time() - start_time
        logger.info(f"✅ Sesión iniciada: {session_id} (tardó {init_time:.2f}s)")
    except Exception as e:
        logger.error(f"❌ Error iniciando sesión: {e}")
        return False
    
    # 2. Verificar daemon conectado
    logger.info("\n[2/7] Verificando daemon...")
    daemon = session_manager.get_godot_daemon(session_id)
    if not daemon:
        logger.error("❌ Daemon no está conectado")
        session_manager.end_session(session_id)
        return False
    logger.info(f"✅ Daemon conectado en puerto {daemon.port}")
    
    # 3. Ping
    logger.info("\n[3/7] Test ping...")
    start_time = time.time()
    result = session_manager.execute_via_daemon(session_id, "ping", {})
    ping_time = time.time() - start_time
    
    if result.get("success") and result.get("pong"):
        logger.info(f"✅ Ping exitoso en {ping_time*1000:.1f}ms")
    else:
        logger.error(f"❌ Ping falló: {result}")
        session_manager.end_session(session_id)
        return False
    
    # 4. Health check
    logger.info("\n[4/7] Health check...")
    result = session_manager.execute_via_daemon(session_id, "health", {})
    if result.get("success"):
        logger.info(f"✅ Daemon healthy")
        logger.info(f"   - Escenas cacheadas: {result.get('scenes_cached', 0)}")
        logger.info(f"   - Memoria: {result.get('memory_mb', 0)} MB")
        logger.info(f"   - Peers: {result.get('peers_connected', 0)}")
    else:
        logger.error(f"❌ Health check falló: {result}")
    
    # 5. Encontrar una escena para probar
    logger.info("\n[5/7] Buscando escenas...")
    import os
    scenes = []
    for root, dirs, files in os.walk(project_path):
        for file in files:
            if file.endswith(".tscn"):
                rel_path = os.path.relpath(os.path.join(root, file), project_path)
                scenes.append("res://" + rel_path.replace("\\", "/"))
    
    if not scenes:
        logger.warning("⚠️ No se encontraron escenas .tscn")
    else:
        test_scene = scenes[0]
        logger.info(f"   Escena de prueba: {test_scene}")
        
        # 5a. Load scene
        logger.info(f"\n[5a] Cargando escena...")
        start_time = time.time()
        result = session_manager.execute_via_daemon(session_id, "load_scene", {
            "scene_path": test_scene
        })
        load_time = time.time() - start_time
        
        if result.get("success"):
            logger.info(f"✅ Escena cargada en {load_time*1000:.1f}ms")
            logger.info(f"   - Nodos: {result.get('node_count', 0)}")
            logger.info(f"   - Cacheada: {result.get('cached', False)}")
        else:
            logger.error(f"❌ Error cargando escena: {result.get('error')}")
        
        # 5b. Get scene tree (debería ser rápido porque está cacheada)
        logger.info(f"\n[5b] Get scene tree (cache)...")
        start_time = time.time()
        result = session_manager.execute_via_daemon(session_id, "get_scene_tree", {
            "scene_path": test_scene
        })
        tree_time = time.time() - start_time
        
        if result.get("success"):
            logger.info(f"✅ Scene tree obtenido en {tree_time*1000:.1f}ms")
            logger.info(f"   - Nodos: {result.get('node_count', 0)}")
        else:
            logger.error(f"❌ Error obteniendo scene tree: {result.get('error')}")
        
        # 5c. Batch operations
        logger.info(f"\n[5c] Batch operations...")
        start_time = time.time()
        result = session_manager.execute_batch_via_daemon(session_id, [
            {"method": "ping", "params": {}},
            {"method": "health", "params": {}},
            {"method": "get_scene_tree", "params": {"scene_path": test_scene}},
        ])
        batch_time = time.time() - start_time
        
        if result.get("success"):
            logger.info(f"✅ Batch ejecutado en {batch_time*1000:.1f}ms")
            logger.info(f"   - Operaciones: {result.get('operation_count', 0)}")
        else:
            logger.error(f"❌ Batch falló: {result.get('error')}")
    
    # 6. Performance metrics
    logger.info("\n[6/7] Performance metrics...")
    result = session_manager.execute_via_daemon(session_id, "performance_metrics", {})
    if result.get("success"):
        metrics = result.get("metrics", {})
        logger.info(f"✅ Métricas obtenidas")
        logger.info(f"   - FPS: {metrics.get('fps', 0)}")
        logger.info(f"   - Objetos: {metrics.get('objects', 0)}")
        logger.info(f"   - Nodos: {metrics.get('nodes', 0)}")
        logger.info(f"   - Draw calls: {metrics.get('draw_calls', 0)}")
    else:
        logger.warning(f"⚠️ No se pudieron obtener métricas: {result.get('error')}")
    
    # 7. Screenshot (solo si hay escenas)
    if scenes:
        logger.info("\n[7/7] Screenshot...")
        import tempfile
        output_path = tempfile.mktemp(suffix=".png")
        start_time = time.time()
        result = session_manager.execute_via_daemon(session_id, "screenshot", {
            "scene_path": test_scene,
            "output_path": output_path.replace("\\", "/"),
            "resolution": [640, 360],
            "wait_frames": 1,
            "format": "png"
        })
        screenshot_time = time.time() - start_time
        
        if result.get("success"):
            logger.info(f"✅ Screenshot capturado en {screenshot_time*1000:.1f}ms")
            logger.info(f"   - Archivo: {result.get('image_path')}")
            logger.info(f"   - Tamaño: {result.get('file_size_bytes', 0)} bytes")
        else:
            logger.warning(f"⚠️ Screenshot falló: {result.get('error')}")
    
    # Cleanup
    logger.info("\n" + "=" * 60)
    logger.info("Cerrando sesión...")
    session_manager.end_session(session_id)
    logger.info("✅ Test completado")
    logger.info("=" * 60)
    
    return True


def main():
    parser = argparse.ArgumentParser(description="Test GodotDaemon")
    parser.add_argument("--project-path", required=True, help="Ruta al proyecto Godot")
    
    args = parser.parse_args()
    
    success = test_daemon(args.project_path)
    sys.exit(0 if success else 1)


if __name__ == "__main__":
    main()
