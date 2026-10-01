#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"

TOP="${1:-5}"

if [ -f build/api-endpoint.txt ]; then
  ENDPOINT=$(cat build/api-endpoint.txt)
else
  API_ID=$(aws apigatewayv2 get-apis --query "Items[?Name=='$API_NAME'].ApiId | [0]" --output text)
  if [ "$API_ID" = "None" ] || [ -z "$API_ID" ]; then
    echo "No existe la API $API_NAME. Corre ./scripts/create-http-api.sh" >&2
    exit 1
  fi
  ENDPOINT=$(aws apigatewayv2 get-api --api-id "$API_ID" --query 'ApiEndpoint' --output text)
fi

mostrar() {
  echo "--> GET $1"
  curl -s "$1" | python3 -m json.tool || echo "(respuesta no es JSON valido)"
  echo ""
}

mostrar "$ENDPOINT/alerts"
mostrar "$ENDPOINT/alerts?severity=HIGH"
mostrar "$ENDPOINT/logs?top=$TOP"
