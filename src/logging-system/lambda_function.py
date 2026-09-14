"""
logging-system

Lambda que se dispara cuando llega un batch de logs a s3://<bucket>/input/,
lo descarga, lo convierte a CSV y lo sube a s3://<bucket>/output/.

Formato de salida:
    timestamp, hostname, program, pid, log

El nombre del archivo se conserva, solo cambia la extension:
    input/openssh-1765382146.log  ->  output/openssh-1765382146.csv
"""

import csv
import io
import os
import re
import urllib.parse

import boto3

s3 = boto3.client("s3")

INPUT_PREFIX = os.environ.get("INPUT_PREFIX", "input/")
OUTPUT_PREFIX = os.environ.get("OUTPUT_PREFIX", "output/")

CSV_HEADER = ["timestamp", "hostname", "program", "pid", "log"]


LOG_LINE = re.compile(
    r"""^
    (?P<timestamp>[A-Za-z]{3}\s+\d{1,2}\s+\d{1,2}:\d{2}:\d{2})\s+
    (?P<hostname>\S+)\s+
    (?P<program>[^\s\[:]+)
    (?:\[(?P<pid>\d+)\])?
    :\s?
    (?P<log>.*)
    $""",
    re.VERBOSE,
)


def parse_line(line):
    """Convierte una linea de log en una lista [timestamp, hostname, program, pid, log].

    Si la linea no sigue el formato esperado no se descarta: se guarda completa
    en la columna `log` para no perder informacion.
    """
    match = LOG_LINE.match(line)

    if match is None:
        return ["", "", "", "", line]

    return [
        match.group("timestamp"),
        match.group("hostname"),
        match.group("program"),
        match.group("pid") or "",
        match.group("log"),
    ]


def to_csv(raw_text):
    """Recibe el contenido del batch y regresa el CSV como string."""
    buffer = io.StringIO()
    writer = csv.writer(buffer, lineterminator="\n")

    writer.writerow(CSV_HEADER)

    lines = 0
    for line in raw_text.splitlines():
        line = line.strip()
        if not line:
            continue
        writer.writerow(parse_line(line))
        lines += 1

    return buffer.getvalue(), lines


def output_key(key):
    """input/openssh-1765382146.log -> output/openssh-1765382146.csv"""
    relative = key[len(INPUT_PREFIX):] if key.startswith(INPUT_PREFIX) else key
    name, _ = os.path.splitext(relative)
    return f"{OUTPUT_PREFIX}{name}.csv"


def lambda_handler(event, context):
    procesados = []

    for record in event.get("Records", []):
        bucket = record["s3"]["bucket"]["name"]
        key = urllib.parse.unquote_plus(record["s3"]["object"]["key"])

        print(f"Evento recibido: s3://{bucket}/{key}")

        if not key.startswith(INPUT_PREFIX):
            print(f"Ignorado: {key} no esta en {INPUT_PREFIX}")
            continue

        response = s3.get_object(Bucket=bucket, Key=key)
        raw_text = response["Body"].read().decode("utf-8", errors="replace")
        print(f"Batch descargado ({len(raw_text)} bytes)")

        csv_text, lines = to_csv(raw_text)
        destino = output_key(key)

        s3.put_object(
            Bucket=bucket,
            Key=destino,
            Body=csv_text.encode("utf-8"),
            ContentType="text/csv",
        )
        print(f"CSV con {lines} renglones guardado en s3://{bucket}/{destino}")

        procesados.append(destino)

    return {"status": "ok", "procesados": procesados}
