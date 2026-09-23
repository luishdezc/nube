# Logging system

Sistema serverless que consume logs de OpenSSH en batches de ~1KB, los procesa con una maquina de
estados de Step Functions y separa los registros normales de los sospechosos en dos tablas de
DynamoDB.

## Cambios entre entregas

| | Parte 1 | Parte 2 | Parte 3 |
|---|---|---|---|
| Procesamiento | 1 Lambda | 1 Lambda | Maquina de estados + 2 Lambdas |
| Destino | CSV en S3 | Tabla `logging` | Tablas `Logs` y `SecurityAlerts` |
| Clasificacion | no hay | no hay | Estado `Choice` |
| Manejo de fallos | ninguno | reintento de Lambda | `Retry` por tarea |

La tabla `logging` de la parte 2 se renombro a `Logs`, siguiendo el enunciado.

## La maquina de estados

Definicion en [`statemachine/logging-system.asl.json`](statemachine/logging-system.asl.json).

| Estado | Tipo | Que hace |
|---|---|---|
| `ParseBatch` | Task (Lambda) | Descarga el batch de S3 y lo separa en lineas parseadas. No escribe en DynamoDB. |
| `ProcesarLineas` | Map | Recorre las lineas, hasta 5 en paralelo. |
| `ClasificarLinea` | Choice | Decide si la linea es sospechosa. |
| `GuardarAlertaUsuarioInvalido` | Task (DynamoDB) | `SecurityAlerts` con `alert_type=INVALID_USER`. |
| `GuardarAlertaBreakIn` | Task (DynamoDB) | `SecurityAlerts` con `alert_type=BREAK_IN_ATTEMPT`. |
| `GuardarLog` | Task (DynamoDB) | `Logs`. |

### Como se arranca

S3 no puede invocar una maquina de estados con una notificacion de bucket: solo sabe llamar Lambda,
SNS y SQS. Por eso existe `start_execution`, una lambda de ~40 lineas que recibe el evento y llama a
`StartExecution`. No procesa nada.

La alternativa es mandar el evento por EventBridge, que si puede apuntar a Step Functions sin
intermediarios. No se uso porque en AWS Academy requiere que `LabRole` confie en
`events.amazonaws.com`, y eso no esta garantizado.

### Clasificacion

El `Choice` usa `StringMatches`, que compara con comodines directamente en la definicion; no hace
falta una lambda para clasificar.

```json
{ "Variable": "$.log", "StringMatches": "*Invalid user*",             "Next": "GuardarAlertaUsuarioInvalido" },
{ "Variable": "$.log", "StringMatches": "*POSSIBLE BREAK-IN ATTEMPT*", "Next": "GuardarAlertaBreakIn" }
```

**`StringMatches` distingue mayusculas.** Con las tres lineas del enunciado, la tercera
(`input_userauth_request: invalid user webmaster [preauth]`, en minusculas) se clasifica como
**normal**, porque el enunciado pide buscar `Invalid user` con mayuscula. Es el comportamiento
correcto segun la especificacion. Para atrapar tambien las minusculas habria que agregar una tercera
regla con `*invalid user*`.

### Retry

Cada tarea que escribe en DynamoDB lleva dos reglas de `Retry`:

```json
{ "ErrorEquals": ["DynamoDB.ProvisionedThroughputExceededException",
                  "DynamoDB.ThrottlingException",
                  "DynamoDB.RequestLimitExceeded",
                  "DynamoDB.InternalServerError"],
  "IntervalSeconds": 1, "MaxAttempts": 5, "BackoffRate": 2 }
```

Con `BackoffRate: 2` las esperas son 1s, 2s, 4s, 8s, 16s. Si DynamoDB rechaza una escritura por
throttling, solo se reintenta **esa** linea; las demas iteraciones del Map siguen su curso y la
ejecucion no falla. `ParseBatch` tambien tiene `Retry`, para errores transitorios del servicio de
Lambda.

### Por que parse_batch devuelve todo como texto

En Step Functions el `Item` del `putItem` se arma con tipos explicitos:

