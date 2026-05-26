# TODO — Antes de producción

Lista de pendientes técnicos identificados durante el desarrollo del POC. Ordenado por severidad. Las referencias `file:line` apuntan al estado actual del repo.

Severidad:
- **[P0]** Bloqueante — no llevar a producción sin esto.
- **[P1]** Importante — resolver antes del primer release real.
- **[P2]** Hardening — debería estar antes de escalar usuarios/datos.
- **[P3]** Mejora — nice-to-have, no bloquea.

---

## Seguridad

### [P0] Bearer tokens están siendo loggeados en CloudWatch
`lambda/query_decrypt/main.go:55` hace `log.Printf("Received request: %v", request)` que imprime el `APIGatewayProxyRequest` completo, **incluyendo el header `Authorization: Bearer <jwt>`**. Cualquiera con acceso de lectura a CloudWatch Logs puede capturar tokens válidos y replicarlos hasta que expiren (1h por default). Verificado en los logs del POC.

**Fix:** sanitizar antes de loggear — clonar `request.Headers`, borrar `Authorization` (y cualquier `Cookie`), o simplemente loggear solo `request.HTTPMethod`, `request.Path`, `request.QueryStringParameters`, y el claim `sub`/`cognito:username` del authorizer.

### [P0] TLS al RDS sin validación de certificado
`lambda/{query_decrypt,extract_encrypt}/main.go` usan `sslmode=require`. Esto cifra la conexión pero **no valida** que el certificado del servidor sea efectivamente de tu instancia RDS — vulnerable a MITM dentro del VPC si un atacante logra desplegarse ahí.

**Fix:** subir a `sslmode=verify-full`, embebiendo el bundle de CA de RDS (`global-bundle.pem` de AWS) en el binario Go (`go:embed`) y usando el connection-string param `sslrootcert`. Documentado en https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/UsingWithRDS.SSL.html

### [P0] Secrets en `terraform.tfvars` y state local
- `db_password`, `encryption_key`, `cognito_*_password` viven en `terraform/terraform.tfvars` (presumiblemente fuera de git, pero plaintext en disco).
- El state de Terraform es **local** (no hay bloque `backend` en `terraform/main.tf:1`). Esto guarda **todos** los secrets en plaintext en `terraform.tfstate`, no es shared, y no tiene state locking.

**Fix:**
- Backend remoto: S3 con `encrypt = true` + DynamoDB para locking.
- Secrets: AWS Secrets Manager (o SSM Parameter Store con `SecureString`). La Lambda los lee al arrancar (cachear en memoria entre invocaciones tibias). Eliminar `db_password`, `encryption_key`, etc. de las env vars del Lambda y del `tfvars`.
- `terraform.tfvars` debe estar en `.gitignore` (verificar).

### [P0] Auth flow para consumers reales
`USER_PASSWORD_AUTH` es OK para CLI/testing pero anti-patrón para integraciones reales — obliga a cada consumer a almacenar credenciales de usuario humano.

**Fix por tipo de consumer:**
- **Servicio → servicio (M2M):** OAuth2 Client Credentials. App client en Cognito con `generate_secret=true` por cada consumer, Resource Server con scopes (`employees/read`, `employees/write`), y el authorizer del API GW autoriza por scope en vez de grupo. Quitar `ALLOW_USER_PASSWORD_AUTH` cuando no quede script que lo use.
- **App con usuarios finales (web/mobile):** Authorization Code + PKCE vía hosted UI.

### [P1] No hay MFA en Cognito
Política actual (`terraform/modules/cognito/main.tf:4-10`): 8 caracteres mínimos, sin símbolos requeridos, sin MFA. Para una BD de empleados con PII, al menos los usuarios `admin` deberían tener MFA obligatorio.

**Fix:** `mfa_configuration = "ON"` (o `"OPTIONAL"` con enforcement por grupo) + `software_token_mfa_configuration` en el user pool. Endurecer password policy (12+ chars, símbolos).

### [P1] Rotación de la llave de encripción
`encryption_key` (AES-256-GCM) es estática y vive en env var. Si se compromete, todos los registros existentes quedan expuestos y re-cifrarlos requiere downtime + custom code. No hay key versioning.

**Fix:** envelope encryption con KMS — un KMS CMK como key-encryption-key (KEK), genera data keys frescos por registro o por batch, almacena el data key cifrado junto al ciphertext. Rotación de KMS habilitada automáticamente. Permite rotar la KEK sin re-cifrar datos.

### [P1] IAM Lambda role demasiado amplio
`terraform/modules/lambda/main.tf:38-44` da `ec2:CreateNetworkInterface|Delete|Describe` con `Resource = "*"`. Necesario para VPC, pero se puede restringir.

