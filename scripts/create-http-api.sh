#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"

CUENTA=$(aws sts get-caller-identity --query Account --output text)

API_ID=$(aws apigatewayv2 get-apis \
  --query "Items[?Name=='$API_NAME'].ApiId | [0]" --output text 2>/dev/null || echo "None")

if [ "$API_ID" = "None" ] || [ -z "$API_ID" ]; then
  echo "Creando la HTTP API $API_NAME..."
  API_ID=$(aws apigatewayv2 create-api \
    --name "$API_NAME" \
    --protocol-type HTTP \
    --query 'ApiId' --output text)
else
  echo "La API $API_NAME ya existe ($API_ID), se reutiliza."
fi

conectar_ruta() {
  local metodo_ruta="$1"
  local funcion="$2"

  local fn_arn
  fn_arn=$(aws lambda get-function --function-name "$funcion" \
    --query 'Configuration.FunctionArn' --output text)

  local ruta_id
  ruta_id=$(aws apigatewayv2 get-routes --api-id "$API_ID" \
    --query "Items[?RouteKey=='$metodo_ruta'].RouteId | [0]" --output text)
  if [ "$ruta_id" != "None" ] && [ -n "$ruta_id" ]; then
    aws apigatewayv2 delete-route --api-id "$API_ID" --route-id "$ruta_id"
  fi

  local integracion_id
  integracion_id=$(aws apigatewayv2 create-integration \
    --api-id "$API_ID" \
    --integration-type AWS_PROXY \
    --integration-uri "$fn_arn" \
    --payload-format-version 2.0 \
    --query 'IntegrationId' --output text)

  aws apigatewayv2 create-route \
    --api-id "$API_ID" \
    --route-key "$metodo_ruta" \
    --target "integrations/$integracion_id" >/dev/null

  aws lambda add-permission \
    --function-name "$funcion" \
    --statement-id "apigw-$(echo "$metodo_ruta" | tr ' /' '--')" \
    --action lambda:InvokeFunction \
    --principal apigateway.amazonaws.com \
    --source-arn "arn:aws:execute-api:$REGION:$CUENTA:$API_ID/*/*" \
    --no-cli-pager >/dev/null 2>&1 || true

  echo "  $metodo_ruta -> $funcion"
}

echo "Conectando rutas:"
conectar_ruta "GET /alerts" "$ALERTS_FUNCTION"
conectar_ruta "GET /logs" "$LOGS_FUNCTION"

if ! aws apigatewayv2 get-stage --api-id "$API_ID" --stage-name '$default' >/dev/null 2>&1; then
  echo "Creando el stage \$default..."
  aws apigatewayv2 create-stage \
    --api-id "$API_ID" \
    --stage-name '$default' \
    --auto-deploy >/dev/null
fi

ENDPOINT=$(aws apigatewayv2 get-api --api-id "$API_ID" --query 'ApiEndpoint' --output text)

mkdir -p build
echo "$ENDPOINT" > build/api-endpoint.txt

echo ""
echo "API lista:"
echo "  $ENDPOINT/alerts"
echo "  $ENDPOINT/logs?top=5"
