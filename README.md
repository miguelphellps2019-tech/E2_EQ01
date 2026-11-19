# E2_EQ01 · Lago de datos deportivos en AWS (Ruta 1)

Proyecto técnico para ingerir datos de **API-Football / API-Sports**, conservar el JSON original en Amazon S3, transformarlo con AWS Glue a Parquet particionado, exponerlo mediante Glue Data Catalog/Athena y mantener una vista operacional en DynamoDB.

> Equipo: **EQ01**.

## Inicio rápido en AWS CloudShell

```bash
# 1. Suban E2_EQ01.zip con Actions → Upload file
unzip E2_EQ01.zip && cd E2_EQ01
bash scripts/cloudshell_setup.sh          # Terraform, permisos, boto3, verifica identidad
source ~/.bashrc
# 2. Desplegar (pide la API key sin mostrarla; luego escribir "yes"), ejecutar y medir
./scripts/deploy.sh
./scripts/trigger_pipeline.sh
python3 scripts/run_athena_queries.py
./scripts/collect_evidence.sh
# 3. Descargar evidencias
zip -r evidencias.zip evidencias          # Actions → Download file: /home/cloudshell-user/E2_EQ01/evidencias.zip
```

`terraform.tfvars` ya está configurado para EQ01.

**Sobre la API key:** la cuenta del curso tiene una SCP que deniega `ssm:PutParameter`, por eso `deploy.sh` pide la clave y la pasa a Terraform como `TF_VAR_api_key` (variable `sensitive`). Lambda la guarda como variable de entorno cifrada con KMS. La clave no se escribe en ningún archivo del repositorio, pero sí queda en `terraform.tfstate` de CloudShell: no compartan ese archivo. En cuentas sin esa restricción se puede seguir usando `bootstrap_api_key.sh` (SSM) y dejar la clave vacía en `deploy.sh`.

## Resultado esperado

Una ejecución crea este flujo:

```text
EventBridge Scheduler
        │ asíncrono, diario
        ▼
Lambda ── GET fixtures / teams / standings ──► API-Football
   │
   ├──► S3 raw/ (JSON original + metadatos)
   ├──► DynamoDB (último fixture + control de corridas)
   └──► Glue Spark (solo corrida actual)
             │
             └──► S3 curated/ (Parquet/Snappy particionado)
                         │
                         └──► Glue Catalog + Athena
                                      │
                                      └──► S3 athena-results/
```

El diseño detallado está en [docs/architecture.md](docs/architecture.md).

## Cumplimiento del enunciado

| Requisito | Implementación/evidencia |
|---|---|
| Lago con 3 capas | Un bucket con `raw/`, `curated/` y `athena-results/`; cifrado, bloqueo público y ciclo de vida |
| Tres consultas con bytes | SQL en `athena/queries/`; `scripts/run_athena_queries.py` registra `DataScannedInBytes`, QueryExecutionId y resultados |
| Datos estructurados DynamoDB/Athena | DynamoDB `*-operational`; Athena `fixtures`, `teams`, `standings` |
| Job Glue raw → Parquet | `src/glue/raw_to_curated.py`, 2 workers G.1X, Snappy, lectura incremental por corrida, deduplicación y particiones |
| Optimización de costos | lifecycle por tamaño, TTL, logs 14 d, resultados 7 d, Parquet, proyección de particiones y límite de 100 MiB/consulta |
| Evento de ingesta | EventBridge Scheduler → Lambda asíncrona; 3 reintentos y SQS DLQ |
| Roles | Dueño, Ingeniero, Analista y Auditor implementados en Terraform |
| ADR | Entrada/almacenamiento, procesamiento y acceso en `docs/adr/` |
| Costos x1/x3 | [docs/costs.md](docs/costs.md), total anual base USD 27.36 y USD 55.08 |
| Trazabilidad | `run_id`, `ingested_at`, `source_file`, DynamoDB run metadata y tabla de linaje |

## Datos seleccionados

- Deporte: fútbol.
- API base: `https://v3.football.api-sports.io`.
- Liga de referencia: Premier League, `league_id=39`.
- Temporada predeterminada: `2024`.
- Endpoints por corrida: `fixtures`, `teams`, `standings`.
- Frecuencia: una vez al día, tres solicitudes/día.

API-Sports publica un plan general de 100 solicitudes diarias. Un tutorial oficial actualizado en 2026 indica que el plan gratuito de API-Football ofrece temporadas históricas 2022–2024; por eso el proyecto usa 2024 y no una temporada actual. Confirmen la cobertura en su *dashboard* antes de desplegar.

## Estructura del repositorio

```text
E2_EQ01/
├── README.md
├── Makefile
├── athena/queries/                 # tres consultas obligatorias
├── docs/
│   ├── architecture.md
│   ├── data_structure.md
│   ├── roles_raci.md
│   ├── costs.md
│   └── adr/
├── evidencias/                     # guía y evidencia generada por el equipo
├── iam/README.md
├── infrastructure/terraform/       # todos los recursos AWS
├── scripts/                        # despliegue, ejecución y evidencia
├── src/lambda_ingest/app.py
├── src/glue/raw_to_curated.py
└── tests/
```

