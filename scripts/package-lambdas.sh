#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"

SRC_DIR="src"
BUILD_ROOT="build"

if [ -z "$PYTHON_BIN" ]; then
  for candidato in python3 python; do
    if "$candidato" -c "import sys" >/dev/null 2>&1; then
      PYTHON_BIN="$candidato"
      break
    fi
  done
fi

if [ -z "$PYTHON_BIN" ]; then
  echo "No se encontro Python (se probo python3 y python)." >&2
  exit 1
fi

comprimir() {
  local origen="$1"
  local destino="$2"

  if command -v zip >/dev/null 2>&1; then
    (cd "$origen" && zip -qr9 "$destino" .)
  else
    "$PYTHON_BIN" - "$origen" "$destino" <<'PYZIP'
import os, sys, zipfile
origen, destino = sys.argv[1], sys.argv[2]
with zipfile.ZipFile(destino, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as z:
    for raiz, _, archivos in os.walk(origen):
        for nombre in archivos:
            ruta = os.path.join(raiz, nombre)
            # Separadores "/" dentro del zip: Lambda corre en Linux
            z.write(ruta, os.path.relpath(ruta, origen).replace(os.sep, "/"))
PYZIP
  fi
}

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
    if [ -f "$VENV_DIR/bin/activate" ]; then
      source "$VENV_DIR/bin/activate"
    else
      source "$VENV_DIR/Scripts/activate"
    fi
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
  comprimir "$PACKAGE_DIR" "$(pwd)/$FUNC_NAME.zip"

  echo "  $FUNC_NAME.zip creado"
done

echo "Empaquetado completo."
