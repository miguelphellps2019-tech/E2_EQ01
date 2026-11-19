# ADR-003: Acceso por roles y separación raw/curated

- **Estado:** Aceptado
- **Fecha:** 18 de noviembre de 2026
- **Responsable:** Equipo EQ01

## Contexto

Ingeniería necesita operar la canalización, mientras que análisis solo requiere datos curados y auditoría solo configuración/logs. Compartir credenciales o una política administrativa impediría demostrar mínimo privilegio.

## Decisión

Crear cuatro roles asumibles dentro de la cuenta: Dueño de datos, Ingeniero de datos, Analista y Auditor. El analista lee únicamente `curated/` y escribe resultados de Athena; ingeniería opera raw/curated/Lambda/Glue pero no lee la API key; auditor no lee objetos de datos.

## Alternativas

1. **Un rol único de proyecto.** Costo USD 0, pero riesgo alto de borrado, exposición raw y falta de atribución.
2. **Usuarios IAM con claves permanentes.** Costo USD 0, pero riesgo alto de credenciales filtradas y rotación manual.
3. **Lake Formation desde el inicio.** Costo de servicio bajo, pero mayor complejidad operativa para tres tablas y un solo equipo.

## Consecuencias

Se gana separación de funciones, evidencia auditable y menor impacto de errores. Se pierde simplicidad inicial y un administrador debe autorizar quién puede asumir cada rol. Se vigilan denegaciones IAM, cambios de políticas y accesos a raw.

## Condición de cambio

Adoptar Lake Formation si se superan **20 tablas**, **10 equipos consumidores**, se requieren permisos por columna/fila o hay intercambio entre cuentas.
