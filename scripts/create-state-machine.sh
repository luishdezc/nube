#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"

ASL_SRC="statemachine/logging-system.asl.json"
ASL_OUT="build/logging-system.asl.json"

if [ ! -f "$ASL_SRC" ]; then
  echo "No existe $ASL_SRC" >&2
  exit 1
fi

LAB_ROLE_ARN=$(aws iam get-role --role-name LabRole --query 'Role.Arn' --output text)

if ! aws iam get-role --role-name LabRole --query 'Role.AssumeRolePolicyDocument' \
     --output json | grep -q "states.amazonaws.com"; then
  echo "AVISO: LabRole no parece confiar en states.amazonaws.com." >&2
  echo "Si el siguiente paso falla, hay que crear un rol para Step Functions." >&2
fi

PARSE_BATCH_ARN=$(aws lambda get-function --function-name "$PARSER_FUNCTION" \
  --query 'Configuration.FunctionArn' --output text)

echo "Generando la definicion:"
echo "  parse_batch    -> $PARSE_BATCH_ARN"
echo "  tabla normales -> $LOGS_TABLE"
echo "  tabla alertas  -> $ALERTS_TABLE"

mkdir -p build
PARSE_BATCH_ARN="$PARSE_BATCH_ARN" LOGS_TABLE="$LOGS_TABLE" ALERTS_TABLE="$ALERTS_TABLE" \
python3 - "$ASL_SRC" "$ASL_OUT" <<'PY'
import json, os, sys

origen, destino = sys.argv[1], sys.argv[2]
texto = open(origen, encoding="utf-8").read()

for clave in ("PARSE_BATCH_ARN", "LOGS_TABLE", "ALERTS_TABLE"):
    texto = texto.replace("${" + clave + "}", os.environ[clave])

# Si quedo algun placeholder sin sustituir, mejor fallar aqui que en AWS.
if "${" in texto:
    sys.exit(f"Quedaron placeholders sin sustituir en {destino}")

json.loads(texto)  # valida que siga siendo JSON valido
open(destino, "w", encoding="utf-8").write(texto)
print(f"  {destino} generado y validado")
PY

SM_ARN=$(aws stepfunctions list-state-machines \
  --query "stateMachines[?name=='$STATE_MACHINE_NAME'].stateMachineArn | [0]" \
  --output text 2>/dev/null || echo "None")

if [ "$SM_ARN" != "None" ] && [ -n "$SM_ARN" ]; then
  echo "La maquina de estados ya existe, actualizando definicion..."
  aws stepfunctions update-state-machine \
    --state-machine-arn "$SM_ARN" \
    --definition "file://$ASL_OUT" \
    --role-arn "$LAB_ROLE_ARN" \
    --no-cli-pager >/dev/null
else
  echo "Creando la maquina de estados $STATE_MACHINE_NAME..."
  SM_ARN=$(aws stepfunctions create-state-machine \
    --name "$STATE_MACHINE_NAME" \
    --definition "file://$ASL_OUT" \
    --role-arn "$LAB_ROLE_ARN" \
    --type STANDARD \
    --query 'stateMachineArn' --output text)
fi

echo "  $SM_ARN"

# start_execution necesita saber a que maquina llamar.
echo "Pasando el ARN a $STARTER_FUNCTION..."
aws lambda update-function-configuration \
  --function-name "$STARTER_FUNCTION" \
  --environment "Variables={INPUT_PREFIX=$INPUT_PREFIX,STATE_MACHINE_ARN=$SM_ARN}" \
  --no-cli-pager >/dev/null

aws lambda wait function-updated --function-name "$STARTER_FUNCTION"

echo "Maquina de estados lista."
