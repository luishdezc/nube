#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"

ATRIBUTOS="AttributeName=pk,AttributeType=S AttributeName=sk,AttributeType=S \
AttributeName=gsi_pk,AttributeType=S AttributeName=s3_last_modified,AttributeType=S"

LLAVES="AttributeName=pk,KeyType=HASH AttributeName=sk,KeyType=RANGE"

gsi_json() {
  cat <<EOF
[{
  "IndexName": "$GSI_NAME",
  "KeySchema": [
    {"AttributeName": "gsi_pk", "KeyType": "HASH"},
    {"AttributeName": "s3_last_modified", "KeyType": "RANGE"}
  ],
  "Projection": {"ProjectionType": "ALL"}
}]
EOF
}

crear_tabla() {
  local tabla="$1"

  if aws dynamodb describe-table --table-name "$tabla" >/dev/null 2>&1; then
    echo "  $tabla ya existe."

    if aws dynamodb describe-table --table-name "$tabla" \
         --query "Table.GlobalSecondaryIndexes[?IndexName=='$GSI_NAME'] | [0]" \
         --output text 2>/dev/null | grep -q "$GSI_NAME"; then
      echo "  El indice $GSI_NAME ya existe."
    else
      echo "  Agregando el indice $GSI_NAME..."
      mkdir -p build
      echo "[{\"Create\": $(gsi_json | python3 -c 'import json,sys; print(json.dumps(json.load(sys.stdin)[0]))')}]" \
        > "build/gsi-$tabla.json"
      aws dynamodb update-table \
        --table-name "$tabla" \
        --attribute-definitions $ATRIBUTOS \
        --global-secondary-index-updates "file://build/gsi-$tabla.json" \
        --no-cli-pager >/dev/null
      echo "  (el indice tarda un par de minutos en quedar activo)"
    fi
  else
    echo "  Creando $tabla con el indice $GSI_NAME..."
    mkdir -p build
    gsi_json > "build/gsi-$tabla.json"
    aws dynamodb create-table \
      --table-name "$tabla" \
      --attribute-definitions $ATRIBUTOS \
      --key-schema $LLAVES \
      --global-secondary-indexes "file://build/gsi-$tabla.json" \
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
echo "Esperando a que los indices esten activos..."
for tabla in "$LOGS_TABLE" "$ALERTS_TABLE"; do
  for _ in $(seq 1 60); do
    ESTADO=$(aws dynamodb describe-table --table-name "$tabla" \
      --query "Table.GlobalSecondaryIndexes[?IndexName=='$GSI_NAME'].IndexStatus | [0]" \
      --output text 2>/dev/null || echo "NONE")
    [ "$ESTADO" = "ACTIVE" ] && break
    sleep 5
  done
  echo "  $tabla / $GSI_NAME: $ESTADO"
done