**Fix:** usar la policy administrada `AWSLambdaVPCAccessExecutionRole` (sigue siendo `*` pero es la práctica recomendada) y condicionar con `aws:RequestTag` o limitar a VPCs/subnets específicos vía `Condition`.

### [P2] WAF en API Gateway
Sin protección contra SQLi/XSS/scrapers/bot traffic ni rate-limiting por IP a nivel de capa 7.

**Fix:** AWS WAFv2 asociado al stage del API GW. Empezar con la managed rule group `AWSManagedRulesCommonRuleSet` + `AWSManagedRulesAmazonIpReputationList` + un rate-limit rule por IP (~2000 req/5min).

### [P2] Throttling y usage plans
API GW sin throttling configurado. Un consumer descontrolado (o un atacante) puede generar costos enormes y agotar concurrencia de Lambda.

**Fix:** `aws_api_gateway_method_settings` con `throttling_rate_limit` / `throttling_burst_limit`. Para clientes con API key (futuro), `aws_api_gateway_usage_plan` por tier.

---

## Datos / RDS

### [P1] RDS sin encryption-at-rest verificable
`terraform/modules/rds/main.tf` no declara `storage_encrypted`. Para `db.t3.micro` el default histórico era `false`. Datos cifrados a nivel aplicación (los campos sensibles) pero el resto (PII no marcada como sensible: nombre, email, depto) queda en claro en disco/snapshots.

**Fix:** `storage_encrypted = true` + `kms_key_id` apuntando a una CMK del cliente. **Nota:** este atributo es inmutable post-creación; requiere snapshot + restore para habilitarlo en un RDS existente.

### [P1] Single-AZ
`multi_az = false` en `terraform/modules/rds/main.tf:14`. Una falla de AZ implica downtime.

**Fix:** `multi_az = true` antes de SLA real. Costo: ~2x en RDS. No aplica a free tier.

### [P2] Schema bootstrap dentro del Lambda
Hoy el schema se crea on-demand desde la primera invocación del Lambda extract. Esto introduce race conditions si dos invocaciones concurrentes son las primeras, y dificulta auditar cambios de schema.

**Fix:** migrations con `golang-migrate` o `goose`, corridas desde CI o desde una Lambda one-shot dedicada con concurrencia 1. Los Lambdas de runtime asumen que el schema ya existe.

---

## Observabilidad

### [P1] Sin DLQ ni manejo de errores asíncronos
Los Lambdas no tienen Dead Letter Queue. Si una invocación falla y no es síncrona (ej. retries internos), los eventos se pierden sin trace.

**Fix:** `aws_lambda_function.dead_letter_config` apuntando a una SQS por Lambda + alarma de CloudWatch si la queue tiene mensajes.

### [P1] No hay alarmas
Cero alarmas configuradas. No te enteras si las Lambdas están fallando masivamente, si RDS está al 90% de CPU, o si el API gateway está devolviendo 5xx.

**Fix mínimo:**
- Alarma sobre `AWS/Lambda Errors > 5 en 5min` (por función).
- Alarma sobre `AWS/RDS CPUUtilization > 80%` (5min sostenidos).
- Alarma sobre `AWS/ApiGateway 5XXError > 1% en 5min`.
- Output a SNS topic con suscripción a email/PagerDuty/Slack.

### [P2] Sin tracing distribuido
Imposible saber cuánto tarda RDS vs cuánto tarda la Lambda en sí cuando hay latencia.

**Fix:** `tracing_config { mode = "Active" }` en cada Lambda + AWS X-Ray SDK envolviendo `database/sql` y `net/http`. Casi gratis.

### [P3] Log retention
7 días (`terraform/modules/lambda/main.tf:65,71`). Fine para dev. Para producción, considerar archive a S3 (cheap storage) con lifecycle policy.

---

## Robustez del código

### [P1] Sin cap en paginación
`lambda/query_decrypt/main.go:109` lee `limit` del query string sin tope. `?limit=1000000` haría un query masivo, consumir toda la memoria del Lambda, y potencialmente DoS al RDS.

**Fix:** clamp explícito (`if limit > 100 { limit = 100 }`) + default sano si no viene (`if limit <= 0 { limit = 20 }`). Mismo tratamiento para `page`.

### [P2] Connection pooling entre invocaciones
Cada invocación abre y cierra una conexión a RDS (`connectDB()` + `defer db.Close()` en `lambda/query_decrypt/main.go:69-74`). En cold start es ~50-150ms extra; en warm start desperdicia conexiones del pool de RDS (limitado en t3.micro).

**Fix:** declarar `var db *sql.DB` a nivel paquete, inicializar en `init()`, reusarlo entre invocaciones warm. `database/sql` ya maneja un pool internamente — configurar `SetMaxOpenConns(2)` para no agotar RDS.

### [P2] Errores del cliente devuelven 500
`createErrorResponse(500, ...)` se usa para todo: token sin claims, role inválido, DB caída. Un cliente que pasa un `id` que no existe debería ver 404, no 500.

