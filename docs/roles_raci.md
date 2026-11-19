# Política de acceso y RACI

## Principios

- Mínimo privilegio, separación entre datos crudos y datos de consumo y prohibición de secretos en código/estado.
- Acceso humano mediante `sts:AssumeRole`; no se crean usuarios IAM ni claves permanentes.
- Denegación implícita para cualquier acción no listada.
- La aprobación organizacional del Dueño de datos debe acompañar la asignación técnica de roles.

## Roles implementados

| Rol | Puede | No puede | Responsabilidad |
|---|---|---|---|
| Dueño de datos | Revisar catálogo, ciclo de vida, cifrado, bucket policy y definición de roles | Ejecutar Lambda/Glue, escribir objetos, consultar el secreto | Aprobar acceso, retención y propósito de uso |
| Ingeniero de datos | Leer/escribir `raw/` y `curated/`, invocar Lambda, iniciar/inspeccionar Glue, consultar DynamoDB operacional | Leer la clave API, cambiar políticas IAM, administrar dueños | Operar y corregir la canalización; asegurar calidad y linaje |
| Analista | Ejecutar Athena en el workgroup, leer catálogo y `curated/`, usar `athena-results/` | Leer `raw/`, escribir `curated/`, iniciar Glue o modificar permisos | Producir análisis reproducibles y filtrar particiones |
| Auditor de seguridad | Revisar CloudTrail Event History, CloudWatch, IAM y configuración de recursos | Leer objetos raw/curated, ejecutar jobs o cambiar configuración | Verificar mínimo privilegio, cifrado, retención y actividad |

Terraform crea los cuatro roles en `access_roles.tf`. La política de confianza permite que el administrador de la misma cuenta delegue `sts:AssumeRole`; el administrador aún debe conceder a cada persona el permiso para asumir su rol correspondiente.

## RACI

R = Responsible, A = Accountable, C = Consulted, I = Informed.

| Actividad | Dueño de datos | Ingeniero de datos | Analista | Auditor |
|---|---|---|---|---|
| Aprobar acceso y retención | A/R | C | I | C |
| Operar ingesta y Glue | I | A/R | I | C |
| Ejecutar y documentar consultas Athena | A | C | R | I |
| Revisar controles, logs y evidencias | C | I | I | A/R |

## Matriz de zonas

| Acción | Dueño | Ingeniero | Analista | Auditor |
|---|---:|---:|---:|---:|
| Leer `raw/` | No | Sí | No | No |
| Escribir `raw/` | No | Sí | No | No |
| Leer `curated/` | Metadatos | Sí | Sí | No |
| Escribir `curated/` | No | Sí | No | No |
| Ejecutar Glue | No | Sí | No | No |
| Ejecutar Athena | No | Opcional para prueba | Sí | No |
| Cambiar IAM | No | No | No | No |

Los cambios IAM quedan fuera de estos roles y pertenecen al administrador/arquitecto de la cuenta.
