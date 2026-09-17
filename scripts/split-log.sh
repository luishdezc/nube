
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"

INPUT_FILE="${1:-data/sample.log}"
OUT_DIR="${2:-$BATCHES_DIR}"
LIMIT="${3:-$BATCH_SIZE}"

if [ ! -f "$INPUT_FILE" ]; then
  echo "No existe el archivo $INPUT_FILE" >&2
  exit 1
fi

rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR"

# LC_ALL=C hace que ${#line} cuente bytes y no caracteres
export LC_ALL=C

TS=$(date +%s)
LAST_TS=0
COUNT=0
BYTES=0
CURRENT=""

nuevo_batch() {
  # El timestamp debe ser unico. Como varios batches se crean dentro del
  # mismo segundo, si se repite simplemente avanzamos un segundo.
  TS=$(date +%s)
  if [ "$TS" -le "$LAST_TS" ]; then
    TS=$((LAST_TS + 1))
  fi
  LAST_TS=$TS

  CURRENT="$OUT_DIR/openssh-${TS}.log"
  : > "$CURRENT"
  BYTES=0
  COUNT=$((COUNT + 1))
}

nuevo_batch

while IFS= read -r line || [ -n "$line" ]; do
  printf '%s\n' "$line" >> "$CURRENT"
  # +1 por el salto de linea
  BYTES=$((BYTES + ${#line} + 1))

  if [ "$BYTES" -ge "$LIMIT" ]; then
    echo "  $CURRENT ($BYTES bytes)"
    nuevo_batch
  fi
done < "$INPUT_FILE"

# El ultimo batch puede quedar vacio si el corte cayo justo al final
if [ ! -s "$CURRENT" ]; then
  rm -f "$CURRENT"
  COUNT=$((COUNT - 1))
else
  echo "  $CURRENT ($BYTES bytes)"
fi

echo ""
echo "$COUNT batches creados en $OUT_DIR/"
