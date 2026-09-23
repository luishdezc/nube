#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"

LAB_ROLE_ARN=$(aws iam get-role --role-name LabRole --query 'Role.Arn' --output text)

SM_ARN=$(aws stepfunctions list-state-machines \
  --query "stateMachines[?name=='$STATE_MACHINE_NAME'].stateMachineArn | [0]" \
  --output text 2>/dev/null || echo "None")
[ "$SM_ARN" = "None" ] && SM_ARN=""

desplegar() {
  local nombre="$1"
  local zip="$2"
  local envvars="$3"

  if [ ! -f "$zip" ]; then
    echo "No existe $zip. Corre primero ./scripts/package-lambdas.sh" >&2
    exit 1
  fi

  if aws lambda get-function --function-name "$nombre" >/dev/null 2>&1; then
    echo "  $nombre ya existe, actualizando codigo..."
    aws lambda update-function-code \
      --function-name "$nombre" \
      --zip-file "fileb://$zip" \
      --no-cli-pager >/dev/null
  else
    echo "  Creando $nombre..."
    aws lambda create-function \
      --function-name "$nombre" \
      --runtime "$RUNTIME" \
      --role "$LAB_ROLE_ARN" \
      --handler lambda_function.lambda_handler \
      --zip-file "fileb://$zip" \
      --no-cli-pager >/dev/null
    aws lambda wait function-active --function-name "$nombre"
  fi

  aws lambda wait function-updated --function-name "$nombre"

  aws lambda update-function-configuration \
    --function-name "$nombre" \
    --memory-size 256 \
    --timeout 30 \
    --environment "Variables={$envvars}" \
    --no-cli-pager >/dev/null

  aws lambda wait function-updated --function-name "$nombre"
  echo "  $nombre listo."
}

echo "Desplegando lambdas:"
desplegar "$PARSER_FUNCTION" "$PARSER_FUNCTION.zip" \
  "INPUT_PREFIX=$INPUT_PREFIX,LOG_YEAR=$LOG_YEAR,TTL_DAYS=$TTL_DAYS"

desplegar "$STARTER_FUNCTION" "$STARTER_FUNCTION.zip" \
  "INPUT_PREFIX=$INPUT_PREFIX,STATE_MACHINE_ARN=$SM_ARN"

if [ -z "$SM_ARN" ]; then
  echo ""
  echo "Nota: la maquina de estados todavia no existe, asi que start_execution"
  echo "quedo sin STATE_MACHINE_ARN. Lo llena ./scripts/create-state-machine.sh"
fi
