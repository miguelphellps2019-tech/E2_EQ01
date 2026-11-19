# Costos de almacenaje y procesamiento a 12 meses

**Fecha de referencia:** 18 de noviembre de 2026. **Región:** `us-east-1`. Los valores son una estimación de diseño, no una promesa de factura; deben contrastarse con AWS Pricing Calculator y Cost Explorer al desplegar.

## Supuestos

| Variable | Escenario x1 | Escenario x3 |
|---|---:|---:|
| Ligas | 1 | 3 |
| Llamadas API/día | 3 | 9 |
| JSON raw/día | 2 MB | 6 MB |
| Fixtures actualizados/día en DynamoDB | 380 | 1,140 |
| Duración Lambda/día | 15 s a 512 MB | 35 s a 512 MB |
| Glue | 2 DPU × 5 min/día | 2 DPU × 10 min/día |
| Consultas Athena/día | 3 | 9 |
| Mínimo facturable supuesto por consulta | 10 MB | 10 MB |

La temporada 2024 se usa para mantener el proveedor en el plan gratuito histórico. El precio de un plan de API-Sports que habilite temporadas actuales no se incluye porque no es un cargo AWS. El código entregado despliega x1; x3 es un escenario prospectivo que supone adaptar la ingesta para agrupar tres ligas en una sola corrida diaria de Glue.

## Tarifas de referencia

- Glue ETL: **USD 0.44 por DPU-hora**, cobro por segundo con mínimo de un minuto.
- Athena: **USD 5 por TB escaneado**, redondeo y mínimo de 10 MB por consulta.
- Lambda x86 de referencia: USD 0.0000166667 por GB-s y USD 0.20 por millón de solicitudes; la función usa Arm, por lo que el cálculo conservador no aplica el descuento de Arm.
- DynamoDB on-demand estándar: ejemplos oficiales usan USD 0.625 por millón de escrituras y USD 0.125 por millón de lecturas en la región de referencia.
- S3 Standard: USD 0.023 por GB-mes; se agregan solicitudes y transiciones de ciclo de vida.
- EventBridge Scheduler incluye 14 millones de invocaciones mensuales sin cargo; 30–31 invocaciones están muy por debajo.

## Estimación anual

| Servicio | Fórmula x1 | x1 USD/año | Fórmula x3 | x3 USD/año |
|---|---|---:|---|---:|
| AWS Glue | `2 × 5/60 × 365 × 0.44` | **26.77** | `2 × 10/60 × 365 × 0.44` | **53.53** |
| S3 almacenamiento, solicitudes y transiciones | límite conservador con <1 GB x1 y <3 GB x3 | 0.30 | triple volumen y más objetos | 0.70 |
| Lambda | `0.5 GB × 15 s × 365` + solicitudes | 0.05 | `0.5 GB × 35 s × 365` + solicitudes | 0.11 |
| DynamoDB | 138,700 WRU + 36,500 RRU | 0.09 | 416,100 WRU + 109,500 RRU | 0.27 |
| Athena | `3 × 365 × 10 MB × 5/TB` | 0.06 | `9 × 365 × 10 MB × 5/TB` | 0.17 |
| CloudWatch Logs | <0.2 GB/año estimado | 0.10 | <0.6 GB/año estimado | 0.30 |
| Scheduler, SQS sin mensajes, SSM estándar, Glue Catalog | dentro de cuotas gratuitas/uso insignificante | 0.00 | dentro de cuotas gratuitas/uso insignificante | 0.00 |
| **Total base** |  | **27.36** |  | **55.08** |
| **Presupuesto con 15% de contingencia** |  | **31.46** |  | **63.34** |

El costo dominante es Glue. El resto permanece pequeño porque la arquitectura evita servidores permanentes, NAT Gateway y claves KMS administradas por el cliente. Como sensibilidad conservadora, ejecutar tres jobs Glue independientes de cinco minutos elevaría Glue a USD 80.30/año y el total aproximado a USD 81.89, o USD 94.17 con 15% de contingencia.

## Efecto de las políticas técnicas

1. **Parquet/Snappy y selección de columnas.** Athena lee menos bytes que con JSON de filas completas.
2. **Particiones por liga, temporada y mes.** Las consultas obligatorias filtran liga/temporada; el workgroup cancela cualquier consulta que llegue a 100 MiB.
3. **Sin crawler periódico.** Las tablas se crean con Terraform y usan proyección de particiones, evitando corridas de crawler y altas de particiones manuales.
4. **Ciclo de vida por tamaño.** Los objetos grandes pasan a Standard-IA/Glacier; los pequeños no se transicionan para evitar cargos mínimos desproporcionados.
5. **Limpieza.** Athena y Glue temporal: 7 días; logs Lambda y Glue: 14 días; versiones S3: 30 días; corridas DynamoDB: 30 días; raw: 90/365 días; curated: 730 días.
6. **Lectura incremental.** Glue procesa solo los tres objetos de la corrida actual; el histórico raw no aumenta el escaneo diario.
7. **Una fotografía raw por día.** Un `run_id` determinista evita archivos duplicados cuando Scheduler reintenta.
8. **Sin NAT Gateway.** Lambda se ejecuta fuera de VPC y sale al endpoint público HTTPS del proveedor; introducir un NAT costaría mucho más que toda la solución.

## Alertas y condición de revisión

- Crear un AWS Budget de **USD 5/mes** y una alerta al 80%.
- Revisar el diseño si Glue supera 15 minutos durante cinco corridas, si una corrida procesa más de 50 GB, si Athena escanea más de 1 TB/mes o si DynamoDB recibe más de 1 millón de consultas por llave al día.

## Fuentes oficiales

- AWS Glue pricing: https://aws.amazon.com/glue/pricing/
- Amazon Athena pricing: https://aws.amazon.com/athena/pricing/
- AWS Lambda pricing: https://aws.amazon.com/lambda/pricing/
- Amazon DynamoDB pricing: https://aws.amazon.com/dynamodb/pricing/
- Amazon S3 pricing: https://aws.amazon.com/s3/pricing/
- Amazon EventBridge pricing: https://aws.amazon.com/eventbridge/pricing/
