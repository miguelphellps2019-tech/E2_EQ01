# ADR-001: Ingesta programada con Lambda y almacenamiento S3 + DynamoDB

- **Estado:** Aceptado
- **Fecha:** 18 de noviembre de 2026
- **Responsable:** Equipo EQ01

## Contexto

Se requieren fotografías reproducibles de tres endpoints de API-Football sin exponer la clave ni mantener servidores encendidos. El uso analítico es por lotes, pero también se necesita una vista rápida del último estado de cada fixture.

## Decisión

Usar EventBridge Scheduler una vez al día para invocar Lambda de forma asíncrona. Lambda hace tres `GET` síncronos, guarda la respuesta original en S3 `raw/`, actualiza el último fixture y el control de corridas en DynamoDB y lanza Glue. La clave se lee desde SSM Parameter Store `SecureString`.

S3 es el sistema de registro analítico; DynamoDB solo es una vista operacional por llave. La región es `us-east-1`, sin replicación interregional en la primera versión.

**Costo estimado x1 asociado a ingesta/almacenamiento:** aproximadamente USD 0.59/año antes de Glue (S3 0.30, Lambda 0.05, DynamoDB 0.09, Athena 0.06, logs 0.10 y servicios menores). EventBridge queda dentro de su nivel gratuito.

## Alternativas

### Alternativa A: API Gateway + Lambda bajo demanda

- **Costo:** cercano al elegido a este volumen; las solicitudes de API Gateway serían centavos o quedarían dentro de créditos/cuotas aplicables.
- **Riesgo:** el usuario espera una respuesta, puede repetir llamadas, consumir cuota y producir ingestas no reproducibles; agrega autenticación de un endpoint público.
- **Motivo de descarte:** el dato no necesita respuesta interactiva y el cron ofrece una fotografía consistente.

### Alternativa B: tarea ECS Fargate programada

- **Costo:** el cómputo de una tarea mínima durante cinco minutos diarios sería menor a unos pocos dólares/año, pero aumentaría si se agrega VPC privada, imágenes, registro y especialmente NAT Gateway.
- **Riesgo:** mayor operación, tiempo de arranque, repositorio de imágenes y superficie de configuración para una extracción de pocos MB.
- **Motivo de descarte:** Lambda cabe holgadamente en 120 segundos y no necesita dependencias nativas.

### Alternativa C: guardar todo el historial solo en DynamoDB

- **Costo:** bajo en el volumen inicial, pero crece por cada snapshot y cada escaneo; las agregaciones históricas no aprovechan almacenamiento columnar.
- **Riesgo:** modelado complejo para análisis, exportaciones adicionales y consultas completas más caras que Athena sobre Parquet.
- **Motivo de descarte:** el patrón principal es analítico por lotes, no millones de consultas por llave.

## Consecuencias

### Se gana

- Escala a cero, una sola fuente histórica en JSON y reintentos administrados.
- Secreto fuera del código y del estado Terraform.
- Acceso por llave de milisegundos en DynamoDB y análisis histórico en S3/Athena.
- Idempotencia diaria y DLQ para fallos no resueltos.

### Se pierde

- Frescura en tiempo real: el RPO es 24 horas.
- Lambda depende de que cada llamada termine dentro del timeout.
- S3 y DynamoDB mantienen dos representaciones con propósitos distintos.

### Vigilar

Cuota restante del API, errores 429/5xx, mensajes en DLQ, duración de Lambda, objetos raw faltantes y crecimiento de escrituras DynamoDB.

## Condición de cambio

Revisar la decisión si una corrida requiere **más de 50 llamadas**, **más de 10 minutos**, **más de 100 MB de respuesta** o una frecuencia inferior a **cinco minutos**. En esos casos evaluar Step Functions + Fargate o un patrón de streaming. Activar replicación interregional si el RTO baja de 4 horas o el RPO baja de 24 horas.
