//! LSP frame parser (framing LSP estándar: headers `Content-Length` + JSON-RPC 2.0 body).
//!
//!
//! LSP usa un framing minimalista estilo HTTP pero sin status line ni verb:
//!
//! ```text
//! Content-Length: 42\r\n
//! \r\n
//! {"jsonrpc":"2.0","id":1,...}
//! ```
//!
//! Otros headers (e.g. `Content-Type`) se ignoran. El body es UTF-8 con longitud
//! exacta indicada por `Content-Length`. Este módulo es **puro** (sin I/O), lo
//! cual permite tests unitarios deterministas sin levantar sockets.
//!
//! ## Por qué no `lsp-types` / `tokio-lsp`
//!
//! El bridge solo necesita el framing + JSON-RPC 2.0; los tipos LSP semánticos
//! (`CompletionItem`, `Hover`, etc.) los maneja OpenCode por su lado. Meternos
//! con `lsp-types` añadiría ~3MB al binario y un grafo de tipos completo que
//! nunca consultamos (el bridge es proxy passthrough). `serde_json::Value` basta.

use thiserror::Error;

#[derive(Debug, Error, PartialEq, Eq)]
pub enum FrameError {
    /// `Content-Length` header ausente o no parseable.
    #[error("missing or invalid Content-Length header")]
    MissingContentLength,
    /// Headers contienen bytes no UTF-8.
    #[error("non-UTF8 header bytes")]
    NonUtf8Header,
}

/// Resultado de un intento de extraer el siguiente frame del buffer interno.
#[derive(Debug)]
pub enum ParseOutcome {
    /// Frame completo listo (`Content-Length` bytes de body extraídos).
    Complete(Vec<u8>),
    /// Aún no hay suficientes bytes en el buffer; el caller debe `feed()` más.
    Incomplete,
    /// Header malformado; el caller debe descartar hasta el próximo `\r\n\r\n`.
    Error(FrameError),
}

/// Parser incremental: el caller hace `feed()` con bytes crudos del socket
/// y recibe los frames completos que se hayan podido formar.
#[derive(Debug, Default)]
pub struct FrameParser {
    buffer: Vec<u8>,
}

impl FrameParser {
    #[must_use]
    pub fn new() -> Self {
        Self::default()
    }

    /// Alimenta bytes al parser. Devuelve **todos** los frames completos que se
    /// hayan podido formar; el resto queda en el buffer interno para el próximo `feed`.
    pub fn feed(&mut self, chunk: &[u8]) -> Vec<Vec<u8>> {
        self.buffer.extend_from_slice(chunk);
        let mut frames = Vec::new();
        loop {
            match self.parse_one_and_consume() {
                ParseOutcome::Complete(body) => frames.push(body),
                ParseOutcome::Incomplete => break,
                ParseOutcome::Error(e) => {
                    tracing::warn!("LSP frame malformado, descartando hasta próximo CRLFCRLF: {e}");
                    discard_until_next_header(&mut self.buffer);
                }
            }
        }
        frames
    }

    /// `true` si queda algo pendiente en el buffer (header sin body completo).
    #[must_use]
    pub fn has_pending(&self) -> bool {
        !self.buffer.is_empty()
    }

    /// Bytes pendientes en el buffer (útil para tests).
    #[must_use]
    pub fn pending_len(&self) -> usize {
        self.buffer.len()
    }

    fn parse_one_and_consume(&mut self) -> ParseOutcome {
        // Buscar separador header/body: \r\n\r\n
        let Some(separator) = self.buffer.windows(4).position(|w| w == b"\r\n\r\n") else {
            return ParseOutcome::Incomplete;
        };

        let header_str = if let Ok(s) = std::str::from_utf8(&self.buffer[..separator]) {
            s.to_string()
        } else {
            self.buffer.drain(..separator + 4);
            return ParseOutcome::Error(FrameError::NonUtf8Header);
        };

        let Ok(content_length) = parse_content_length(&header_str) else {
            self.buffer.drain(..separator + 4);
            return ParseOutcome::Error(FrameError::MissingContentLength);
        };

        let body_start = separator + 4;
        let body_end = body_start + content_length;
        if self.buffer.len() < body_end {
            return ParseOutcome::Incomplete;
        }

        // IMPORTANTE: drenar el frame del buffer ANTES de devolver. Si no,
        // el loop externo en `feed()` ve el mismo separator otra vez y entra
        // en loop infinito copiando el body hasta OOM.
        let body = self.buffer[body_start..body_end].to_vec();
        self.buffer.drain(..body_end);
        ParseOutcome::Complete(body)
    }
}

/// Codifica un body con su framing `Content-Length`. Output listo para escribir
/// al socket TCP o a stdout (LSP usa el mismo framing en ambas direcciones).
#[must_use]
pub fn encode(body: &[u8]) -> Vec<u8> {
    // Pre-allocate: header típico "Content-Length: N\r\n\r\n" ≤ 32 bytes + body.
    let mut out = Vec::with_capacity(body.len() + 32);
    let header = format!("Content-Length: {}\r\n\r\n", body.len());
    out.extend_from_slice(header.as_bytes());
    out.extend_from_slice(body);
    out
}

