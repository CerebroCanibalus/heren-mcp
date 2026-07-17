# syntax=docker/dockerfile:1
FROM python:3.11-slim-bookworm

# Variables de build
ARG GODOT_VERSION=4.6.1
ARG GODOT_RELEASE=stable
ARG GODOT_DIR=/opt/godot

# Instalar dependencias del sistema
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    unzip \
    libx11-6 \
    libxinerama1 \
    libxrandr2 \
    libgl1 \
    libpulse0 \
    libdbus-1-3 \
    libfontconfig1 \
    && rm -rf /var/lib/apt/lists/*

# Descargar e instalar Godot Engine 4.6.1 Linux headless
RUN mkdir -p ${GODOT_DIR} && \
    curl -fsSL \
      "https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}-${GODOT_RELEASE}/Godot_v${GODOT_VERSION}-${GODOT_RELEASE}_linux.x86_64.zip" \
      -o /tmp/godot.zip && \
    unzip -q /tmp/godot.zip -d ${GODOT_DIR} && \
    rm /tmp/godot.zip && \
    mv ${GODOT_DIR}/Godot_v${GODOT_VERSION}-${GODOT_RELEASE}_linux.x86_64 ${GODOT_DIR}/godot && \
    chmod +x ${GODOT_DIR}/godot

# Añadir Godot al PATH
ENV PATH="${GODOT_DIR}:${PATH}"
ENV GODOT_EXE="${GODOT_DIR}/godot"

# Crear directorio de trabajo
WORKDIR /app

# Copiar e instalar dependencias Python
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copiar codigo fuente
COPY . .
RUN pip install --no-cache-dir -e .

# Puerto para transporte HTTP (si se activa)
EXPOSE 8000

# Directorio para proyectos Godot de prueba / trabajo
RUN mkdir -p /projects

# Comando por defecto: MCP STDIO (compatible con MCPize deploy)
CMD ["python", "-m", "heren.server"]
