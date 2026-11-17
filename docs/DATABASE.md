# Base de datos — decisiones de diseño

PostgreSQL 17 (Supabase). Fuente de verdad: `supabase/migrations/`. La base se reconstruye
desde cero con `npm run db:reset` (local). **No se hacen cambios manuales desde el Dashboard.**

## Migraciones

| Orden | Archivo | Contenido |
|---|---|---|
| 1 | `*_initial_schema.sql` | Esquema `private`, tablas, restricciones, índices, triggers, fila única de `site_settings` |
| 2 | `*_functions.sql` | `private.is_admin()`, `private.is_category_visible()` y privilegios de funciones |
| 3 | `*_rls_policies.sql` | `GRANT`/`REVOKE` por tabla, RLS y políticas |
| 4 | `*_storage.sql` | Bucket `site-media` y políticas de `storage.objects` |
| 5 | `*_category_images.sql` | `categories.image_path` (banner fotográfico de cada categoría en la carta) |
| 6 | `*_site_content_presentation_sections.sql` | Secciones `moments`, `name_meaning`, `experience` (textos de la presentación del cliente) |
| 7 | `*_product_ingredients.sql` | `products.ingredients` (bloque "Ingredientes" de la tarjeta; opcional) |
| 8 | `*_category_moments.sql` | Enum `day_moment`, `categories.moments` y vista `categories_with_moments` (herencia) |
| 9 | `*_category_moments_data.sql` | **Datos**: momentos iniciales de las 8 categorías raíz (idempotente) |

`functions` va **antes** que `rls_policies` (el prompt técnico las listaba al revés) porque las
políticas referencian las funciones y estas deben existir al crearlas.

Para cambios futuros: `npm run db:new <nombre>` y nunca editar una migración ya aplicada en remoto.

## Modelo

```text
categories ──< categories (parent_id, 1 nivel)
     └──< products                       (ON DELETE RESTRICT)
trainings ──< training_images            (ON DELETE CASCADE)
gallery_items · tour_images · site_content · site_settings (fila única)
auth.users ──1 profiles                  (ON DELETE CASCADE)
```

### Convenciones comunes

- `id uuid default gen_random_uuid()`, `created_at` / `updated_at timestamptz`.
- Trigger `private.set_updated_at()` en todas las tablas.
- `sort_order integer >= 0` donde el admin ordena.
- Textos con `CHECK` de longitud (y `btrim` en los obligatorios, para rechazar strings vacíos).
- Dominio `public.slug`: `^[a-z0-9]+(-[a-z0-9]+)*$`, máx. 120. Único por tabla.
- Paths de Storage validados con `private.is_image_path()` / `private.is_video_path()`:
  `<carpeta>/<nombre>.<ext>` con caracteres seguros. Imposible guardar `../`, URLs o la carpeta equivocada.

### Tablas

| Tabla | Decisiones |
|---|---|
| `categories` | `parent_id` → `categories` con `ON DELETE RESTRICT`. **Un solo nivel** forzado por trigger (`private.enforce_category_depth`): el padre debe ser raíz y una categoría con hijas no puede volverse hija. `image_path` opcional (banner de la carta), guardado bajo `products/` del bucket. |
| `products` | `category_id` `ON DELETE RESTRICT`: borrar una categoría con productos falla (`23503`), nunca borra productos en cascada. `price numeric(10,2)` **nullable** (`NULL` = sin precio publicado) con `CHECK (price >= 0)`. `description` nullable. |
| `gallery_items` | `media_type` `image`/`video`. CHECK cruzado: una imagen no tiene poster y su archivo es imagen; un video tiene archivo de video y poster opcional. `category` restringida a las 6 del cliente. `title` se usa como `alt`. |
| `tour_images` | `area` restringida a `salon`, `barra`, `rincones`, `detalles`. |
| `trainings` | Campos del prompt + **`subtitle`** (la "bajada" oficial del texto 5.8). `instructor`, `organization`, `certificate_name` nullable: se completan cuando se confirmen con los diplomas. |
| `training_images` | **Tabla** (no arreglo de paths): cada foto tiene orden y `alt_text` propios, se edita/borra individualmente y la limpieza de Storage es foto por foto. `ON DELETE CASCADE` borra filas, **no archivos**: la Server Action debe borrar los archivos (fotos, portada y certificado). |
| `site_content` | `section` única entre 10 claves fijas. `items jsonb` para listas (hoy solo `values`): CHECK `items IS NULL OR (section = 'values' AND jsonb_typeof(items) = 'array')`. La forma de cada ítem (`{title, description}`) se valida con Zod. Se eligió jsonb sobre una tabla porque son 5 ítems que siempre se editan juntos. |
| `site_settings` | **Fila única**: columna `singleton boolean unique check (singleton)`. La fila se crea en la migración (es estructura, existe también en producción); la API solo permite `UPDATE`. URLs de redes/Maps con CHECK de dominio. `opening_hours jsonb` (arreglo por día, forma validada con Zod). Sin `external_menu_url` (la carta es interna). |
| `profiles` | `id` → `auth.users` `ON DELETE CASCADE`. `role` restringido a `admin` y **sin default**: un perfil solo existe si se creó deliberadamente. Un usuario autenticado sin fila en `profiles` no tiene permisos de escritura. |

