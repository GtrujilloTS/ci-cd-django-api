#!/bin/bash
############################################################
# Script Name:      setup-dockerization.sh
# Author:           Giovanni Trujillo Silvas (gtrujill0@outlook.com)
# Created:          2025-05-24
# Last Modified:    2025-05-26
# Description:      Automate Dockerization of Projects
############################################################

DOCKERFILE="Dockerfile"
COMPOSEFILE="docker-compose.yml"
DOCKERIGNORE=".dockerignore"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
API_ID="$(basename "$SCRIPT_DIR" | sed 's/[^a-zA-Z0-9_]/_/g')"
PORT_START=8000
PORT_END=8999

# Verificación de dependencias
for cmd in ss docker docker-compose curl python3; do
    if ! command -v $cmd &> /dev/null; then
        echo "❌ '$cmd' no está instalado. Instálalo antes de continuar."
        exit 1
    fi
done


# Verificación de archivos existentes
for file in "$DOCKERFILE" "$COMPOSEFILE" "$DOCKERIGNORE"; do
    if [ -f "$file" ]; then
        read -p "⚠️  El archivo '$file' ya existe. ¿Deseas sobrescribirlo? [s/N]: " answer
        if [[ ! "$answer" =~ ^[Ss]$ ]]; then
            echo "❌ Cancelado por el usuario."
            exit 1
        fi
    fi
done

# Buscar un puerto libre
find_free_port() {
    local start=$1
    local end=$2
    for ((port=start; port<=end; port++)); do
        if ! ss -tuln | grep -q ":$port\b"; then
            echo "$port"
            return
        fi
    done
    echo "❌ No se encontró puerto libre entre $start y $end" >&2
    exit 1
}

PORT_LOCAL=$(find_free_port $PORT_START $PORT_END)
echo "📡 Puerto local disponible encontrado: $PORT_LOCAL"

# Docker ignore
echo "🛠️ Generando archivo $DOCKERIGNORE..."
cat <<EOF > $DOCKERIGNORE
# Ignorar archivos y directorios innecesarios para Docker
__pycache__/
*.py[cod]
*.pyo
*.pyd
*.log
*.sqlite3
*.db
*.DS_Store
*.egg-info/
*.egg
*.zip
*.tar.gz
*.tar
*.gz
*.tgz
*.whl
*.pyc
*.coverage
*.mypy_cache/
*.pytest_cache/
*.tox/
*.venv/
*.env.local
EOF

echo "✅ .dockerignore generado."


# Generación del Dockerfile
echo "🛠️ Generando archivo $DOCKERFILE..."

REQUIREMENTS=""
[ -f "requirements.txt" ] && REQUIREMENTS+="RUN pip install --no-cache-dir -r requirements.txt"
[ -f "pyproject.toml" ] && REQUIREMENTS+="RUN pip install ."


{
cat <<EOF
# Imagen base
FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1

WORKDIR /$API_ID

RUN apt-get update && apt-get install -y \\
    build-essential \\
    libpq-dev \\
    unixodbc \\
    curl \\
    && rm -rf /var/lib/apt/lists/*

RUN curl -sSL -O https://packages.microsoft.com/config/debian/12/packages-microsoft-prod.deb && \\
    dpkg -i packages-microsoft-prod.deb && \\
    rm packages-microsoft-prod.deb

RUN apt-get update && \\
    ACCEPT_EULA=Y apt-get install -y msodbcsql17

RUN rm -rf /var/lib/apt/lists/*

COPY . .

RUN pip install gunicorn
RUN pip install --upgrade pip


EOF

# Insertar el bloque COPY con saltos reales
echo -e "$REQUIREMENTS"

cat <<EOF

EXPOSE $PORT_LOCAL

CMD ["gunicorn", "$API_ID.wsgi:application", "--bind", "0.0.0.0:$PORT_LOCAL", "--workers", "3"]

EOF
} > "$DOCKERFILE"

echo "✅ Dockerfile generado."

# Docker Compose
echo "🛠️ Generando archivo $COMPOSEFILE..."

cat <<EOF > $COMPOSEFILE
version: '3.9'

services:
  api:
    container_name: "$API_ID"
    network_mode: host
    build: .
    command: gunicorn $API_ID.wsgi:application --bind 0.0.0.0:$PORT_LOCAL
    volumes:
      - .:/$API_ID
    env_file:
      - ../.env
EOF

echo "✅ docker-compose.yml generado con puerto: $PORT_LOCAL"
echo "🚀 Ejecuta desde el directorio donde está este script:"
echo "   make up"
echo "   o"
echo "   docker-compose up -d --build"
