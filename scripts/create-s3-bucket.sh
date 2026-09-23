#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"

echo "Creando bucket s3://$BUCKET_NAME en $REGION"

if aws s3api head-bucket --bucket "$BUCKET_NAME" 2>/dev/null; then
  echo "El bucket ya existe, se reutiliza."
else
  aws s3 mb "s3://$BUCKET_NAME" --region "$REGION"
fi

aws s3api put-object --bucket "$BUCKET_NAME" --key "$INPUT_PREFIX" >/dev/null

echo "Bucket listo:"
aws s3 ls "s3://$BUCKET_NAME/"
