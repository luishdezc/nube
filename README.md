# Logging system

Un log es un registro de eventos que ocurren en un sistema informatico. Este proyecto implementa un
sistema serverless que consume logs en batches de ~1KB, los procesa y guarda el resultado como CSV
en S3.

El flujo de la aplicacion es:

1. `split-log.sh` parte un archivo de log grande en batches de ~1KB (`openssh-<timestamp>.log`)
2. `send-logs.sh` sube los batches a `s3://<bucket>/input/` esperando N segundos entre cada uno
3. El evento `ObjectCreated` en `input/` hace trigger a la lambda `logging-system`
4. La lambda descarga el batch, lo convierte a CSV y lo guarda en `s3://<bucket>/output/`

El batch y el CSV mantienen el mismo nombre y solo cambia la extension, para poder identificar la
correspondencia entre entrada y salida.

## Formato de salida

```
timestamp, hostname, program, pid, log
```

Entrada:

```
Dec 10 06:55:46 LabSZ sshd[24200]: Invalid user webmaster from 173.234.31.186
```

Salida:

```csv
timestamp,hostname,program,pid,log
Dec 10 06:55:46,LabSZ,sshd,24200,Invalid user webmaster from 173.234.31.186
```

Casos que maneja el parser:

- Lineas sin pid (`LabSZ CRON: ...`) dejan la columna `pid` vacia
- Mensajes que contienen comas o comillas se escapan con el modulo `csv` de Python
- Mensajes que contienen `:` (como `input_userauth_request: invalid user webmaster`) no se cortan
- Lineas que no siguen el formato no se descartan: se guardan completas en la columna `log`

## Estructura del proyecto

```
├── README.md
├── start_logging.sh              
├── data
│   └── sample.log                
├── scripts
│   ├── config.sh             
│   ├── check-aws.sh             
│   ├── create-s3-bucket.sh
│   ├── split-log.sh
│   ├── send-logs.sh
│   ├── package-lambda.sh
│   ├── deploy-lambda.sh
│   ├── test-local.sh 
│   └── teardown.sh
└── src
    └── logging-system
        ├── lambda_function.py
        └── requirements.txt
```

## Configuracion

Todos los scripts leen `scripts/config.sh`. Los nombres de bucket en S3 son **globales**: no pueden
repetirse entre cuentas de AWS, por eso el bucket se llama `ccg1-logging` y no solo `logging`.
Cambia el prefijo por el de tu equipo antes de empezar:

```bash
# Opcion 1: editar scripts/config.sh
# Opcion 2: exportar la variable
export BUCKET_NAME=ccg1-logging-equipo3
```

### Perfil de AWS

`config.sh` exporta `AWS_PROFILE`, y el AWS CLI lee esa variable solo, asi que no hace falta pasar
`--profile` en cada comando. El default es el perfil `nube`:

```bash
# Ver que perfiles tienes configurados
aws configure list-profiles

# Usar otro perfil sin editar config.sh
AWS_PROFILE=default ./scripts/create-s3-bucket.sh
```

Antes de crear recursos, confirma con que cuenta estas entrando:

```bash
./scripts/check-aws.sh
```

## Uso

### 0. Requisitos

- AWS CLI configurado (en AWS Academy: copiar las credenciales del Learner Lab a `~/.aws/credentials`)
- Python 3 y `zip` instalados localmente
- El archivo de log en `data/`. Con `data/sample.log` (3 lineas) el sistema ya funciona, pero para
  generar varios batches conviene usar el log completo de OpenSSH.

### 1. Crear el bucket

```bash
./scripts/create-s3-bucket.sh
```

### 2. Empaquetar y desplegar la lambda

```bash
./scripts/package-lambda.sh
./scripts/deploy-lambda.sh
```

`deploy-lambda.sh` crea la funcion si no existe y solo actualiza el codigo si ya estaba. Tambien
configura el permiso de invocacion y la notificacion del bucket.

### 3. Partir el log en batches

```bash
./scripts/split-log.sh data/openssh.log batches 1024
```

Lee linea por linea acumulando bytes hasta pasar el limite de ~1KB; cuando lo alcanza cierra el
batch y abre el siguiente. Ninguna linea se parte a la mitad, por eso los batches quedan un poco
arriba de 1024 bytes.

### 4. Enviar los batches a S3

```bash
./start_logging.sh 30
```

o de forma equivalente:

```bash
./scripts/send-logs.sh 30
```

### 5. Revisar el resultado

```bash
# Archivos generados
aws s3 ls s3://ccg1-logging/output/

# Descargar y ver uno
aws s3 cp s3://ccg1-logging/output/openssh-1765382146.csv - | head
```

## Probar sin AWS

Antes de gastar tiempo de laboratorio se puede validar la conversion localmente:

```bash
./scripts/test-local.sh data/sample.log
```

## Debug

Los `print()` de la lambda van a CloudWatch Logs:

```bash
# Ver los logs mas recientes en la terminal
aws logs tail /aws/lambda/logging-system --follow
```

Si el CSV no aparece en `output/`, revisar en orden:

1. Que el batch si se haya subido a `input/` (`aws s3 ls s3://ccg1-logging/input/`)
2. Que exista la notificacion del bucket
   (`aws s3api get-bucket-notification-configuration --bucket ccg1-logging`)
3. Los errores en CloudWatch

## Cuidado con el ciclo infinito

La lambda lee y escribe en el **mismo** bucket. Si la notificacion no tuviera filtro, el CSV escrito
en `output/` dispararia otra vez la lambda, que escribiria otro archivo, y asi hasta agotar la
cuenta. Por eso hay dos protecciones:

1. La notificacion de S3 filtra por `prefix=input/` y `suffix=.log`
2. La lambda revisa el prefijo de la llave y ignora lo que no venga de `input/`

## Destruir recursos

```bash
./scripts/teardown.sh
```

Elimina el bucket con su contenido, la lambda y el log group de CloudWatch. Es importante borrar
tambien los logs de CloudWatch: en ambientes productivos esto no se hace a mano, se configura un
retention period.

## Notas

- El runtime esta en `python3.13` (variable `RUNTIME` en `config.sh`). Si tu cuenta soporta otra
  version, cambiala ahi.
- `requirements.txt` esta vacio a proposito: el runtime de Lambda ya incluye `boto3` y el resto del
  codigo solo usa la libreria estandar (`csv`, `re`, `io`, `urllib`). Si agregas una dependencia
  externa, `package-lambda.sh` crea el venv y la mete al zip automaticamente.
- La lambda se configuro con 256 MB de memoria y 30 s de timeout; para batches de 1KB sobra.
