
set -e

FILE="${1:-data/sample.log}"

python3 - "$FILE" <<'PY'
import sys, os, types

# boto3 existe dentro de Lambda, pero no siempre en la maquina local.
# Como esta prueba no toca S3, lo sustituimos por un modulo vacio.
try:
    import boto3  # noqa: F401
except ImportError:
    stub = types.ModuleType("boto3")
    stub.client = lambda *args, **kwargs: None
    sys.modules["boto3"] = stub

sys.path.insert(0, os.path.join("src", "logging-system"))
from lambda_function import to_csv

with open(sys.argv[1], encoding="utf-8") as f:
    csv_text, lines = to_csv(f.read())

print(csv_text)
print(f"-- {lines} renglones convertidos --")
PY
