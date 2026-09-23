#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"

PK="${1:-LabSZ#sshd}"
VERBOSE="${2:-}"

contar() {
  aws dynamodb query \
    --table-name "$1" \
    --key-condition-expression "pk = :pk" \
    --expression-attribute-values "{\":pk\":{\"S\":\"$PK\"}}" \
    --select COUNT --query 'Count' --output text
}

NORMALES=$(contar "$LOGS_TABLE")
ALERTAS=$(contar "$ALERTS_TABLE")
TOTAL=$((NORMALES + ALERTAS))

echo "Query : pk = $PK        Hora: $(date +%H:%M:%S)"
echo ""
printf "  %-16s %6s\n" "$LOGS_TABLE" "$NORMALES"
printf "  %-16s %6s\n" "$ALERTS_TABLE" "$ALERTAS"
printf "  %-16s %6s\n" "TOTAL" "$TOTAL"

if [ "$VERBOSE" = "-v" ] && [ "$ALERTAS" -gt 0 ]; then
  echo ""
  echo "Ultimas alertas:"
  aws dynamodb query \
    --table-name "$ALERTS_TABLE" \
    --key-condition-expression "pk = :pk" \
    --expression-attribute-values "{\":pk\":{\"S\":\"$PK\"}}" \
    --no-scan-index-forward --max-items 5 \
    --query 'Items[].{Tipo:alert_type.S,Hora:timestamp.S,Log:log.S}' \
    --output table
fi