## Prerrequisitos

- Cuenta AWS con permisos para IAM, S3, Lambda, EventBridge Scheduler, SQS, SSM, DynamoDB, Glue, Athena y CloudWatch.
- Cuenta y API key de API-Sports/API-Football.
- AWS CLI configurada: `aws sts get-caller-identity` debe responder con la cuenta correcta.
- Terraform 1.6 o posterior.
- Python 3.10 o posterior y `boto3` para ejecutar el recolector de métricas.
- Recomendado: un AWS Budget de USD 5 mensuales antes de desplegar.

No desplieguen en una cuenta de producción ni concedan `AdministratorAccess` a usuarios permanentes solo para esta práctica.

## 1. Configurar el equipo

```bash
cd E2_EQ01
cp infrastructure/terraform/terraform.tfvars.example \
   infrastructure/terraform/terraform.tfvars
```

Edite `terraform.tfvars`:

```hcl
project_name           = "e2-eq01-api-sports"
team_code              = "EQ01"
api_key_parameter_name = "/e2/eq01/api-sports/key"
league_id              = 39
season                 = 2024
```

Los nombres del bucket incluyen el ID de cuenta y un sufijo aleatorio, por lo que son globalmente únicos.

## 2. Guardar la API key sin exponerla

```bash
./scripts/bootstrap_api_key.sh us-east-1 /e2/eq01/api-sports/key
```

El script solicita la clave sin mostrarla y crea un parámetro SSM `SecureString`. No pase la clave como variable Terraform: hacerlo la guardaría en el estado.

Comprobación segura, sin imprimir el valor:

```bash
aws ssm describe-parameters \
  --parameter-filters 'Key=Name,Values=/e2/eq01/api-sports/key' \
  --region us-east-1
```

## 3. Desplegar

```bash
./scripts/deploy.sh
```

O de forma explícita:

```bash
terraform -chdir=infrastructure/terraform init
terraform -chdir=infrastructure/terraform fmt -recursive
terraform -chdir=infrastructure/terraform validate
terraform -chdir=infrastructure/terraform plan -out=e2.tfplan
terraform -chdir=infrastructure/terraform apply e2.tfplan
```

Recursos principales:

- S3 con versionado, cifrado, lifecycle y bloqueo público.
- Lambda Arm/Python 3.12 y logs de Lambda/Glue con retención de 14 días.
- EventBridge Scheduler, reintentos y SQS DLQ.
- DynamoDB on-demand con GSI y TTL.
- Glue Job 5.0 y Glue Data Catalog.
- Athena workgroup y tres consultas nombradas.
- Cuatro roles humanos de mínimo privilegio.

## 4. Ejecutar la canalización para obtener evidencia

No esperen al cron para la prueba inicial:

```bash
./scripts/trigger_pipeline.sh
```

El script invoca Lambda, guarda la respuesta en `evidencias/lambda-manual-response.json` y espera a que Glue termine en `SUCCEEDED`.

Validaciones rápidas:

```bash
BUCKET=$(terraform -chdir=infrastructure/terraform output -raw bucket_name)
aws s3 ls "s3://${BUCKET}/raw/" --recursive
aws s3 ls "s3://${BUCKET}/curated/" --recursive
```

Deben existir tres objetos JSON raw y archivos `.parquet` en rutas similares a:

```text
curated/fixtures/league_id=39/season=2024/event_month=2024-08/
curated/teams/league_id=39/season=2024/
curated/standings/league_id=39/season=2024/
```

## 5. Ejecutar las tres consultas y anotar bytes

Instale dependencias locales si hace falta:

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements-dev.txt
```

Ejecute:

```bash
python3 scripts/run_athena_queries.py
```

El script crea:

- `evidencias/athena-query-metrics.md`.
- `evidencias/athena-query-metrics.csv`.
- Un CSV de resultados por consulta.

La tabla generada contiene el valor exacto `Statistics.DataScannedInBytes` de Athena. Ese valor, y no una estimación, es el que se debe copiar a la entrega:

| Consulta | Propósito | Bytes |
|---|---|---:|
| 01 Home win rate | desempeño local por equipo | ejecutar y copiar |
| 02 Goals by month | goles y promedio por mes | ejecutar y copiar |
| 03 Reconcile standings | puntos oficiales frente a puntos calculados | ejecutar y copiar |

El workgroup aplica un corte de 100 MiB por consulta. Athena cobra por datos escaneados, con mínimo de 10 MB por consulta; Parquet, compresión, columnas selectivas y filtros de partición reducen el escaneo.

## 6. Recolectar evidencia complementaria

```bash
./scripts/collect_evidence.sh
```

Luego completen las capturas indicadas en [evidencias/README.md](evidencias/README.md). Las capturas deben mostrar los bytes de Athena, el JobRun de Glue, las tres capas S3, DynamoDB, lifecycle, Scheduler y roles IAM.

## Tablas y particiones

### `fixtures`

Última versión de cada `fixture_id`; particiones `league_id`, `season`, `event_month`. Incluye equipos, marcador, estado, sede, ronda, fecha, `run_id`, `ingested_at` y `source_file`.

### `teams`

Última versión de `(league_id, season, team_id)`; particiones `league_id`, `season`. Incluye información de equipo y estadio.

### `standings`

Última versión de `(league_id, season, group_name, team_id)`; particiones `league_id`, `season`. Incluye posición, puntos, diferencia de goles, forma y desglose local/visitante.

### DynamoDB

- `FIXTURE#<id> / LATEST`: acceso operacional por llave.
- `RUN#<fecha-liga-temporada> / METADATA`: objetos raw, conteos y Glue JobRunId.
- `gsi1`: consulta por liga/temporada/fecha y listado temporal de corridas.