```json
"pid": { "N.$": "$.pid" }
```

`N.$` toma un **string** con digitos y lo guarda como numero. Si la lambda mandara un entero de JSON,
el estado fallaria en ejecucion. Por eso `parse_batch` convierte todo a string, incluidos `pid`,
`line` y `expires_at`. `./scripts/test-local.sh` verifica justamente esto.

Por la misma razon el `Item` tiene forma fija y no se pueden omitir campos: cuando un log no trae
pid, `parse_batch` manda `"0"`.

## Modelo de datos

Las dos tablas comparten esquema:

```
pk (HASH)  = "<hostname>#<program>"       ej. "LabSZ#sshd"
sk (RANGE) = "<ts_iso>#<batch>#<linea>"   ej. "2025-12-10T06:55:46#openssh-1790033516#0002"
```

`SecurityAlerts` agrega `alert_type` (`INVALID_USER` o `BREAK_IN_ATTEMPT`).

**Por que la llave es compuesta:** las tres lineas del enunciado comparten timestamp, hostname y pid.
DynamoDB no permite dos items con la misma llave, asi que con un sort key de solo timestamp se
perderian dos de tres registros, sin aviso. Agregar batch y numero de linea ademas hace la escritura
idempotente: reprocesar un batch sobreescribe con lo mismo en vez de duplicar.

**Por que el timestamp se normaliza a ISO:** DynamoDB ordena los sort keys como texto. Con el formato
de syslog, `Dec 10` quedaria antes que `Feb 3` porque "D" va antes que "F". Como syslog no trae el
anio, se configura con `LOG_YEAR`.

## Estructura del proyecto

```
├── README.md
├── start_logging.sh                      # wrapper de send-logs.sh
├── data
│   └── sample.log                        # las 3 lineas del enunciado
├── statemachine
│   └── logging-system.asl.json           # definicion de la maquina de estados
├── scripts
│   ├── config.sh                         # variables compartidas
│   ├── check-aws.sh
│   ├── create-infra.sh                   # crea TODO
│   ├── create-s3-bucket.sh
│   ├── create-dynamodb-tables.sh
│   ├── package-lambdas.sh
│   ├── deploy-lambdas.sh
│   ├── create-state-machine.sh
│   ├── configure-trigger.sh
│   ├── generate-log.sh
│   ├── split-log.sh
│   ├── send-logs.sh
│   ├── query-logs.sh
│   ├── test-local.sh                     # simula la maquina de estados sin AWS
│   └── teardown.sh
└── src
    ├── parse_batch
    │   ├── lambda_function.py
    │   └── requirements.txt
    └── start_execution
        ├── lambda_function.py
        └── requirements.txt
```

## Configuracion

Todos los scripts leen `scripts/config.sh`. Los nombres de bucket en S3 son **globales**: cambia el
prefijo por el de tu equipo antes de empezar.

```bash
export BUCKET_NAME=ccg1-logging-equipo3
```

`config.sh` tambien exporta `AWS_PROFILE` (default `nube`) y `AWS_DEFAULT_REGION`, asi que no hace
falta escribir `--profile` en cada comando. Para comandos `aws` manuales en una terminal nueva:

```bash
source scripts/config.sh
```

## Uso

### 0. Requisitos

- AWS CLI configurado (en AWS Academy: copiar las credenciales del Learner Lab a `~/.aws/credentials`)
- Python 3 instalado (el comando `zip` es opcional: si no existe, se comprime con Python)

### 1. Verificar credenciales

```bash
./scripts/check-aws.sh
```

### 2. Crear toda la infraestructura

```bash
./scripts/create-infra.sh
```

Crea, en orden: bucket, tablas, lambdas, maquina de estados y trigger. El orden importa porque la
maquina necesita el ARN de `parse_batch` y `start_execution` necesita el ARN de la maquina. Todos los
pasos son idempotentes.

### 3. Generar el log y partirlo en batches

La actividad da tres lineas de ejemplo, que son las primeras del dataset **OpenSSH de loghub**. El
dataset completo son 70MB, asi que el proyecto incluye un generador:

