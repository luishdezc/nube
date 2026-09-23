#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"

SLEEP_SECONDS="${1:-30}"
DIR="${2:-$BATCHES_DIR}"

if ! [[ "$SLEEP_SECONDS" =~ ^[0-9]+$ ]]; then
  echo "Uso: $0 <segundos> [carpeta_batches]" >&2
  exit 1
fi

if [ ! -d "$DIR" ]; then
  echo "No existe la carpeta $DIR. Corre primero ./scripts/split-log.sh" >&2
  exit 1
fi

TOTAL=$(find "$DIR" -maxdepth 1 -name '*.log' | wc -l | tr -d ' ')

if [ "$TOTAL" -eq 0 ]; then
  echo "No hay batches .log en $DIR" >&2
  exit 1
fi

echo "Enviando $TOTAL batches a s3://$BUCKET_NAME/$INPUT_PREFIX cada $SLEEP_SECONDS s"
echo ""

I=0
for batch in "$DIR"/*.log; do
  I=$((I + 1))
  echo "[$I/$TOTAL] $(basename "$batch")"

  aws s3 cp "$batch" "s3://$BUCKET_NAME/$INPUT_PREFIX" --region "$REGION"

  if [ "$I" -lt "$TOTAL" ]; then
    sleep "$SLEEP_SECONDS"
  fi
done

echo ""
echo "Listo. Revisa los logs almacenados con:"
echo "  ./scripts/query-logs.sh LabSZ#sshd -v"
