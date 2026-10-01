#!/bin/bash
set -e

LINEAS="${1:-0}"
SALIDA="${2:-data/openssh.log}"
URL="https://raw.githubusercontent.com/logpai/loghub/master/OpenSSH/OpenSSH_2k.log"

mkdir -p "$(dirname "$SALIDA")"

echo "Descargando el log de loghub (OpenSSH)..."
if command -v curl >/dev/null 2>&1; then
  curl -sL "$URL" -o "$SALIDA.tmp"
elif command -v wget >/dev/null 2>&1; then
  wget -q "$URL" -O "$SALIDA.tmp"
else
  echo "No hay curl ni wget. Descarga el archivo a mano:" >&2
  echo "  $URL" >&2
  echo "y guardalo como $SALIDA" >&2
  exit 1
fi

if [ ! -s "$SALIDA.tmp" ]; then
  echo "La descarga fallo o quedo vacia." >&2
  rm -f "$SALIDA.tmp"
  exit 1
fi

tr -d '\r' < "$SALIDA.tmp" > "$SALIDA"
rm -f "$SALIDA.tmp"

if [ "$LINEAS" -gt 0 ] 2>/dev/null; then
  head -n "$LINEAS" "$SALIDA" > "$SALIDA.cut" && mv "$SALIDA.cut" "$SALIDA"
fi

TOTAL=$(wc -l < "$SALIDA" | tr -d ' ')
BYTES=$(wc -c < "$SALIDA" | tr -d ' ')
BATCHES=$(( (BYTES + 1023) / 1024 ))

echo "$SALIDA: $TOTAL lineas, $BYTES bytes (~$BATCHES batches de 1KB)"
echo "  sospechosas: $(grep -cE 'Invalid user|POSSIBLE BREAK-IN ATTEMPT' "$SALIDA")"
echo ""
echo "Siguiente paso:"
echo "  ./scripts/split-log.sh $SALIDA batches 1024"
