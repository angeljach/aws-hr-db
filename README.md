# AWS HR Database - Terraform Serverless Architecture

Una arquitectura serverless completa en AWS que simula la extracción, encriptación y consulta de datos de empleados con control de acceso basado en roles.

## Características

✅ **Encriptación AES-256-GCM** (sin KMS) - Directamente en Lambda  
✅ **3 Roles de acceso**: Admin (acceso total), Limited (solo no-sensibles), Premium (no-sensibles + phone)  
✅ **RDS PostgreSQL** en subnets privadas  
✅ **API Gateway** con autenticación Cognito  
✅ **2 Lambda functions** en GO (Extract & Encrypt, Query & Decrypt)  
✅ **Paginación** de 10 empleados por página  
✅ **100% Free Tier** (~$0/mes)  

---

## Arquitectura

```
┌─────────────────────────────────────────────────────────────┐
│                      AWS VPC (10.0.0.0/16)                 │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ┌──────────┐  ┌──────────┐                                │
│  │ IGW      │  │ Public   │                                │
│  │          │──│ Subnets  │                                │
│  └──────────┘  └──────────┘                                │
│                     │                                       │
│              ┌──────────────┐                              │
│              │  API Gateway │                              │
│              │  + Cognito   │                              │
│              └──────┬───────┘                              │
│                     │                                       │
│              ┌──────▼───────┐                              │
│              │  Lambda      │                              │
│              │  - Extract   │                              │
│              │  - Query     │                              │
│              └──────┬───────┘                              │
│                     │                                       │
│          ┌──────────┴──────────┐                           │
│          │   Private Subnets   │                           │
│          ├──────────┬──────────┤                           │
│          │ RDS PostgreSQL      │                           │
│          │ - Employees Table   │                           │
│          │ - Encrypted Fields  │                           │
│          └─────────────────────┘                           │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

---

## Requisitos Previos

- AWS Account con Free Tier eligibilidad
- Terraform >= 1.0
- Go >= 1.21 (para compilar Lambdas)
- AWS CLI configurado
- jq (para parsing JSON)

---

## Instalación y Deployment

### 1. Clonar el repositorio

```bash
cd aws-hr-db
```

### 2. Generar clave de encriptación

```bash
# Genera una clave AES-256 aleatoria
ENCRYPTION_KEY=$(openssl rand -hex 32)
echo "Encryption Key: $ENCRYPTION_KEY"
```

### 3. Actualizar terraform.tfvars

```bash
# Editar terraform/terraform.tfvars con tus valores
# Cambiar especialmente:
# - db_password (no usar temporal)
# - cognito_*_password
# - encryption_key (pegar la generada arriba)
# - terraform/terraform.tfvars
```

### 4. Compilar Lambdas

```bash
chmod +x scripts/build_lambdas.sh
scripts/build_lambdas.sh
```

Esto generará binarios `bootstrap` en cada carpeta de Lambda:
- `lambda/extract_encrypt/bootstrap`
- `lambda/query_decrypt/bootstrap`

### 5. Inicializar y aplicar Terraform

```bash
cd terraform
terraform init
terraform plan
terraform apply
```

**Salida importante**: Guardá los outputs:
- `api_gateway_url` — URL base del API
- `cognito_user_pool_id` — Para obtener tokens
- `extract_lambda_name` — Nombre de la Lambda de extracción

---

## Uso

### Opción 1: Extraer datos (Lambda manualmente)

```bash
# Invocar Lambda para insertar 20 empleados dummy
scripts/invoke-extract.sh aws-hr-db-extract us-east-1

# Output esperado:
# {
#   "message": "Extraction and encryption completed successfully",
#   "rows_added": 20,
#   "timestamp": "2024-05-22T...",
#   "status_code": 200
# }
```

### Opción 2: Consultar empleados vía API

#### Obtener token Cognito

El script `scripts/get_cognito_token.sh` usa `aws cognito-idp initiate-auth` con el flow `USER_PASSWORD_AUTH` y devuelve el **IdToken** (es el que valida el authorizer de API Gateway y contiene el claim `cognito:groups` que la Lambda usa para el role-based access).

> Nota: el endpoint OAuth2 `/oauth2/token` de Cognito **no soporta** `grant_type=password` — por eso usamos la API `cognito-idp` directamente.

```bash
# Tomar el CLIENT_ID desde los outputs de Terraform
CLIENT_ID=$(cd terraform && terraform output -raw cognito_client_id)

# Credenciales del usuario de prueba (deben coincidir con terraform.tfvars)
USERNAME="admin@example.com"
PASSWORD="AdminPass123!"

# Obtener el ID token
TOKEN=$(scripts/get_cognito_token.sh "$CLIENT_ID" "$USERNAME" "$PASSWORD")