### Momentos del día (`categories.moments`)

La carta se puede filtrar por **mañana / mediodía / tarde-noche** (tarjetas de la home →
`/carta?momento=manana|mediodia|tarde-noche`).

- Enum `public.day_moment`: `morning`, `midday`, `evening`. El front traduce a la URL
  (`manana`, `mediodia`, `tarde-noche`) en `src/features/menu/moments.ts`.
- `categories.moments day_moment[] not null default '{}'`: momentos **propios**.
- **Herencia en un solo lugar**: la vista `public.categories_with_moments` expone
  `effective_moments` = momentos propios, o los del padre si la subcategoría no tiene.
  Una categoría raíz con `{}` no tiene momento: solo aparece en la carta completa.
- **Sin excepciones por producto**: un producto aparece en los momentos de su categoría.
- **Seguridad**: la vista es `security_invoker = true` → aplica la RLS de `categories` con los
  permisos de quien consulta (anon solo ve categorías visibles). Solo tiene `GRANT SELECT` y además
  no es actualizable (tiene un join). Escribir `moments` lo cubren los GRANT y políticas de
  `categories`: solo el admin. Tests: `supabase/tests/database/02_category_moments.test.sql`.

Valores iniciales (seed + migración de datos, que solo completa categorías con `moments = '{}'`
y por eso nunca pisa lo editado desde el panel):

| Categoría | Mañana | Mediodía | Tarde/Noche | Estado |
|---|:-:|:-:|:-:|---|
| Cafetería | ✅ | ✅ | ✅ | ⚠️ **A confirmar** (se asume café todo el día) |
| Sandwiches | ✅ | ✅ | | Presentación del equipo |
| Desayunos & Brunch | ✅ | | | Presentación del equipo |
| Pastelería | ✅ | | ✅ | ⚠️ **A confirmar** (merienda) |
| Almuerzos | | ✅ | | Presentación del equipo |
| Tapas & para compartir | | | ✅ | Presentación del equipo |
| Postres | | ✅ | ✅ | ⚠️ **A confirmar** |
| Cocktails | | | ✅ | Presentación del equipo |

Las subcategorías quedan en `{}` y heredan (p. ej. Menú del día → mediodía). Se editarán desde el panel.

### Índices

Solo los que tienen justificación a esta escala (decenas o cientos de filas):

| Índice | Motivo |
|---|---|
| `categories (parent_id, sort_order)` | FK: el `RESTRICT` busca hijas al borrar; listado de subcategorías. |
| `products (category_id, sort_order)` | FK: el `RESTRICT` busca productos al borrar una categoría; listado de la carta. |
| `training_images (training_id, sort_order)` | FK: cascade al borrar; listado de fotos. |
| `UNIQUE` de slugs, `section` y `singleton` | Integridad (crean su índice automáticamente). |

No se indexan `is_published` / `is_active`: con tablas tan chicas un seq scan es más rápido.

## Seed (`supabase/seed.sql`, solo desarrollo)

- Carta completa del `CLAUDE.md` §7: 8 categorías, 13 subcategorías, 68 productos, con `price` y
  `description` en `NULL`. Destacados: En Compañía Coffee, En Compañía Sour, Bruma.
- "Menú del día · Opción 1/2": placeholders estructurales de la subcategoría Menú del día.
- `site_content`: textos oficiales **literales** (§4 y §5). Las citas se guardan sin « »: las agrega el diseño.
- `trainings`: café (Doppio Project, CSP Barista Skills – Foundation (SCA)) y coctelería
  (sin institución ni certificado). Instructores en `NULL` en ambos.
- Sin dirección, teléfono, horarios, redes, imágenes ni usuarios.
- ⚠️ **Borradores de desarrollo** (pedido del desarrollador para previsualizar la carta):
  descripción e ingredientes en los **68 productos** (los clásicos con su receta estándar; los
  de autor, Menú del día y Pinchos rotativos con textos genéricos que no afirman la receta de la
  casa) y **precios ficticios**. Solo existen en el seed local: los reales se cargan desde el CMS.
- Subtítulos de cada sección de la carta en `categories.description` (oficiales donde existen).

> El seed **no** corre en producción. La carga de contenido inicial en el proyecto remoto se
> define en la Fase 7 (desde el CMS o con un script de contenido versionado).

## Tipos TypeScript

`npm run types:gen` → `EnCompa-iaFront/src/types/database.types.ts` (no editar a mano).
Regenerar después de cada migración.
