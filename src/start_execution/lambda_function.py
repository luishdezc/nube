import os
import re
import time
import urllib.parse

import boto3

STATE_MACHINE_ARN = os.environ.get("STATE_MACHINE_ARN", "")
INPUT_PREFIX = os.environ.get("INPUT_PREFIX", "input/")

_sfn = None

def get_sfn():
    global _sfn
    if _sfn is None:
        _sfn = boto3.client("stepfunctions")
    return _sfn

def execution_name(key):

    base = os.path.splitext(os.path.basename(key))[0]
    base = re.sub(r"[^A-Za-z0-9_-]", "-", base)
    return f"{base}-{int(time.time())}"[:80]

def lambda_handler(event, context):
    arrancadas = []

    for record in event.get("Records", []):
        bucket = record["s3"]["bucket"]["name"]

        key = urllib.parse.unquote_plus(record["s3"]["object"]["key"])

        if not key.startswith(INPUT_PREFIX):
            print(f"Ignorado: {key} no esta en {INPUT_PREFIX}")
            continue

        nombre = execution_name(key)
        respuesta = get_sfn().start_execution(
            stateMachineArn=STATE_MACHINE_ARN,
            name=nombre,

            input=f'{{"bucket": "{bucket}", "key": "{key}"}}',
        )

        print(f"Ejecucion arrancada: {nombre} -> {respuesta['executionArn']}")
        arrancadas.append(nombre)

    return {"status": "ok", "ejecuciones": arrancadas}
