# ADR-002: Procesamiento con AWS Glue Spark a Parquet particionado

- **Estado:** Aceptado
- **Fecha:** 18 de noviembre de 2026
- **Responsable:** Equipo EQ01

## Contexto

El JSON de API-Football es anidado y debe convertirse a tablas tipadas, deduplicadas y económicas de consultar. La entrega exige un job de Glue que transforme `raw/` en Parquet particionado dentro de `curated/`.

## Decisión

Usar AWS Glue 5.0 con dos workers G.1X. El job lee únicamente los tres snapshots de la corrida actual, aplana `fixtures`, `teams` y `standings`, deduplica por llave de negocio y escribe Parquet/Snappy con sobrescritura dinámica de particiones.

Particiones:

- `fixtures`: `league_id`, `season`, `event_month`.
- `teams`: `league_id`, `season`.
- `standings`: `league_id`, `season`.

Las tablas se crean con Terraform y proyección de particiones; no se ejecuta un crawler diario.

## Costo a 12 meses

- **x1:** `2 DPU × 5/60 h × 365 × USD 0.44 = USD 26.77`.
- **x3 agrupado:** `2 DPU × 10/60 h × 365 × USD 0.44 = USD 53.53`; supone adaptar la ingesta para tres ligas dentro de una sola corrida diaria.
- **Sensibilidad x3 aislado:** tres jobs de cinco minutos cuestan USD 80.30/año solo en Glue.
- Presupuesto total de arquitectura, con 15% de contingencia: USD 31.46 x1 y USD 63.34 x3 agrupado; x3 aislado sería aproximadamente USD 94.17.

## Alternativas

### Alternativa A: Lambda con Python/Pandas o PyArrow

- **Costo:** probablemente menor a USD 1/año en x1 si permanece bajo 500 MB y pocos segundos/minutos.
- **Riesgo:** límite de 15 minutos, memoria local, empaquetado de PyArrow y manejo de archivos/particiones más frágil.
- **Motivo de descarte:** no cumple de forma directa el requisito académico del job Glue y deja menos margen de crecimiento.

### Alternativa B: Athena CTAS/INSERT INTO

- **Costo:** USD 5/TB leído; en este conjunto sería de centavos.
- **Riesgo:** aplanar arreglos y estructuras variables del JSON raw con SQL es menos mantenible; la orquestación de tres salidas y deduplicación es más compleja.
- **Motivo de descarte:** Glue centraliza tipado, validación y escritura de tres tablas.

### Alternativa C: EMR Serverless

- **Costo:** pago por vCPU, memoria y almacenamiento de workers; para corridas pequeñas puede superar Glue por mínimos y arranque, aunque es competitivo a gran escala.
- **Riesgo:** más parámetros, aplicaciones, redes y observabilidad de la necesaria.
- **Motivo de descarte:** no hay decenas de GB ni necesidad de personalizar el runtime Spark.

## Consecuencias

### Se gana

- Transformación distribuida, esquema claro, compresión columnar y poda de particiones.
- Código único para tres entidades y capacidad de crecer a varias ligas.
- Integración nativa con Glue Data Catalog y Athena.

### Se pierde

- Glue representa casi todo el costo anual y tiene latencia de arranque.
- Para pocos cientos de filas, Spark está sobredimensionado.
- La sobrescritura de particiones requiere evitar ejecuciones concurrentes; el job limita concurrencia a uno.

### Vigilar

Duración, DPU-hora, número/tamaño de archivos, filas por tabla, fallos de esquema y bytes de Athena. Compactar si una partición acumula más de 100 archivos pequeños.

## Condición de cambio

Evaluar EMR Serverless si una corrida supera **50 GB** o **30 minutos** durante cinco ejecuciones consecutivas. Evaluar Lambda/PyArrow si el volumen permanece por debajo de **500 MB**, el costo Glue supera **USD 5/mes** y el requisito académico deja de exigir Glue.
