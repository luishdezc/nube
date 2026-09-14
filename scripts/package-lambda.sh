
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"

SRC_DIR="src"
BUILD_ROOT="build"
PYTHON_BIN="${PYTHON_BIN:-python3}"

rm -rf "$BUILD_ROOT"
mkdir -p "$BUILD_ROOT"

for func in "$SRC_DIR"/*; do
  [ -d "$func" ] || continue

  FUNC_NAME=$(basename "$func")
  echo "Empaquetando $FUNC_NAME..."

  WORK_DIR="$BUILD_ROOT/$FUNC_NAME"
  VENV_DIR="$WORK_DIR/venv"
  PACKAGE_DIR="$WORK_DIR/package"
  REQ_FILE="$func/requirements.txt"

  mkdir -p "$PACKAGE_DIR"

  DEPS=0
  if [ -f "$REQ_FILE" ]; then
    DEPS=$(grep -v '^\s*#' "$REQ_FILE" | grep -c '[^[:space:]]' || true)
  fi

  if [ "$DEPS" -gt 0 ]; then
    echo "  Instalando $DEPS dependencia(s)..."
    $PYTHON_BIN -m venv "$VENV_DIR"
    source "$VENV_DIR/bin/activate"
    pip install --quiet --upgrade pip
    pip install --quiet -r "$REQ_FILE"

    SITE_PACKAGES=$(python -c "import site; print(site.getsitepackages()[0])")
    cp -r "$SITE_PACKAGES"/* "$PACKAGE_DIR"/

    deactivate
    rm -rf "$VENV_DIR"
  else
    echo "  Sin dependencias externas (boto3 ya viene en el runtime)."
  fi

  cp "$func/lambda_function.py" "$PACKAGE_DIR"/

  rm -f "$FUNC_NAME.zip"
  cd "$PACKAGE_DIR"
  zip -qr9 "../../../$FUNC_NAME.zip" .
  cd - >/dev/null

  echo "  $FUNC_NAME.zip creado"
done

echo "Empaquetado completo."
