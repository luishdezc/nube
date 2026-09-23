#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"

crear_tabla() {
  local tabla="$1"

  if aws dynamodb describe-table --table-name "$tabla" >/dev/null 2>&1; then
    echo "  $tabla ya existe, se reutiliza."
  else
    echo "  Creando $tabla..."
    aws dynamodb create-table \
      --table-name "$tabla" \
      --attribute-definitions \
        AttributeName=pk,AttributeType=S \
        AttributeName=sk,AttributeType=S \
      --key-schema \
        AttributeName=pk,KeyType=HASH \
        AttributeName=sk,KeyType=RANGE \
      --billing-mode PAY_PER_REQUEST \
      --no-cli-pager >/dev/null

    aws dynamodb wait table-exists --table-name "$tabla"
  fi

  aws dynamodb update-time-to-live \
    --table-name "$tabla" \
    --time-to-live-specification "Enabled=true,AttributeName=expires_at" \
    --no-cli-pager >/dev/null 2>&1 || true
}

echo "Creando tablas de DynamoDB (TTL de $TTL_DAYS dias):"
crear_tabla "$LOGS_TABLE"
crear_tabla "$ALERTS_TABLE"

echo ""
echo "Tablas listas:"
for tabla in "$LOGS_TABLE" "$ALERTS_TABLE"; do
  aws dynamodb describe-table --table-name "$tabla" \
    --query 'Table.{Nombre:TableName,Estado:TableStatus,Items:ItemCount}' \
    --output table
done
