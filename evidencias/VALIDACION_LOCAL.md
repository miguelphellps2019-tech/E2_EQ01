# Validación local previa al despliegue

**Fecha:** 18 de noviembre de 2026  
**Alcance:** validaciones que no requieren credenciales ni una cuenta AWS.

## Resultado

- `pytest -q`: **6 pruebas aprobadas**.
- `python3 -m compileall -q src scripts tests`: **sin errores de sintaxis**.
- `bash -n scripts/*.sh`: **sin errores de sintaxis**.
- Revisión estática de referencias Terraform: **sin referencias locales o variables faltantes**.
- Revisión de delimitadores HCL: **balance correcto**.
- Enlaces Markdown internos: **sin rutas rotas**.

## Validación pendiente en el entorno del equipo

El entorno usado para preparar este repositorio no dispone del binario Terraform ni de credenciales AWS. Por ello, antes de entregar se debe ejecutar:

```bash
terraform -chdir=infrastructure/terraform fmt -recursive
terraform -chdir=infrastructure/terraform init
terraform -chdir=infrastructure/terraform validate
terraform -chdir=infrastructure/terraform plan
```

Después se debe desplegar y generar la evidencia real indicada en `evidencias/README.md`. Los bytes de Athena, QueryExecutionIds, JobRunIds y capturas no pueden conocerse hasta ejecutar la solución en la cuenta AWS del equipo.