La lógica completa está en [docs/data_structure.md](docs/data_structure.md).

## Decisiones de costos

- Raw grande: Standard → Standard-IA día 30 → Glacier día 90 → borrar día 365.
- Raw menor a 128 KiB: no se transiciona; se borra al día 90.
- Curated grande: Standard → Standard-IA día 90 → Glacier día 365 → borrar día 730.
- Athena results y Glue temporal: 7 días.
- Versiones no actuales: 30 días; temporales y resultados: 7 días.
- DynamoDB: on-demand y TTL; sin PITR porque la fuente pública se puede reconstruir.
- SSM Parameter Store estándar en lugar de Secrets Manager para evitar un cargo fijo mensual en este laboratorio.
- Sin NAT Gateway ni VPC privada: Lambda requiere salida HTTPS pública y un NAT costaría más que el resto de la solución.

Estimación anual base: **USD 27.36 x1** y **USD 55.08 x3 agrupado**; tres jobs independientes subirían el escenario x3 a aproximadamente USD 81.89. Véanse supuestos, fórmulas y condiciones de cambio en [docs/costs.md](docs/costs.md).

## Roles y RACI

Terraform crea:

1. `*-data-owner`: revisa gobierno y retención; no ejecuta jobs.
2. `*-data-engineer`: opera raw/curated/Lambda/Glue; no lee la clave ni cambia IAM.
3. `*-analyst`: consulta solo curated mediante Athena; no accede a raw.
4. `*-security-auditor`: revisa CloudTrail, logs, IAM y configuración; no lee datos.

Véase [docs/roles_raci.md](docs/roles_raci.md).

## ADR

- [ADR-001: ingesta y almacenamiento](docs/adr/ADR-001-ingestion-storage.md).
- [ADR-002: procesamiento](docs/adr/ADR-002-processing.md).
- [ADR-003: acceso y gobierno](docs/adr/ADR-003-access-governance.md).

Cada ADR incluye contexto, decisión, alternativas con costo/riesgo, consecuencias, condición cuantitativa de cambio, fecha y responsable.

## Pruebas locales

```bash
python3 -m py_compile \
  src/lambda_ingest/app.py \
  src/glue/raw_to_curated.py \
  scripts/run_athena_queries.py

pytest -q
```

La compilación local valida sintaxis; el script Glue solo puede ejecutarse realmente dentro del runtime de AWS Glue.

## Limpieza al terminar

Guarden primero las evidencias. Después:

```bash
terraform -chdir=infrastructure/terraform destroy
aws ssm delete-parameter \
  --region us-east-1 \
  --name /e2/eq01/api-sports/key
```

`force_destroy_bucket=true` facilita borrar el laboratorio, incluidos objetos y versiones. Cámbienlo a `false` si la cuenta exige protección contra borrado accidental.

## Limitaciones conocidas

- Este repositorio no puede generar capturas, QueryExecutionIds ni bytes reales sin ejecutarse en la cuenta AWS del equipo.
- La cobertura de temporadas depende del plan API-Sports; valide `league_id` y `season` en el dashboard.
- Glue es deliberadamente sobredimensionado para pocos cientos de filas porque es un requisito de la Ruta 1. El ADR documenta cuándo migrar a Lambda o EMR.
- Las URLs de logos se almacenan como atributos; respeten los términos del proveedor si se muestran fuera del contexto académico.

## Referencias oficiales

- API-Sports: https://api-sports.io/
- API-Football documentación v3: https://api-sports.io/documentation/football/v3
- API-Football tutorial de liga y plan gratuito 2026: https://www.api-football.com/news/post/how-to-get-all-data-from-a-league-with-api-football
- EventBridge Scheduler: https://docs.aws.amazon.com/eventbridge/latest/userguide/using-eventbridge-scheduler.html
- AWS Glue pricing: https://aws.amazon.com/glue/pricing/
- Athena pricing: https://aws.amazon.com/athena/pricing/
- Athena partitions: https://docs.aws.amazon.com/athena/latest/ug/partitions.html
- S3 storage classes: https://docs.aws.amazon.com/AmazonS3/latest/userguide/storage-class-intro.html
- DynamoDB on-demand: https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/on-demand-capacity-mode.html
