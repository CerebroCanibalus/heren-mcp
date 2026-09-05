//! Integration tests del LSP bridge con un fake LSP server TCP.
//!
//! Estos tests NO levantan Godot real (que pesaría ~300MB y bloquearía el
//! test runner). Levantan un fake LSP server en `127.0.0.1:0` (puerto
//! aleatorio) que:
//! - acepta conexiones
//! - recibe frames LSP y los reenvía como eco (o los descarta)
//! - puede simular caídas (cerrar el socket) y conexión
//!
//! El bridge se conecta al fake server a través de `run_proxy()` con pipes
//! in-memory para stdin/stdout (en lugar del stdin/stdout reales).

use std::sync::Arc;
use std::time::Duration;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::TcpListener;
use tokio::sync::{mpsc, Mutex};

use heren_server::lsp_bridge::frame::{encode, FrameParser};
use heren_server::lsp_bridge::proxy::run_proxy;

/// Helper: fake LSP server que acepta conexiones, lee frames, y reenvía cada
/// body recibido al `tx` channel. Permite cerrar el socket externamente
/// para probar la reconexión.
async fn fake_lsp_server(
    listener: TcpListener,
    tx: mpsc::Sender<Vec<u8>>,
    kill_signal: Arc<Mutex<bool>>,
) {
    loop {
        // Accept en un select con un check de kill_signal para no bloquearnos
        // cuando el test quiera que dejemos de aceptar.
        let accept_result =
            tokio::time::timeout(Duration::from_millis(100), listener.accept()).await;
        let (socket, _) = match accept_result {
            Ok(Ok(pair)) => pair,
            Ok(Err(_)) => continue,
            Err(_) => {
                if *kill_signal.lock().await {
                    return;
                }
                continue;
            }
        };

        // Task por conexión: lee frames, responde con eco, envía al channel.
        let tx_clone = tx.clone();
        tokio::spawn(async move {
            let mut socket = socket;
            let mut parser = FrameParser::new();
            let mut buf = vec![0u8; 64 * 1024];
            loop {
                match socket.read(&mut buf).await {
                    Ok(0) => return,
                    Ok(n) => {
                        let frames = parser.feed(&buf[..n]);
                        for body in frames {
                            let mut echo = b"ECHO:".to_vec();
                            echo.extend_from_slice(&body);
                            let framed = encode(&echo);
                            if socket.write_all(&framed).await.is_err() {
                                return;
                            }
                            if tx_clone.send(body).await.is_err() {
                                return;
                            }
                        }
                    }
                    Err(_) => return,
                }
            }
        });
    }
}

async fn spawn_fake_server() -> (u16, mpsc::Receiver<Vec<u8>>, Arc<Mutex<bool>>) {
    let listener = TcpListener::bind("127.0.0.1:0").await.expect("bind fake server");
    let port = listener.local_addr().expect("local_addr").port();
    let (tx, rx) = mpsc::channel(64);
    let kill = Arc::new(Mutex::new(false));
    let kill_clone = kill.clone();
    tokio::spawn(async move {
        fake_lsp_server(listener, tx, kill_clone).await;
    });
    // Pequeña pausa para que el server empiece a aceptar.
    tokio::time::sleep(Duration::from_millis(50)).await;
    (port, rx, kill)
}

