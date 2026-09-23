#!/bin/bash
set -e

LINEAS="${1:-200}"
SALIDA="${2:-data/openssh.log}"

mkdir -p "$(dirname "$SALIDA")"

python3 - "$LINEAS" "$SALIDA" <<'PY'
import random
import sys

lineas = int(sys.argv[1])
salida = sys.argv[2]

# Semilla fija: el log generado es siempre el mismo, asi todo el equipo
# trabaja con los mismos datos y los conteos de la query son comparables.
random.seed(42)

HOST = "LabSZ"
USUARIOS = ["webmaster", "admin", "root", "test", "oracle", "postgres", "ubuntu", "git"]
IPS = ["173.234.31.186", "103.99.0.122", "5.36.59.76", "212.83.146.135", "183.62.140.253"]
PUERTOS = lambda: random.randint(1024, 65535)

# Plantillas tomadas de los tipos de evento reales del dataset de loghub
PLANTILLAS = [
    "Invalid user {user} from {ip}",
    "input_userauth_request: invalid user {user} [preauth]",
    "Failed password for invalid user {user} from {ip} port {port} ssh2",
    "Connection closed by {ip} [preauth]",
    "reverse mapping checking getaddrinfo for ns.marryaldkfaczcz.com [{ip}] failed - POSSIBLE BREAK-IN ATTEMPT!",
    "pam_unix(sshd:auth): authentication failure; logname= uid=0 euid=0 tty=ssh ruser= rhost={ip}",
    "Received disconnect from {ip}: 11: Bye Bye [preauth]",
    "Accepted password for {user} from {ip} port {port} ssh2",
]

# El reloj avanza unos segundos por linea para que los timestamps
# no se repitan demasiado y las queries por rango tengan sentido.
dia, hora, minuto, segundo = 10, 6, 55, 46
pid = 24200

with open(salida, "w", encoding="utf-8") as f:
    for i in range(lineas):
        segundo += random.randint(0, 4)
        if segundo >= 60:
            segundo -= 60
            minuto += 1
        if minuto >= 60:
            minuto -= 60
            hora += 1
        if hora >= 24:
            hora -= 24
            dia += 1

        # Cada cierto numero de lineas cambia la sesion (y por lo tanto el pid)
        if i % 7 == 0:
            pid += random.randint(1, 5)

        mensaje = random.choice(PLANTILLAS).format(
            user=random.choice(USUARIOS), ip=random.choice(IPS), port=PUERTOS()
        )

        f.write(f"Dec {dia:2d} {hora:02d}:{minuto:02d}:{segundo:02d} "
                f"{HOST} sshd[{pid}]: {mensaje}\n")

print(f"{lineas} lineas escritas en {salida}")
PY

BYTES=$(wc -c < "$SALIDA")
BATCHES=$(( (BYTES + 1023) / 1024 ))
echo "Tamano: $BYTES bytes (~$BATCHES batches de 1KB)"
echo ""
echo "Siguiente paso:"
echo "  ./scripts/split-log.sh $SALIDA batches 1024"