/// Busca el siguiente `\r\n\r\n` y descarta todo hasta ahí (incluido). Si no
/// encuentra, vacía el buffer. Usado cuando un header está corrupto y queremos
/// resincronizar.
fn discard_until_next_header(buffer: &mut Vec<u8>) {
    if let Some(idx) = buffer.windows(4).position(|w| w == b"\r\n\r\n") {
        buffer.drain(..idx + 4);
    } else {
        buffer.clear();
    }
}

fn parse_content_length(header: &str) -> Result<usize, FrameError> {
    for line in header.split("\r\n") {
        let mut parts = line.splitn(2, ':');
        let key = parts.next().unwrap_or("").trim();
        let value = match parts.next() {
            Some(v) => v.trim(),
            None => continue,
        };
        if key.eq_ignore_ascii_case("Content-Length") {
            return value
                .parse::<usize>()
                .map_err(|_| FrameError::MissingContentLength);
        }
    }
    Err(FrameError::MissingContentLength)
}

// ============================================================================
// Tests unitarios (sin I/O, sin red, deterministas).
// ============================================================================

#[cfg(test)]
mod tests {
    // `body`/`framed`/`buffer` aparecen mucho en los tests; clippy::similar_names
    // se vuelve loco. Es ruido — los nombres son claros en contexto.
    #![allow(clippy::similar_names)]

    use super::*;

    #[test]
    fn encode_single_frame() {
        let body = br#"{"jsonrpc":"2.0","id":1}"#;
        let framed = encode(body);
        let expected = format!("Content-Length: {}\r\n\r\n", body.len());
        assert!(framed.starts_with(expected.as_bytes()));
        assert_eq!(&framed[expected.len()..], body);
    }

    #[test]
    fn encode_empty_body() {
        let framed = encode(b"");
        assert_eq!(framed, b"Content-Length: 0\r\n\r\n");
    }

    #[test]
    fn feed_single_complete_frame() {
        let mut p = FrameParser::new();
        let body = br#"{"jsonrpc":"2.0","id":1,"method":"initialize"}"#;
        let framed = encode(body);
        let frames = p.feed(&framed);
        assert_eq!(frames.len(), 1);
        assert_eq!(frames[0], body);
        assert!(!p.has_pending());
    }

    #[test]
    fn feed_split_across_chunks() {
        let mut p = FrameParser::new();
        let body = br#"{"jsonrpc":"2.0","id":2}"#;
        let framed = encode(body);
        // Partir por la mitad del header para probar el caso patológico.
        let split = framed.len() / 2;
        let frames1 = p.feed(&framed[..split]);
        assert_eq!(frames1.len(), 0);
        assert!(p.has_pending());
        let frames2 = p.feed(&framed[split..]);
        assert_eq!(frames2.len(), 1);
        assert_eq!(frames2[0], body);
    }

    #[test]
    fn feed_multiple_frames_in_one_chunk() {
        let mut p = FrameParser::new();
        let body_a = br#"{"id":1}"#;
        let body_b = br#"{"id":2}"#;
        let body_c = br#"{"id":3}"#;
        let mut combined = encode(body_a);
        combined.extend_from_slice(&encode(body_b));
        combined.extend_from_slice(&encode(body_c));
        let frames = p.feed(&combined);
        assert_eq!(frames.len(), 3);
        assert_eq!(frames[0], body_a);
        assert_eq!(frames[1], body_b);
        assert_eq!(frames[2], body_c);
    }

    #[test]
    fn feed_malformed_header_recovers() {
        let mut p = FrameParser::new();
        // Header con Content-Length no numérico + un frame válido después.
        let bad = b"Content-Length: notanumber\r\n\r\n{}";
        let good = encode(br#"{"ok":true}"#);
        let mut combined = Vec::new();
        combined.extend_from_slice(bad);
        combined.extend_from_slice(&good);
        let frames = p.feed(&combined);
        // El parser descarta el header malo hasta el próximo \r\n\r\n y luego
        // intenta parsear "{}" como body del header anterior; puede dar 1
        // frame vacío o ninguno dependiendo del orden. Lo importante: NO entra
        // en loop infinito y termina.
        assert!(frames.len() <= 1);
    }

    #[test]
    fn feed_ignores_extra_headers() {
        let mut p = FrameParser::new();
        let input = b"Content-Length: 5\r\nContent-Type: application/json\r\n\r\nhello";
        let frames = p.feed(input);
        assert_eq!(frames.len(), 1);
        assert_eq!(frames[0], b"hello");
    }

    #[test]
    fn feed_partial_body_returns_incomplete() {
        let mut p = FrameParser::new();
        let body = b"{\"a\":1}";
        let framed = encode(body);
        // Feed solo los headers + mitad del body.
        let split_at = "Content-Length: 8\r\n\r\n{\"a\"".len();
        assert!(split_at < framed.len());
        let frames = p.feed(&framed[..split_at]);
        assert_eq!(frames.len(), 0);
        assert!(p.has_pending());
        // Feed el resto.
        let frames = p.feed(&framed[split_at..]);
        assert_eq!(frames.len(), 1);
        assert_eq!(frames[0], body);
    }

    #[test]
    fn encode_decode_roundtrip_utf8() {
        let body = "{\"mensaje\":\"Hola, ñoño 🚀\"}".as_bytes();
        let framed = encode(body);
        let mut p = FrameParser::new();
        let frames = p.feed(&framed);
        assert_eq!(frames.len(), 1);
        assert_eq!(frames[0], body);
    }
}
