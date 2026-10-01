import json
import os

import boto3
from boto3.dynamodb.conditions import Key

ALERTS_TABLE = os.environ.get("ALERTS_TABLE", "SecurityAlerts")
GSI_NAME = os.environ.get("GSI_NAME", "ByArrival")

MAX_ITEMS = 1000

_table = None

def get_table():
    global _table
    if _table is None:
        _table = boto3.resource("dynamodb").Table(ALERTS_TABLE)
    return _table

def leer_limit(params):

    crudo = (params or {}).get("limit")
    if crudo is None:
        return MAX_ITEMS
    try:
        valor = int(crudo)
    except (TypeError, ValueError):
        raise ValueError(f"limit debe ser un numero entero, se recibio '{crudo}'")
    if valor < 1:
        raise ValueError("limit debe ser mayor que 0")
    return min(valor, MAX_ITEMS)

def responder(codigo, cuerpo):
    return {
        "statusCode": codigo,
        "headers": {"Content-Type": "application/json"},

        "body": json.dumps(cuerpo, default=str, ensure_ascii=False),
    }

def lambda_handler(event, context):
    params = event.get("queryStringParameters") or {}

    try:
        limit = leer_limit(params)
    except ValueError as error:
        return responder(400, {"error": str(error)})

    severidad = params.get("severity")

    consulta = {
        "IndexName": GSI_NAME,
        "KeyConditionExpression": Key("gsi_pk").eq("ALERT"),
        "ScanIndexForward": False,
    }

    if severidad:
        consulta["FilterExpression"] = Key("severity").eq(severidad.upper())

    items = []
    while len(items) < limit:
        resultado = get_table().query(**consulta)
        items.extend(resultado.get("Items", []))

        cursor = resultado.get("LastEvaluatedKey")
        if not cursor:
            break
        consulta["ExclusiveStartKey"] = cursor

    truncado = len(items) > limit
    items = items[:limit]

    alertas = [
        {
            "id": item["sk"],
            "timestamp": item.get("timestamp", ""),
            "host": item.get("hostname", ""),
            "log": item.get("log", ""),
            "severity": item.get("severity", "UNKNOWN"),
            "alert_type": item.get("alert_type", ""),
            "received_at": item.get("s3_last_modified", ""),
        }
        for item in items
    ]

    print(f"{len(alertas)} alertas regresadas (limit={limit}, severity={severidad})")

    cuerpo = {"count": len(alertas), "alerts": alertas}
    if truncado:
        cuerpo["truncated"] = True

    return responder(200, cuerpo)