echo "Token: ${TOKEN:0:40}..."   # debería verse "eyJraWQiOiI..."
```

Atajo para imprimir la firma con tu CLIENT_ID ya resuelto:

```bash
make get-token
```

**Firma del script:** `scripts/get_cognito_token.sh <CLIENT_ID> <USERNAME> <PASSWORD> [REGION]`
(Region por defecto: `us-east-1`.)

#### Llamar al API

```bash
# URL del API Gateway desde los outputs de Terraform
API_URL=$(cd terraform && terraform output -raw api_gateway_url)

# GET /employees — listado paginado
curl -sS "$API_URL/employees?page=1&limit=10" \
  -H "Authorization: Bearer $TOKEN" | jq

# GET /employees/{id} — un empleado específico
curl -sS "$API_URL/employees/1" \
  -H "Authorization: Bearer $TOKEN" | jq
```

Los campos en la respuesta dependen del grupo Cognito del usuario (admin / premium / limited). Si quieres ver la diferencia, repite con otro usuario:

```bash
TOKEN=$(scripts/get_cognito_token.sh "$CLIENT_ID" "limited@example.com" "LimitedPass123!")
curl -sS "$API_URL/employees/1" -H "Authorization: Bearer $TOKEN" | jq
```

**Errores comunes:**
- `{"message":"Unauthorized"}` → token expirado (1h por default) o IdToken inválido. Regenéralo.
- `{"message":"Missing Authentication Token"}` → la URL es incorrecta (ruta o método que API Gateway no tiene mapeado).
- HTTP 500 desde la Lambda → `aws logs tail /aws/lambda/aws-hr-db-query --follow` para ver el detalle.

---

## Roles de Acceso

La respuesta JSON incluye solo los campos que el rol del usuario tiene permiso para ver. Los campos no autorizados se omiten completamente (no aparecen en la respuesta, ni como `null`).

### Admin (acceso completo)
```json
{
  "employee_id": 1,
  "first_name": "Juan",
  "last_name": "García",
  "email": "juan.garcia@company.com",
  "department": "Engineering",
  "hire_date": "2020-01-15",
  "phone": "555-0101",
  "address": "123 Main St",
  "salary": "75000"
}
```

### Limited (no-sensibles)
```json
{
  "employee_id": 1,
  "first_name": "Juan",
  "last_name": "García",
  "email": "juan.garcia@company.com",
  "department": "Engineering",
  "hire_date": "2020-01-15"
}
```

### Premium (no-sensibles + phone)
```json
{
  "employee_id": 1,
  "first_name": "Juan",
  "last_name": "García",
  "email": "juan.garcia@company.com",
  "department": "Engineering",
  "hire_date": "2020-01-15",
  "phone": "555-0101"
}
```

---

## Decisiones Arquitectónicas (ADRs)

### ADR-001: Omitir campos no autorizados en lugar de enviarlos como null

**Problema**: El contrato de API debe ser consistente y evitar ambigüedades entre "campo no permitido para este rol" y "campo vacío/null en los datos".

**Decisión**: Los campos sensibles que el usuario no tiene permiso de ver se omiten completamente de la respuesta JSON (usando `omitempty`), en lugar de enviarlos como `null`.

**Justificación**:
- **Claridad de contrato**: El cliente siempre recibe la misma respuesta del servidor para un empleado; la diferencia está en qué campos ve cada rol.
- **Simplicidad para consumers**: Un cliente JSON no necesita verificar `_meta.redacted_fields` para saber si un campo está oculto; simplemente chequea si la propiedad existe.
- **Mejor experiencia para clientes de API**: Especialmente importante cuando hay diferentes tipos de clientes (web, mobile, third-party integrations) — todos usan la misma estructura con campos opcionales omitidos.
- **Estándar de la industria**: APIs como Stripe, GitHub, y otros omiten campos sensibles en lugar de enviarlos como null.

**Trade-offs**:
- Los schemas OpenAPI deben marcar estos campos como `nullable: true, not: required` para que los clients sepan que podrían no estar presentes.
- Los clients deben usar `?.` (optional chaining) en lenguajes modernos o chequeos nulos antes de acceder.

**Alternativas rechazadas**:
1. Enviar `null` para campos no autorizados (anterior design) — requería `_meta.redacted_fields` para distinguir "no permitido" de "genuinamente null".
2. Errores 403 por campo — demasiado granular, requería múltiples requests.
3. Roles específicos en el token JWT — más complejo de maintener que el modelo actual de grupos Cognito.

**Impacto**:
- Código: `Employee` struct ahora usa `omitempty` en campos sensibles.
- Documentación: Responses en `README.md` y OpenAPI spec reflejan los campos reales por rol.
- Testing: Validar que los JSON responses no incluyen claves de campos no permitidos.

---

## Usuarios de Prueba

Tres usuarios creados automáticamente en Cognito:

| Usuario | Email | Contraseña | Rol | Acceso |
|---------|-------|------------|-----|--------|
| Admin | admin@example.com | AdminPass123! | admin | Todos los campos |
| Limited | limited@example.com | LimitedPass123! | limited | Solo no-sensibles |
| Premium | premium@example.com | PremiumPass123! | premium | No-sensibles + phone |

---

## Estructura del Proyecto

```
aws-hr-db/
├── terraform/                    # Infraestructura IaC
│   ├── main.tf
│   ├── variables.tf
│   ├── outputs.tf
│   ├── locals.tf
│   ├── terraform.tfvars
│   └── modules/
│       ├── vpc/
│       ├── rds/
│       ├── lambda/
│       ├── cognito/
│       └── api_gateway/
├── lambda/                       # Código de funciones
│   ├── extract_encrypt/
│   │   ├── main.go
│   │   ├── go.mod
│   │   └── bootstrap            # Binario compilado
│   ├── query_decrypt/
│   │   ├── main.go
│   │   ├── go.mod
│   │   └── bootstrap            # Binario compilado
│   └── shared/
│       └── crypto.go            # Utilidades AES-256-GCM
├── data/
│   └── schema.sql               # Schema de BD
├── scripts/
│   ├── build_lambdas.sh         # Compilar GO
│   ├── invoke-extract.sh        # Invocar extraction
│   ├── test_endpoints.sh        # Testing API
│   └── get_cognito_token.sh     # Obtener tokens
└── README.md
```

---

## Encriptación

### Clave de Encriptación
- Algoritmo: AES-256-GCM
- Longitud: 32 bytes (256 bits)
- Formato: Hexadecimal
- Almacenamiento: Variable de entorno de Lambda

### Campos Encriptados
- `salary` — Salario del empleado
- `phone` — Teléfono
- `address` — Dirección

### Flujo de Encriptación/Desencriptación

**Extract Lambda (Encryption)**:
```
Datos Dummy → AES-256-GCM Encrypt → Base64 → RDS
```

**Query Lambda (Decryption)**:
```
RDS → Base64 Decode → AES-256-GCM Decrypt → Retornar (si rol permite)
```

---

## Costos

### Costo Mensual Free Tier
- RDS db.t3.micro: **$0** (750h/mes)
- Lambda: **$0** (1M invocaciones/mes)
- API Gateway: **$0** (1M requests/mes)
- Cognito: **$0** (50K usuarios)
- Data Transfer: **$0** (1GB/mes)
- **Total: $0/mes** ✅

### Costo Post-Free Tier (después del año)
- RDS: ~$20/mes
- Lambda + API Gateway: ~$1-2/mes
- **Total: ~$20-25/mes**

---

## Troubleshooting

### Error: "ENCRYPTION_KEY not set"
```bash
# Asegúrate de que la variable está en terraform.tfvars
echo "encryption_key = \"<tu_clave_hex>\"" >> terraform/terraform.tfvars
terraform apply
```

### Error: "Database connection failed"
```bash
# Verifica que RDS está en el mismo VPC
aws rds describe-db-instances --query 'DBInstances[0].[DBInstanceIdentifier,DBInstanceStatus]'

