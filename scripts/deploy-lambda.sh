
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"

ZIP_FILE="$FUNCTION_NAME.zip"

if [ ! -f "$ZIP_FILE" ]; then
  echo "No existe $ZIP_FILE. Corre primero ./scripts/package-lambda.sh" >&2
  exit 1
fi

LAB_ROLE_ARN=$(aws iam get-role --role-name LabRole --query 'Role.Arn' --output text)

if aws lambda get-function --function-name "$FUNCTION_NAME" >/dev/null 2>&1; then
  echo "La lambda ya existe, actualizando codigo..."
  aws lambda update-function-code \
    --function-name "$FUNCTION_NAME" \
    --zip-file "fileb://$ZIP_FILE" \
    --no-cli-pager >/dev/null

  aws lambda wait function-updated --function-name "$FUNCTION_NAME"
else
  echo "Creando lambda $FUNCTION_NAME..."
  aws lambda create-function \
    --function-name "$FUNCTION_NAME" \
    --runtime "$RUNTIME" \
    --role "$LAB_ROLE_ARN" \
    --handler lambda_function.lambda_handler \
    --zip-file "fileb://$ZIP_FILE" \
    --no-cli-pager >/dev/null

  aws lambda wait function-active --function-name "$FUNCTION_NAME"
fi

echo "Configurando memoria, timeout y variables de entorno..."
aws lambda update-function-configuration \
  --function-name "$FUNCTION_NAME" \
  --memory-size 256 \
  --timeout 30 \
  --environment "Variables={INPUT_PREFIX=$INPUT_PREFIX,OUTPUT_PREFIX=$OUTPUT_PREFIX}" \
  --no-cli-pager >/dev/null

aws lambda wait function-updated --function-name "$FUNCTION_NAME"

echo "Dando permiso a S3 para invocar la lambda..."
aws lambda add-permission \
  --function-name "$FUNCTION_NAME" \
  --statement-id s3-trigger \
  --action lambda:InvokeFunction \
  --principal s3.amazonaws.com \
  --source-arn "arn:aws:s3:::$BUCKET_NAME" \
  --no-cli-pager >/dev/null 2>&1 || echo "  El permiso ya existia."

FUNCTION_ARN=$(aws lambda get-function --function-name "$FUNCTION_NAME" \
  --query 'Configuration.FunctionArn' --output text)

cat > notification.json <<EOF
{
  "LambdaFunctionConfigurations": [
    {
      "LambdaFunctionArn": "${FUNCTION_ARN}",
      "Events": ["s3:ObjectCreated:*"],
      "Filter": {
        "Key": {
          "FilterRules": [
            { "Name": "prefix", "Value": "${INPUT_PREFIX}" },
            { "Name": "suffix", "Value": ".log" }
          ]
        }
      }
    }
  ]
}
EOF

echo "Configurando el evento ObjectCreated en s3://$BUCKET_NAME/$INPUT_PREFIX"
aws s3api put-bucket-notification-configuration \
  --bucket "$BUCKET_NAME" \
  --notification-configuration file://notification.json

rm -f notification.json

echo "Deploy completo."
