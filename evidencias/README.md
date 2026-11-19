# Evidencias requeridas

Esta carpeta debe contener evidencia generada **después de desplegar en la cuenta AWS del equipo**. No suban la API key, credenciales, archivos `.tfstate` ni información sensible de la cuenta.

## Evidencia automática

Ejecuten, en este orden:

```bash
./scripts/trigger_pipeline.sh
python3 scripts/run_athena_queries.py
./scripts/collect_evidence.sh
```

Esto genera:

- `lambda-manual-response.json`: objetos raw, conteos y Glue JobRunId.
- `lambda-invoke-metadata.json`: código de estado y bandera de error de la invocación.
- `athena-query-metrics.md`: las tres consultas con `DataScannedInBytes` exacto.
- `athena-query-metrics.csv`: exportable para revisión.
- `01_*_results.csv`, `02_*_results.csv`, `03_*_results.csv`: resultados.
- `generated/`: listados S3, cifrado/bloqueo/lifecycle, configuración y corridas Glue, catálogo, tabla/TTL/muestra DynamoDB, workgroup, Scheduler, roles y retención de logs.

## Capturas recomendadas

| Archivo sugerido | Qué debe verse |
|---|---|
| `01-terraform-apply.png` | `Apply complete` y número de recursos creados |
| `02-eventbridge-schedule.png` | cron, estado Enabled, Lambda destino, retry y DLQ |
| `03-lambda-success.png` | invocación exitosa y `run_id`, sin mostrar la clave |
| `04-s3-raw.png` | prefijos de `fixtures`, `teams`, `standings` y un objeto JSON por entidad |
| `05-glue-job-succeeded.png` | JobRun `SUCCEEDED`, duración, workers y DPU |
| `06-s3-curated-parquet.png` | rutas Hive `league_id=.../season=.../event_month=...` y archivos `.parquet` |
| `07-dynamodb-items.png` | fixture `LATEST`, registro `RUN#...` y TTL |
| `08-athena-query-01.png` | SQL, resultados y **Data scanned** |
| `09-athena-query-02.png` | SQL, resultados y **Data scanned** |
| `10-athena-query-03.png` | SQL, resultados y **Data scanned** |
| `11-s3-lifecycle.png` | reglas de raw, curated, results, temporales y versiones |
| `12-iam-roles.png` | los cuatro roles y sus descripciones |
| `13-cloudwatch-logs.png` | logs de Lambda o Glue con ejecución exitosa |

## Tabla final para el README

Después de ejecutar las consultas, copien del archivo `athena-query-metrics.md` los bytes exactos:

| Consulta | QueryExecutionId | Bytes escaneados | Estado |
|---|---|---:|---|
| 01 Home win rate | completar | completar | SUCCEEDED |
| 02 Goals by month | completar | completar | SUCCEEDED |
| 03 Reconcile standings | completar | completar | SUCCEEDED |

Los bytes deben ser los reportados por Athena, no el tamaño estimado del archivo ni el mínimo facturable.
