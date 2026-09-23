#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"

FILE="${1:-data/sample.log}"
export LOG_YEAR TTL_DAYS

python3 - "$FILE" <<'PY'
import fnmatch
import json
import os
import sys
import types

# boto3 existe dentro de Lambda, pero no siempre en la maquina local.
try:
    import boto3  # noqa: F401
except ImportError:
    stub = types.ModuleType("boto3")
    stub.client = lambda *a, **k: None
    sys.modules["boto3"] = stub

sys.path.insert(0, os.path.join("src", "parse_batch"))
from lambda_function import build_lines

ruta = sys.argv[1]
batch = os.path.splitext(os.path.basename(ruta))[0]

with open(ruta, encoding="utf-8") as f:
    lineas = build_lines(f.read(), batch)

with open(os.path.join("statemachine", "logging-system.asl.json"), encoding="utf-8") as f:
    asl = json.load(f)

estados = asl["States"]["ProcesarLineas"]["ItemProcessor"]["States"]
choice = estados["ClasificarLinea"]


def evaluar_choice(linea):
    """Aplica las reglas del Choice tal como estan en el JSON."""
    for regla in choice["Choices"]:
        campo = regla["Variable"].removeprefix("$.")
        if fnmatch.fnmatchcase(linea.get(campo, ""), regla["StringMatches"]):
            return regla["Next"]
    return choice["Default"]


# --- 1. Clasificacion ---------------------------------------------------
conteo = {}
print(f"{'ESTADO':<32} {'TABLA':<16} LOG")
print("-" * 100)

for linea in lineas:
    destino = evaluar_choice(linea)
    tabla = estados[destino]["Parameters"]["TableName"]
    conteo[destino] = conteo.get(destino, 0) + 1
    if len(lineas) <= 12:
        print(f"{destino:<32} {tabla:<16} {linea['log'][:48]}")

print()
for estado, n in sorted(conteo.items()):
    print(f"  {estado:<32} {n:>4} lineas  -> {estados[estado]['Parameters']['TableName']}")

# --- 2. Los campos del Item existen y tienen el tipo correcto ------------
print("\nValidando los Item del putItem contra la salida de parse_batch...")
errores = []

for nombre, estado in estados.items():
    if estado["Type"] != "Task":
        continue
    for campo, definicion in estado["Parameters"]["Item"].items():
        for tipo, valor in definicion.items():
            if not tipo.endswith(".$"):
                continue  # valor fijo, como alert_type
            origen = valor.removeprefix("$.")
            for linea in lineas:
                if origen not in linea:
                    errores.append(f"{nombre}: falta el campo '{origen}'")
                    break
                dato = linea[origen]
                if not isinstance(dato, str):
                    errores.append(
                        f"{nombre}.{campo}: '{origen}' es {type(dato).__name__}, "
                        f"debe ser string para el putItem")
                    break
                if tipo == "N.$" and not dato.lstrip("-").isdigit():
                    errores.append(f"{nombre}.{campo}: '{origen}'='{dato}' no es numero")
                    break

# --- 3. Llaves unicas ---------------------------------------------------
llaves = {(l["pk"], l["sk"]) for l in lineas}
if len(llaves) != len(lineas):
    errores.append(f"llaves repetidas: {len(lineas)} lineas pero {len(llaves)} llaves unicas")

if errores:
    print("\nPROBLEMAS ENCONTRADOS:")
    for e in sorted(set(errores)):
        print(f"  - {e}")
    sys.exit(1)

print(f"OK: {len(lineas)} lineas, {len(llaves)} llaves unicas, todos los campos validos.")
PY
