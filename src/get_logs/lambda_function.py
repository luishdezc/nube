import json
import os

import boto3
from boto3.dynamodb.conditions import Key

LOGS_TABLE = os.environ.get("LOGS_TABLE", "Logs")
GSI_NAME = os.environ.get("GSI_NAME", "ByArrival")
DEFAULT_TOP = 10
MAX_TOP = 100

_table = None

def get_table():
    global _table
    if _table is None:
        _table = boto3.resource("dynamodb").Table(LOGS_TABLE)
    return _table

def leer_top(params):

    crudo = (params or {}).get("top")
    if crudo is None:
        return DEFAULT_TOP
    try:
        valor = int(crudo)
    except (TypeError, ValueError):
        raise ValueError(f"top debe ser un numero entero, se recibio '{crudo}'")
    if valor < 1:
        raise ValueError("top debe ser mayor que 0")

    return min(valor, MAX_TOP)

def responder(codigo, cuerpo):
    return {
        "statusCode": codigo,
        "headers": {"Content-Type": "application/json"},

        "body": json.dumps(cuerpo, default=str, ensure_ascii=False),
    }

def lambda_handler(event, context):
    try:
        top = leer_top(event.get("queryStringParameters"))
    except ValueError as error:
        return responder(400, {"error": str(error)})

    resultado = get_table().query(
        IndexName=GSI_NAME,
        KeyConditionExpression=Key("gsi_pk").eq("LOG"),
        ScanIndexForward=False,
        Limit=top,
    )

    logs = [
        {
            "id": item["sk"],
            "timestamp": item.get("timestamp", ""),
            "host": item.get("hostname", ""),
            "program": item.get("program", ""),
            "pid": item.get("pid", 0),
            "log": item.get("log", ""),
            "batch": item.get("batch", ""),
            "received_at": item.get("s3_last_modified", ""),
        }
        for item in resultado.get("Items", [])
    ]

    print(f"{len(logs)} logs regresados (top={top})")

    return responder(200, {"count": len(logs), "top": top, "logs": logs})
