"""
parse_batch

Primer estado de la maquina de estados. Descarga el batch de S3 y lo separa
en lineas individuales, ya parseadas. NO escribe en DynamoDB: de eso se
encargan los estados de la maquina (ver statemachine/logging-system.asl.json).

Entrada (la manda start_execution):
    {"bucket": "ccg1-logging", "key": "input/openssh-1790033516.log"}

Salida:
    {
      "batch": "openssh-1790033516",
      "count": 10,
      "lines": [ {pk, sk, timestamp, hostname, program, pid, log, ...}, ... ]
    }

Todos los valores salen como STRING, incluso los que en DynamoDB seran
numeros. La razon es que en Step Functions el Item de un putItem se arma con
tipos explicitos: {"pid": {"N.$": "$.pid"}} toma el string "24200" y lo
guarda como numero. Si la lambda mandara un entero de JSON, el estado fallaria.
"""

import datetime
import os
import re
import time
import urllib.parse

import boto3

INPUT_PREFIX = os.environ.get("INPUT_PREFIX", "input/")
LOG_YEAR = int(os.environ.get("LOG_YEAR", datetime.datetime.now(datetime.timezone.utc).year))
TTL_DAYS = int(os.environ.get("TTL_DAYS", "7"))

_s3 = None


def get_s3():
    global _s3
    if _s3 is None:
        _s3 = boto3.client("s3")
    return _s3


MONTHS = {
    "Jan": 1, "Feb": 2, "Mar": 3, "Apr": 4, "May": 5, "Jun": 6,
    "Jul": 7, "Aug": 8, "Sep": 9, "Oct": 10, "Nov": 11, "Dec": 12,
}

LOG_LINE = re.compile(
    r"""^
    (?P<month>[A-Za-z]{3})\s+(?P<day>\d{1,2})\s+(?P<clock>\d{1,2}:\d{2}:\d{2})\s+
    (?P<hostname>\S+)\s+
    (?P<program>[^\s\[:]+)
    (?:\[(?P<pid>\d+)\])?
    :\s?
    (?P<log>.*)
    $""",
    re.VERBOSE,
)


def to_iso(month, day, clock):
    """'Dec', '10', '06:55:46' -> '2025-12-10T06:55:46'

    Se normaliza porque DynamoDB ordena los sort keys como texto: con el
    formato original 'Dec 10' quedaria antes que 'Feb 3' alfabeticamente.
    """
    return f"{LOG_YEAR:04d}-{MONTHS.get(month, 0):02d}-{int(day):02d}T{clock}"


def parse_line(line):
    """Convierte una linea de log en un diccionario de campos (todos string)."""
    match = LOG_LINE.match(line)

    if match is None:
        return {
            "timestamp": "",
            "ts_iso": "",
            "hostname": "unknown",
            "program": "unknown",
            "pid": "0",
            "log": line,
            "parsed": False,
        }

    return {
        "timestamp": f"{match.group('month')} {match.group('day')} {match.group('clock')}",
        "ts_iso": to_iso(match.group("month"), match.group("day"), match.group("clock")),
        "hostname": match.group("hostname"),
        "program": match.group("program"),
        "pid": match.group("pid") or "0",
        "log": match.group("log"),
        "parsed": True,
    }


def build_lines(raw_text, batch_name):
    """Arma la lista de lineas que la maquina de estados va a recorrer."""
    lineas = []
    expires_at = str(int(time.time()) + TTL_DAYS * 86400)
    ingested_at = datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="seconds")

    numero = 0
    for linea in raw_text.splitlines():
        linea = linea.strip()
        if not linea:
            continue

        numero += 1
        item = parse_line(linea)

        item["pk"] = f"{item['hostname']}#{item['program']}"
        item["sk"] = f"{item['ts_iso']}#{batch_name}#{numero:04d}"
        item["batch"] = batch_name
        item["line"] = str(numero)
        item["ingested_at"] = ingested_at
        item["expires_at"] = expires_at

        lineas.append(item)

    return lineas


def lambda_handler(event, context):
    bucket = event["bucket"]
    key = urllib.parse.unquote_plus(event["key"])

    print(f"Procesando s3://{bucket}/{key}")

    if not key.startswith(INPUT_PREFIX):
        raise ValueError(f"La llave {key} no esta en {INPUT_PREFIX}")

    response = get_s3().get_object(Bucket=bucket, Key=key)
    raw_text = response["Body"].read().decode("utf-8", errors="replace")

    batch_name = os.path.splitext(os.path.basename(key))[0]
    lineas = build_lines(raw_text, batch_name)

    print(f"Batch {batch_name}: {len(raw_text)} bytes, {len(lineas)} lineas")

    return {"batch": batch_name, "count": len(lineas), "lines": lineas}
