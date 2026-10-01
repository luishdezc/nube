#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"

echo "Esto va a borrar:"
echo "  - bucket s3://$BUCKET_NAME (con todo su contenido)"
echo "  - tablas DynamoDB $LOGS_TABLE y $ALERTS_TABLE (con todos los registros)"
echo "  - maquina de estados $STATE_MACHINE_NAME"
echo "  - HTTP API $API_NAME"
echo "  - lambdas $PARSER_FUNCTION, $STARTER_FUNCTION, $ALERTS_FUNCTION y $LOGS_FUNCTION"
read -p "Continuar? (y/N) " -n 1 -r
echo
[[ $REPLY =~ ^[Yy]$ ]] || exit 0

echo "Vaciando y borrando el bucket..."
aws s3 rm "s3://$BUCKET_NAME" --recursive || true
aws s3 rb "s3://$BUCKET_NAME" --region "$REGION" || true

echo "Borrando las tablas de DynamoDB..."
for tabla in "$LOGS_TABLE" "$ALERTS_TABLE"; do
  aws dynamodb delete-table --table-name "$tabla" --no-cli-pager >/dev/null 2>&1 || true
done

echo "Borrando la HTTP API..."
API_ID=$(aws apigatewayv2 get-apis --query "Items[?Name=='$API_NAME'].ApiId | [0]" \
  --output text 2>/dev/null || echo "None")
if [ "$API_ID" != "None" ] && [ -n "$API_ID" ]; then
  aws apigatewayv2 delete-api --api-id "$API_ID" || true
fi

echo "Borrando la maquina de estados..."
SM_ARN=$(aws stepfunctions list-state-machines \
  --query "stateMachines[?name=='$STATE_MACHINE_NAME'].stateMachineArn | [0]" \
  --output text 2>/dev/null || echo "None")
if [ "$SM_ARN" != "None" ] && [ -n "$SM_ARN" ]; then
  aws stepfunctions delete-state-machine --state-machine-arn "$SM_ARN" || true
fi

echo "Borrando las lambdas..."
for fn in "$PARSER_FUNCTION" "$STARTER_FUNCTION" "$ALERTS_FUNCTION" "$LOGS_FUNCTION"; do
  aws lambda delete-function --function-name "$fn" >/dev/null 2>&1 || true
  aws logs delete-log-group --log-group-name "/aws/lambda/$fn" >/dev/null 2>&1 || true
done

echo "Limpiando archivos locales..."
rm -rf build ./*.zip "$BATCHES_DIR"

echo "Todo eliminado."
