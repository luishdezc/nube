#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"

echo "Dando permiso a S3 para invocar $STARTER_FUNCTION..."
aws lambda add-permission \
  --function-name "$STARTER_FUNCTION" \
  --statement-id s3-trigger \
  --action lambda:InvokeFunction \
  --principal s3.amazonaws.com \
  --source-arn "arn:aws:s3:::$BUCKET_NAME" \
  --no-cli-pager >/dev/null 2>&1 || echo "  El permiso ya existia."

FUNCTION_ARN=$(aws lambda get-function --function-name "$STARTER_FUNCTION" \
  --query 'Configuration.FunctionArn' --output text)

mkdir -p build
cat > build/notification.json <<EOF
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
  --notification-configuration file://build/notification.json

echo "Trigger listo."