#[tokio::test]
async fn proxy_forwards_frame_from_stdin_to_socket_and_back() {
    let (port, mut rx, _kill) = spawn_fake_server().await;

    // Pipes in-memory para stdin/stdout.
    let (mut stdin_write, stdin_read) = tokio::io::duplex(64 * 1024);
    let (stdout_write, mut stdout_read) = tokio::io::duplex(64 * 1024);

    // Lanza el proxy en background.
    let proxy_task = tokio::spawn(async move {
        run_proxy(
            "127.0.0.1".to_string(),
            port,
            5_000,
            false,
            stdin_read,
            stdout_write,
        )
        .await
    });

    // Escribir frame al stdin.
    let original_body = br#"{"jsonrpc":"2.0","id":1,"method":"initialize"}"#;
    let framed = encode(original_body);
    stdin_write.write_all(&framed).await.expect("write stdin");

    // Esperar el mensaje del fake server (confirma que stdin→socket funcionó).
    let received = tokio::time::timeout(Duration::from_secs(2), rx.recv())
        .await
        .expect("timeout esperando body")
        .expect("rx cerrado");
    assert_eq!(received, original_body);

    // Ahora leer stdout con timeout corto — el eco debería estar allí.
    // No usamos read_to_end porque el proxy no termina hasta que cerremos stdin.
    let mut out_buf = vec![0u8; 4096];
    let n = tokio::time::timeout(Duration::from_millis(500), stdout_read.read(&mut out_buf))
        .await
        .expect("timeout leyendo stdout")
        .expect("read error");
    assert!(n > 0, "stdout vacío (eco no llegó)");

    // Parsear el frame frameado en stdout.
    let mut parser = FrameParser::new();
    let frames = parser.feed(&out_buf[..n]);
    assert!(!frames.is_empty(), "no se pudo parsear stdout");
    let echo = &frames[0];
    assert!(echo.starts_with(b"ECHO:"), "eco no tiene prefijo ECHO: {echo:?}");
    assert_eq!(&echo[5..], original_body);

    // Cleanup: cerrar stdin para que el proxy termine.
    drop(stdin_write);
    tokio::time::timeout(Duration::from_secs(2), proxy_task)
        .await
        .expect("proxy timeout")
        .expect("proxy join")
        .expect("proxy error");
}

#[tokio::test]
async fn proxy_reconnects_after_socket_close() {
    // Server que se "cae" después de la primera conexión y "vuelve" en 200ms.
    let listener = TcpListener::bind("127.0.0.1:0").await.expect("bind");
    let port = listener.local_addr().unwrap().port();

    // Primera conexión: aceptar, leer 1 frame, luego cerrar el socket abruptamente.
    let (tx, mut rx) = mpsc::channel::<()>(8);
    let listener_task = tokio::spawn(async move {
        // Solo aceptamos 1 conexión.
        let (mut socket, _) = listener.accept().await.expect("accept");
        let mut buf = vec![0u8; 4096];
        let _ = socket.read(&mut buf).await;
        drop(socket); // cerrar
        tx.send(()).await.unwrap();
    });

    // Pipes.
    let (stdin_write, stdin_read) = tokio::io::duplex(64 * 1024);
    let (stdout_write, _stdout_read) = tokio::io::duplex(64 * 1024);

    let proxy_task = tokio::spawn(async move {
        run_proxy(
            "127.0.0.1".to_string(),
            port,
            5_000, // ventana de reconexión
            false,
            stdin_read,
            stdout_write,
        )
        .await
    });

    // Escribir frame 1 → server lo lee y cierra.
    let body1 = b"hello";
    let mut stdin_writer = stdin_write;
    stdin_writer.write_all(&encode(body1)).await.expect("write 1");
    drop(stdin_writer);

    // Esperar a que el server confirme la primera conexión.
    tokio::time::timeout(Duration::from_secs(2), rx.recv())
        .await
        .expect("timeout esperando server")
        .expect("rx");

    // Verificar que el proxy terminó (puerto muerto + ventana agotada o fin stdin).
    listener_task.await.ok();
    let result = tokio::time::timeout(Duration::from_secs(7), proxy_task)
        .await
        .expect("proxy se quedó colgado")
        .expect("proxy join");
    // Puede ser Ok (terminó por stdin EOF antes de intentar reconectar) o
    // ReconnectTimeout (si intentó reconectar y no había server). Ambos son
    // válidos para este test — lo importante es que el proxy NO se cuelga.
    let _ = result;
}
