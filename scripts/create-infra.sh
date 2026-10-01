#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"

echo "=============================================="
echo " Creando infraestructura"
echo "   Perfil  : $AWS_PROFILE"
echo "   Region  : $REGION"
echo "   Bucket  : s3://$BUCKET_NAME"
echo "   Tablas  : $LOGS_TABLE, $ALERTS_TABLE"
echo "   Lambdas : $PARSER_FUNCTION, $STARTER_FUNCTION, $ALERTS_FUNCTION, $LOGS_FUNCTION"
echo "   Maquina : $STATE_MACHINE_NAME"
echo "   API     : $API_NAME"
echo "=============================================="
echo ""

echo "--- 1/6 Bucket de S3 ---"
"$SCRIPT_DIR/create-s3-bucket.sh"
echo ""

echo "--- 2/6 Tablas de DynamoDB ---"
"$SCRIPT_DIR/create-dynamodb-tables.sh"
echo ""

echo "--- 3/6 Lambdas ---"
"$SCRIPT_DIR/package-lambdas.sh"
"$SCRIPT_DIR/deploy-lambdas.sh"
echo ""

echo "--- 4/6 Maquina de estados ---"
"$SCRIPT_DIR/create-state-machine.sh"
echo ""

echo "--- 5/6 Trigger de S3 ---"
"$SCRIPT_DIR/configure-trigger.sh"
echo ""

echo "--- 6/6 HTTP API ---"
"$SCRIPT_DIR/create-http-api.sh"
echo ""

echo "=============================================="
echo " Infraestructura lista."
echo ""
echo " Siguiente paso:"
echo "   ./scripts/generate-log.sh 200"
echo "   ./scripts/split-log.sh data/openssh.log batches 1024"
echo "   ./start_logging.sh 60"
echo "   ./scripts/test-api.sh 5"
echo "=============================================="
