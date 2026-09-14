
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"

echo "Perfil : $AWS_PROFILE"
echo "Region : $REGION"
echo "Bucket : s3://$BUCKET_NAME"
echo "Lambda : $FUNCTION_NAME"
echo ""

if ! aws sts get-caller-identity --output table; then
  echo ""
  echo "No se pudo autenticar con el perfil '$AWS_PROFILE'." >&2
  echo "Revisa que exista en ~/.aws/credentials con: aws configure list-profiles" >&2
  exit 1
fi

echo ""
echo "Credenciales OK."