**Fix:** mapear tipos de error a status codes apropiados (400, 401, 403, 404, 500). Que el body devuelva un correlation/request-id que el cliente pueda mandar en bug reports — sin exponer detalles internos.

---

## Diseño del API / Contrato

### [P2] Spec OpenAPI 3.x del API (con `x-required-role` por campo)
Hoy no hay spec formal. La documentación viva en `README.md` y `CLAUDE.md` se desincroniza con el código en cuanto cambia algo. Sin spec no hay generación de SDK (TypeScript, Python, Go), no hay validación request/response automatizada en CI, no hay mock server para frontends, y los consumers (humanos o servicios) tienen que leer el código Go para saber qué esperar.

**Por qué ahora importa (no antes):**
- El contrato se acaba de estabilizar — las responses ahora omiten completamente los campos que el usuario no tiene permiso de ver (en lugar de enviarlos como `null`). Ver ADR-001 en `README.md`.
- Si vas a abrir el API a consumers reales (Client Credentials, ver P0 de Auth en este mismo TODO), un consumer integra mucho más rápido contra un OpenAPI que contra un README.

**Fix mínimo:**
- Crear `openapi/spec.yaml` (OpenAPI 3.1) con los 2 endpoints, sus query params, y los schemas `Employee`, `QueryResponse`, `ErrorResponse`.
- Documentar el `securityScheme` Cognito (bearer JWT) referenciando el authorizer.
- Documentar el campo `_meta` (`role`) que ambos endpoints devuelven.
- Marcar **cada campo sensible** como **no requerido** (not in `required`) y documentar con `x-required-role`:
  ```yaml
  Employee:
    required: [employee_id, first_name, last_name, email, department, hire_date]
    properties:
      first_name: { type: string }
      phone:
        type: string
        x-required-role: premium       # Omitted si el rol del caller no aplica
        description: "Only present if caller's role has access"
      address:
        type: string
        x-required-role: admin
      salary:
        type: string
        x-required-role: admin
  ```
- `x-required-role` no es estándar OpenAPI pero **es la convención** para extensiones (cualquier campo `x-*` es válido). Sirve como documentación + base para generar matrices de permisos o checks de policy automáticos.

**Pasos para que no se desincronice:**
- Generar tipos Go desde la spec con `oapi-codegen` (o lo opuesto: derivar la spec de structs Go anotados). En esta etapa de POC, mantener la spec a mano es razonable; cuando crezca, considerar codegen bidireccional.
- CI: validar que la spec es válida (`spectral lint`), idealmente que las responses reales en tests de integración matchean la spec (`prism` o similar).
- Publicar la spec en Swagger UI o Redoc para que los consumers la naveguen.

**Herramientas recomendadas:**
- `oapi-codegen` (Go) para generar handlers/types tipados desde la spec.
- `spectral` para linting.
- `redocly-cli` o `swagger-ui-express` para servir docs interactivos.
- En API Gateway, se puede importar la spec con `aws_api_gateway_rest_api.body` y declarar las rutas/integrations desde ahí — eso convierte la spec en source-of-truth incluso para infra.

---

## Operaciones / CI/CD

### [P1] Sin pipeline de CI/CD
Deploys manuales con `make deploy`. Sin gates, sin diff visible en PR, sin tests automatizados antes de aplicar.

**Fix:** GitHub Actions (o equivalente):
- En PR: `terraform fmt -check`, `terraform validate`, `terraform plan` (output como comentario), `go vet`, `go test`, build de los binarios.
- En merge a main: `terraform apply -auto-approve` solo si el plan pasó review.

### [P2] Tags de cost allocation
Las resources tienen `Name` pero no `Environment`, `Owner`, `CostCenter`. Hace imposible cost allocation por equipo/proyecto cuando hay múltiples stacks.

**Fix:** `default_tags` en el provider AWS de `terraform/main.tf` con las tags estándar de tu org.

### [P3] Sin tests
No hay tests unitarios para el código Go, ni `terraform plan` automatizado en PRs.

**Fix:** tests al menos del módulo `lambda/shared/crypto.go` (round-trip encrypt/decrypt, key wrong, nonce reuse). Para Terraform, `terraform validate` mínimo, idealmente `tflint` y `checkov`.

---

## Referencias

- AWS RDS SSL/TLS: https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/UsingWithRDS.SSL.html
- Cognito Client Credentials: https://docs.aws.amazon.com/cognito/latest/developerguide/cognito-user-pools-app-idp-settings.html
- Terraform S3 backend: https://developer.hashicorp.com/terraform/language/settings/backends/s3
- AWS WAF managed rule groups: https://docs.aws.amazon.com/waf/latest/developerguide/aws-managed-rule-groups-list.html
