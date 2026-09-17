
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"

echo "Esto va a borrar:"
echo "  - bucket s3://$BUCKET_NAME (con todo su contenido)"
echo "  - lambda $FUNCTION_NAME"
echo "  - log group /aws/lambda/$FUNCTION_NAME"
read -p "Continuar? (y/N) " -n 1 -r
echo
[[ $REPLY =~ ^[Yy]$ ]] || exit 0

echo "Vaciando y borrando el bucket..."
aws s3 rm "s3://$BUCKET_NAME" --recursive || true
aws s3 rb "s3://$BUCKET_NAME" --region "$REGION" || true

echo "Borrando la lambda..."
aws lambda delete-function --function-name "$FUNCTION_NAME" || true

echo "Borrando los logs de CloudWatch..."
aws logs delete-log-group --log-group-name "/aws/lambda/$FUNCTION_NAME" || true

echo "Limpiando archivos locales..."
rm -rf build "$FUNCTION_NAME.zip" "$BATCHES_DIR" notification.json

echo "Todo eliminado."
