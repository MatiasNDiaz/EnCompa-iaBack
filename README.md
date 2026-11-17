# En Compañía — Backend (Supabase)

Backend gestionado con **Supabase**: PostgreSQL, Auth, Storage y Row Level Security.
No hay servidor propio (ni Express ni NestJS): la lógica de acceso vive en la base de datos
mediante migraciones SQL versionadas y políticas RLS.

> Estado: **Fase 2** completa (esquema, RLS, Storage, seed y tests de seguridad).

## Requisitos

| Herramienta    | Versión usada | Para qué                                     |
| -------------- | ------------- | -------------------------------------------- |
| Node.js / npm  | 26 / 11       | Ejecutar el Supabase CLI local y los scripts |
| Docker Desktop | 28            | Levantar Supabase en local (`db:start`)      |
| Supabase CLI   | 3.1.0         | devDependency del proyecto (no es global)    |

## Instalación y primer uso

```bash
npm install          # instala el Supabase CLI local
npm run db:start     # levanta Supabase local en Docker (la primera vez descarga imágenes)
npm run db:reset     # aplica migraciones + seed
npm run db:test      # tests pgTAP de RLS
npm run test:security  # tests de seguridad contra la API HTTP local
npm run types:gen    # genera los tipos TS para el frontend
npm run db:status    # muestra URL, publishable key y Studio
```

Supabase local expone:

- API: `http://127.0.0.1:54321`
- Studio: `http://127.0.0.1:54323`
- Emails de prueba (Mailpit): `http://127.0.0.1:54324`

## Comandos

| Comando                 | Descripción                                                          |
| ----------------------- | -------------------------------------------------------------------- |
| `npm run db:start`      | Inicia Supabase local                                                |
| `npm run db:stop`       | Detiene Supabase local                                               |
| `npm run db:reset`      | **Local**: recrea la base aplicando todas las migraciones + seed     |
| `npm run db:new <n>`    | Crea una nueva migración vacía (con timestamp)                       |
| `npm run db:lint`       | Analiza el esquema en busca de errores                               |
| `npm run db:test`       | Tests pgTAP (`supabase/tests/database/`)                             |
| `npm run test:security` | `scripts/test-security-api.mjs`: ataques por rol vía REST/Auth/Storage (solo local) |
| `npm run types:gen`     | `scripts/gen-types.mjs`: tipos TS → `../EnCompa-iaFront/src/types/database.types.ts` |
| `npm run admin:create`  | `scripts/create-admin.mjs`: crea/promueve el administrador (local por defecto) |

## Estructura

```text
supabase/
├── config.toml                 # configuración del entorno local
├── migrations/                 # fuente de verdad del esquema
│   ├── *_initial_schema.sql    # tablas, restricciones, índices, triggers
│   ├── *_functions.sql         # is_admin(), is_category_visible()
│   ├── *_rls_policies.sql      # privilegios + RLS
│   └── *_storage.sql           # bucket site-media + políticas
├── tests/database/             # tests pgTAP
└── seed.sql                    # datos de DESARROLLO (carta, textos oficiales, capacitaciones)
scripts/
├── gen-types.mjs               # tipos TS para el frontend
├── create-admin.mjs            # alta segura del administrador
└── test-security-api.mjs       # tests de seguridad HTTP
docs/
├── DATABASE.md                 # modelo y decisiones
├── SECURITY.md                 # RLS, roles, creación del admin
└── STORAGE.md                  # bucket, límites, consistencia Storage ↔ DB
```

## Base de datos, RLS y Storage

Resumen (detalle en `docs/`):

- 9 tablas, todas con RLS. Visitantes solo leen contenido publicado/activo; solo el admin escribe.
- Rol verificado con `private.is_admin()` (`SECURITY DEFINER`, sin recursión, no expuesta por RPC).
- Bucket público `site-media` (50 MiB, JPEG/PNG/WebP/AVIF/MP4/WebM); escritura solo admin y solo
  en las 6 carpetas permitidas.
- Categorías con productos no se pueden borrar (`ON DELETE RESTRICT`).

## Creación del administrador

```bash
npm run admin:create   # local por defecto; pide email, nombre y contraseña (sin eco)
```

Detalle y uso contra remoto en [docs/SECURITY.md](docs/SECURITY.md#creación-del-administrador-procedimiento-seguro).
Nunca hay credenciales en el repositorio y no existe registro público.

## Decisiones de configuración (config.toml)

- `enable_signup = false`: no existe registro público.
- Contraseñas: mínimo 12 caracteres con mayúsculas, minúsculas y dígitos.
- `realtime` y `storage.vector` desactivados: el proyecto no los usa.
- Límite global de subida local: 50 MiB (igual al del bucket).

> `config.toml` solo afecta al entorno **local**. En el proyecto remoto estas opciones se
> configuran en el Dashboard (o con `supabase config push`, previa autorización).

## Proyecto remoto

Todavía no está vinculado. **No ejecutar `supabase link`, `db push` ni `config push` sin
autorización.** El procedimiento paso a paso se documenta en la Fase 7. Al vincular, revisar:
registro deshabilitado, política de contraseñas y límite global de subida de Storage.
