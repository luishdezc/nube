"""
start_execution

S3 no puede invocar una maquina de estados directamente con una notificacion
de bucket: solo sabe llamar Lambda, SNS y SQS. Esta funcion es el puente.
Recibe el evento ObjectCreated y arranca una ejecucion de Step Functions.

La alternativa es mandar el evento por EventBridge, que si puede apuntar a
Step Functions sin intermediarios. No se uso porque en AWS Academy requiere
que LabRole confie en events.amazonaws.com, y eso no esta garantizado.

Esta funcion no procesa nada: solo traduce el evento y arranca la ejecucion.
"""

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
    """Nombre unico y valido para la ejecucion.

    Step Functions solo acepta letras, numeros, guiones y guiones bajos, con
    un maximo de 80 caracteres, y rechaza un nombre repetido dentro de los
    ultimos 90 dias. Por eso se agrega el epoch: si el mismo batch se resube
    a S3, la ejecucion nueva no choca con la anterior.
    """
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
