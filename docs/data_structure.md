# Estructura de datos, retención y linaje

## Zonas S3

| Zona | Formato y propósito | Escritura | Lectura | Partición/ruta | Retención |
|---|---|---|---|---|---|
| `raw/` | JSON original del proveedor más metadatos de ingesta; permite reproceso y auditoría | Lambda | Glue e ingeniero de datos | `source=api_sports/entity=<entidad>/ingestion_date=YYYY-MM-DD/run_id=<id>.json` | Objetos >128 KiB: Standard 30 d, Standard-IA 30–90 d, Glacier 90–365 d y borrado; objetos pequeños: borrado a 90 d |
| `curated/` | Parquet/Snappy tipado, aplanado y deduplicado | Glue | Athena, analista | Fixtures: liga/temporada/mes; teams y standings: liga/temporada | >128 KiB: IA a 90 d, Glacier a 365 d, borrado a 730 d; versiones no actuales a 30 d |
| `athena-results/` | CSV y metadatos generados por Athena | Athena | Analista | por ejecución de consulta | borrado a 7 d |

También existen `glue-assets/` para el script y `glue-temp/` para temporales; `glue-temp/` se elimina a 7 días y las versiones antiguas del script a 30 días.

## Tablas estructuradas

### Athena `fixtures`

Llave de negocio: `fixture_id`. Contiene fecha, estado, sede, equipos, marcador por tiempos, liga, ronda y metadatos de ingesta. Particiones: `league_id`, `season`, `event_month`.

### Athena `teams`

Llave de negocio: `(league_id, season, team_id)`. Contiene datos del equipo y su sede. Particiones: `league_id`, `season`.

### Athena `standings`

Llave de negocio: `(league_id, season, group_name, team_id)`. Contiene posición, puntos, diferencia de goles, forma y resultados globales/local/visitante. Particiones: `league_id`, `season`.

### DynamoDB `*-operational`

Diseño de una tabla con PK/SK:

- Fixture: `pk=FIXTURE#<id>`, `sk=LATEST`.
- Corrida: `pk=RUN#<run_id>`, `sk=METADATA`.
- GSI `gsi1`: permite consultar fixtures de una liga-temporada ordenados por fecha y listar corridas por fecha.
- Capacidad: `PAY_PER_REQUEST`.
- TTL: 400 días para fixtures desde la última actualización y 30 días para corridas.

DynamoDB sirve la vista de acceso por llave y el control operacional; S3/Athena conserva el historial analítico. No se usa DynamoDB como almacén del lago porque no es eficiente para escaneos agregados.

## Cuatro criterios de diseño

### Usabilidad

- Nombres en `snake_case`, tipos explícitos y horas normalizadas a UTC.
- Parquet columnar y Snappy para leer solo columnas necesarias.
- Partición mensual en fixtures: una partición diaria produciría demasiados archivos pequeños para solo 380 encuentros por temporada.
- Las consultas incluyen filtros por `league_id`, `season` y un intervalo de `event_month` para poda de particiones.

### Seguridad

- Bloqueo total de acceso público y denegación de HTTP sin TLS.
- Cifrado SSE-S3 en reposo; DynamoDB usa cifrado administrado por AWS.
- La clave API vive en SSM `SecureString`; Lambda solo puede leer ese parámetro.
- El analista puede leer `curated/`, pero IAM le impide leer `raw/` o escribir datos del lago.
- No se ingieren datos personales; logos y URLs se conservan solo como identificadores descriptivos del proveedor.

### Costo y retención

- Ciclos de vida distinguen objetos grandes y pequeños; no se mueve un objeto menor a 128 KiB a clases con mínimos y cargos de transición que podrían costar más que almacenarlo.
- Resultados de Athena y temporales expiran en siete días.
- Versiones no actuales expiran en 30 días.
- CloudWatch retiene logs de Lambda y Glue 14 días; DynamoDB elimina registros operacionales con TTL.
- El workgroup limita cada consulta a 100 MiB.

### Trazabilidad

Cada objeto raw contiene `run_id`, `ingested_at`, endpoint, liga, temporada, URL sin secreto y cabeceras de cuota. Cada fila curated conserva `run_id`, `ingested_at` y `source_file`. El registro de corrida de DynamoDB conecta objetos raw con el Glue JobRun.

## Tabla de linaje

| Dato fuente | Zona | Tabla/objeto | Proceso | Rol ejecutor | Dueño | Fecha registrada |
|---|---|---|---|---|---|---|
| `GET /fixtures` | raw | `entity=fixtures/...json` | Lambda `ingest` | rol técnico Lambda | Dueño de datos | `metadata.ingested_at` |
| `GET /teams` | raw | `entity=teams/...json` | Lambda `ingest` | rol técnico Lambda | Dueño de datos | `metadata.ingested_at` |
| `GET /standings` | raw | `entity=standings/...json` | Lambda `ingest` | rol técnico Lambda | Dueño de datos | `metadata.ingested_at` |
| Raw fixtures | curated | Athena `fixtures` | Glue `raw-to-curated` | rol técnico Glue | Dueño de datos | `ingested_at` + Glue JobRun |
| Raw teams | curated | Athena `teams` | Glue `raw-to-curated` | rol técnico Glue | Dueño de datos | `ingested_at` + Glue JobRun |
| Raw standings | curated | Athena `standings` | Glue `raw-to-curated` | rol técnico Glue | Dueño de datos | `ingested_at` + Glue JobRun |
| Curated | resultados | `athena-results/` | consultas 01–03 | rol Analista | Dueño de datos | QueryExecutionId |
