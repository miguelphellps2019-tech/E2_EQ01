# Permisos IAM

Las políticas ejecutables están declaradas como infraestructura en:

- `infrastructure/terraform/iam.tf`: roles de servicio de Lambda, Glue y Scheduler.
- `infrastructure/terraform/access_roles.tf`: Dueño de datos, Ingeniero de datos, Analista y Auditor.

La clave de API no aparece en ninguna política ni archivo. El ARN del parámetro SSM se construye a partir de `api_key_parameter_name`, y solo el rol de Lambda recibe `ssm:GetParameter` sobre ese ARN.

Para asignar una persona a un rol, el administrador de la cuenta debe concederle `sts:AssumeRole` sobre el ARN mostrado por `terraform output role_arns`. No se recomienda crear claves IAM permanentes para el proyecto.