# Verifica security groups
aws ec2 describe-security-groups --filters Name=group-name,Values=aws-hr-db-rds-sg
```

### Error: "Cognito token invalid"
```bash
# Verifica que el usuario existe en Cognito
aws cognito-idp list-users --user-pool-id <POOL_ID> --region us-east-1

# Reinicia la contraseña si es necesario
aws cognito-idp admin-set-user-password --user-pool-id <POOL_ID> \
  --username admin@example.com --password NewPass123! --permanent
```

---

## Limpiar recursos

```bash
# Eliminar toda la infraestructura
cd terraform
terraform destroy
```

⚠️ Esto eliminará:
- RDS instance (con snapshot final)
- Lambda functions
- API Gateway
- Cognito User Pool
- VPC y todos sus recursos

---

## Próximos Pasos

1. ✅ Deployment en AWS
2. ✅ Testing con usuarios de prueba
3. Integración con AuthN/AuthZ real
4. Agregar logging a CloudWatch
5. Configurar alertas y monitoreo
6. Implementar backup automático

---

## Documentación Adicional

- [AWS Lambda en Go](https://docs.aws.amazon.com/lambda/latest/dg/golang-handler.html)
- [API Gateway + Cognito](https://docs.aws.amazon.com/apigateway/latest/developerguide/apigateway-use-lambda-authorizer.html)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)

---

## Licencia

MIT

---

## Autor

Generado por AI Assistant - Mayo 2024
