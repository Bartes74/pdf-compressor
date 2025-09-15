#!/usr/bin/env bash

set -euo pipefail

# start.sh — uruchamia wszystkie komponenty projektu (PWA w Docker + Electron)
# Opcje:
#   --no-docker       Nie uruchamiaj kontenera Docker (tylko Electron)
#   --no-electron     Nie uruchamiaj Electron (tylko Docker/PWA)
#   --port=N          Port hosta dla PWA (domyślnie 8081)
#   --image-tag=TAG   Tag obrazu Docker (domyślnie pdfcompressor:local)

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
PWA_DIR="$ROOT_DIR/pdf-compressor-pwa"
PORT="8081"
IMAGE_TAG="pdfcompressor:local"
RUN_DOCKER=1
RUN_ELECTRON=1

log() { printf "[start] %s\n" "$*"; }
err() { printf "[start][ERROR] %s\n" "$*" >&2; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-docker) RUN_DOCKER=0; shift ;;
    --no-electron) RUN_ELECTRON=0; shift ;;
    --port=*) PORT="${1#*=}"; shift ;;
    --image-tag=*) IMAGE_TAG="${1#*=}"; shift ;;
    -h|--help)
      cat <<EOF
Usage: ./start.sh [--no-docker] [--no-electron] [--port=8081] [--image-tag=pdfcompressor:local]
EOF
      exit 0
      ;;
    *) err "Nieznana opcja: $1"; exit 1 ;;
  esac
done

require() {
  if ! command -v "$1" >/dev/null 2>&1; then
    err "Wymagany program nie znaleziony: $1"
    exit 1
  fi
}

is_port_free() {
  local port="$1"
  if command -v lsof >/dev/null 2>&1; then
    ! lsof -i ":${port}" >/dev/null 2>&1
  else
    # Fallback best-effort
    return 0
  fi
}

start_docker() {
  require docker

  if ! is_port_free "$PORT"; then
    err "Port ${PORT} jest zajęty. Użyj --port=INNY_PORT lub zwolnij port."
    exit 1
  fi

  # Zbuduj obraz jeśli nie istnieje
  if ! docker image inspect "$IMAGE_TAG" >/dev/null 2>&1; then
    log "Buduję obraz Docker ($IMAGE_TAG) z $PWA_DIR…"
    docker build -t "$IMAGE_TAG" -f "$PWA_DIR/Dockerfile" "$PWA_DIR"
  else
    log "Obraz $IMAGE_TAG już istnieje — pomijam build."
  fi

  # Zatrzymaj stary kontener (jeżeli istnieje)
  if docker ps -a --format '{{.Names}}' | grep -q '^pdfcompressor-web$'; then
    log "Zatrzymuję poprzedni kontener pdfcompressor-web…"
    docker rm -f pdfcompressor-web >/dev/null 2>&1 || true
  fi

  log "Uruchamiam PWA w kontenerze (http://localhost:${PORT})…"
  docker run -d --rm \
    --name pdfcompressor-web \
    -p "${PORT}:80" \
    "$IMAGE_TAG" >/dev/null

  log "Kontener działa: pdfcompressor-web (port ${PORT})"
}

start_electron() {
  require node
  require npm

  log "Buduję i uruchamiam aplikację Electron w tle…"
  (
    cd "$PWA_DIR"
    # Szybka walidacja node_modules — w razie potrzeby możesz odkomentować npm ci
    # [[ -d node_modules ]] || npm ci --prefer-offline --no-audit --no-fund
    npm run electron:dev >/tmp/pdfcompressor-electron.log 2>&1 &
    echo $! > /tmp/pdfcompressor-electron.pid
  )
  log "Electron PID: $(cat /tmp/pdfcompressor-electron.pid) (log: /tmp/pdfcompressor-electron.log)"
}

open_browser() {
  local url="http://localhost:${PORT}"
  log "Otwieram przeglądarkę: ${url}"
  if command -v open >/dev/null 2>&1; then
    open "$url" || true
  elif command -v xdg-open >/dev/null 2>&1; then
    xdg-open "$url" || true
  else
    log "Otwórz ręcznie: $url"
  fi
}

main() {
  log "Startuję komponenty… (port=${PORT}, image=${IMAGE_TAG})"

  if [[ "$RUN_DOCKER" -eq 1 ]]; then
    start_docker
  else
    log "Pomijam Docker (na żądanie)."
  fi

  if [[ "$RUN_ELECTRON" -eq 1 ]]; then
    start_electron
  else
    log "Pomijam Electron (na żądanie)."
  fi

  if [[ "$RUN_DOCKER" -eq 1 ]]; then
    open_browser
  fi

  log "Wszystko odpalone. Zdrowie! (whisky opcjonalna)"
}

main "$@"