```bash
./scripts/generate-log.sh 200                       # ~20 batches -> data/openssh.log
./scripts/split-log.sh data/openssh.log batches 1024
```

El generador usa semilla fija, asi que todo el equipo obtiene el mismo archivo. `data/openssh.log` no
se sube al repo (esta en `.gitignore`): se regenera con un comando.

### 4. Enviar los batches

```bash
./start_logging.sh 60
```

## Validacion

### Step Functions (vista Graph)

1. **Step Functions → State machines → `logging-system`**
2. Abrir una ejecucion de la lista
3. Pestana **Graph view**

Se ve `ParseBatch`, el `Map` y, dentro, las tres ramas. En **Table view** se puede abrir cada
iteracion del Map y confirmar a que estado entro cada linea.

### Las dos tablas

En **DynamoDB → Tables → Explore table items**, con **Query** (no Scan) y `pk = LabSZ#sshd`:

- `Logs`: lineas normales
- `SecurityAlerts`: solo sospechosas, cada una con su `alert_type`

Repetir el **Run** cada minuto: los conteos suben conforme llegan batches.

Desde la terminal, las dos tablas a la vez:

```bash
./scripts/query-logs.sh                 # conteos
./scripts/query-logs.sh LabSZ#sshd -v   # ademas las ultimas alertas
```

### Sin AWS

```bash
./scripts/test-local.sh data/sample.log
```

Corre `parse_batch` en local, lee el ASL, evalua las reglas del `Choice` tal como estan en el JSON y
comprueba que cada campo del `Item` exista y tenga el tipo correcto. Con las 3 lineas del enunciado
el resultado esperado es 1 `INVALID_USER`, 1 `BREAK_IN_ATTEMPT` y 1 normal.

## Debug

```bash
# Ejecuciones recientes y su estado
aws stepfunctions list-executions \
  --state-machine-arn "$(aws stepfunctions list-state-machines \
     --query "stateMachines[?name=='logging-system'].stateMachineArn | [0]" --output text)" \
  --max-items 5 --output table

# Logs de las lambdas
aws logs tail /aws/lambda/parse_batch --since 10m
aws logs tail /aws/lambda/start_execution --since 10m
```

Si no llegan registros, revisar en orden:

1. Que el batch se haya subido: `aws s3 ls s3://$BUCKET_NAME/input/`
2. Que `start_execution` se haya ejecutado (sus logs)
3. Que tenga el ARN:
   `aws lambda get-function-configuration --function-name start_execution --query 'Environment'`
4. En la vista Graph, que estado quedo en rojo

**Nota sobre el log group:** CloudWatch crea el log group la **primera vez** que la lambda corre. Si
`aws logs tail` dice que no existe, es que todavia no se ha ejecutado.

## Decisiones tecnicas

- **La clasificacion vive en el `Choice`, no en una lambda.** `StringMatches` hace el trabajo sin
  codigo, sin costo de invocacion y queda visible en el Graph.
- **Dos estados de alerta en vez de uno** con condicion combinada: permite guardar un `alert_type`
  distinto y hace visible la separacion en el Graph, que es justo lo que se valida.
- **`Map` con `MaxConcurrency: 5`** en modo INLINE. Un batch de 1KB son ~10 lineas, muy por debajo
  del limite de 256KB de payload entre estados.
- **`PAY_PER_REQUEST`** en las tablas: no hay que adivinar la capacidad y no cobra en reposo.
- **TTL de 7 dias** sobre `expires_at`: un sistema de logs no deberia guardar todo para siempre.
- **Las lineas que no parsean no se descartan**: se guardan con `parsed=false`.
- **Los clientes de boto3 se crean de forma perezosa**: Lambda los reutiliza entre invocaciones
  calientes, y el modulo se puede importar sin credenciales para probarlo en local.

## Destruir recursos

```bash
./scripts/teardown.sh
```

Borra bucket, las dos tablas, la maquina de estados, las dos lambdas y sus log groups.
