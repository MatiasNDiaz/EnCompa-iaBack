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
| 10 | `*_storage_folders.sql` | Carpetas `categories/` y `specials/` en las políticas de subida de `site-media` |
| 11 | `*_category_banners.sql` | Banner en la base: `image_path` → carpeta `categories/`, `image_is_illustrative`, vista con la columna nueva |
| 12 | `*_category_banners_data.sql` | **Datos**: texto inicial de los 8 banners (solo donde está vacío) |
| 13 | `*_product_stock.sql` | `products.out_of_stock_on`, `private.today_ar()` y campo calculado `out_of_stock_today` |
| 14 | `*_category_reorder.sql` | `public.reorder_categories(uuid[])`: reordenar secciones hermanas en una transacción (solo admin) |
| 15 | `*_daily_specials.sql` | Tabla `daily_specials` (plato del día) con sus **3 filas fijas**, RLS y `private.is_valid_ingredient_list()` |
| 16 | `*_daily_specials_ingredients_text.sql` | `daily_specials.ingredients` pasa de lista (`text[]`) a texto libre (≤ 500), como en productos. Conserva los datos (une con ", ") |
| 17 | `*_site_settings_email.sql` | `site_settings.email` (≤ 254, formato validado) y Facebook acepta `web.` / `m.` |
| 18 | `*_site_settings_contact_data.sql` | Dirección, WhatsApp, teléfono, email y redes del local (solo si estaban vacíos) |
| 19 | `*_site_settings_map_embed.sql` | El mapa acepta el embed por dirección (sin clave de API) y se carga el del local |
| 20 | `*_tapeo.sql` | "Tapas" → **"Tapeo"**: categoría (nombre y slug `tapeo-y-para-compartir`), descriptor del hero, bloque de la propuesta y tarjeta "Bar y tapeo". Solo si el texto seguía siendo el original |
| 21 | `*_opening_hours.sql` | **Horarios**: validación estricta de `site_settings.opening_hours`, horario genérico inicial (todos los días de 9:00 a 23:00, solo si estaba vacío), tabla `opening_exceptions` (días especiales) con RLS y `public.purge_past_opening_exceptions()` |
| 22 | `*_opening_hours_lint.sql` | Misma función de validación con una variable renombrada (aviso de `db lint`) |
| 23 | `*_opening_hours_today.sql` | Los días especiales usan `private.today_ar()` (la que ya existía) y se borra la duplicada `today_in_cordoba()` |

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
| `site_settings` | **Fila única**: columna `singleton boolean unique check (singleton)`. La fila se crea en la migración (es estructura, existe también en producción); la API solo permite `UPDATE`. URLs de redes/Maps con CHECK de dominio. `opening_hours jsonb` (horario semanal, validado en la base: ver "Horarios"). Sin `external_menu_url` (la carta es interna). |
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
| Tapeo & para compartir | | | ✅ | Presentación del equipo |
| Postres | | ✅ | ✅ | ⚠️ **A confirmar** |
| Cocktails | | | ✅ | Presentación del equipo |

Las subcategorías quedan en `{}` y heredan (p. ej. Menú del día → mediodía). Se editan desde el panel.

### Banners de la carta (`categories.image_path`, `description`, `image_is_illustrative`)

El banner de cada sección sale de la base (antes la foto salía del código por slug):

- `image_path`: foto en `site-media/categories/`. `NULL` → la web muestra la textura de marca.
- `description`: texto breve bajo el título.
- `image_is_illustrative`: la foto es de banco (no del local) → la web la rotula "Imagen
  ilustrativa". Al subir o quitar la foto desde el panel vuelve a `false`.
- Valores iniciales: textos con la migración 12; fotos con `npm run media:banners`
  (ver `docs/STORAGE.md`). Se decidió **no renombrar** las columnas a `banner_*`: ya eran el
  banner y renombrar obligaba a tocar vista, tipos y queries sin beneficio.

### Disponibilidad: oculto vs. sin stock por hoy

| | `is_available = false` | `out_of_stock_on = hoy` |
|---|---|---|
| En el panel | "Oculto de la carta" (p. ej. de temporada) | "Sin stock hoy" |
| Web pública | **No aparece** (la RLS no lo entrega) | **Aparece** atenuado con la etiqueta |
| Cómo vuelve | Lo muestra el admin | Solo al día siguiente, o "Disponible otra vez" (`NULL`) |

- "Hoy" = `private.today_ar()` = fecha en `America/Argentina/Cordoba`.
- `public.out_of_stock_today(products)` es un **campo calculado** de PostgREST
  (`select=*,out_of_stock_today`); lo usan el panel y los tests.
- La web pública recibe la **fecha** (no un sí/no) y decide al mostrar: el servidor manda su
  estimación y el navegador la confirma con la fecha de Córdoba. Así una página en caché del día
  anterior no deja un producto atenuado.
- La RLS pública no cambió: ya filtraba solo por `is_available`.
- Tests: `supabase/tests/database/03_panel_carta.test.sql`.

### Plato del día (`daily_specials`)

Una fila por momento del día (`moment day_moment UNIQUE`): mañana, mediodía y tarde/noche.

- **Las 3 filas se crean en la migración** (vacías y sin publicar), así existen también en
  producción. El admin solo tiene `UPDATE`: no puede crear ni borrar filas ("Vaciar" en el panel
  pone los campos en `NULL` y borra la foto).
- Campos: `image_path` (`site-media/specials/`), `title`, `subtitle`, `body`, `price numeric(10,2)`
  opcional (≥ 0), `ingredients text` opcional (texto libre, hasta 500 caracteres; migración 16:
  cargarlos de a uno en el panel era tedioso), `is_published`.
- **No se publica sin foto y sin título**: `CHECK (not is_published or (image_path is not null and title is not null))`.
- RLS: anon y no-admin ven solo los publicados; el admin ve y edita los 3.
- En la web se ven en la carta, filtro "Platos del día" (`/carta?ver=platos-del-dia`), al que
  lleva el ítem "Plato del día" del menú. Cada plato muestra su horario (provisorio, a confirmar
  con los dueños) definido en `EnCompa-iaFront/src/config/specials.ts`: mañana 06:00–11:59,
  mediodía 12:00–15:59, tarde/noche 16:00–05:59.
- Tests: `supabase/tests/database/04_daily_specials.test.sql`.

### Horarios (`site_settings.opening_hours` y `opening_exceptions`)

Se editan desde el panel (`/admin/horarios`) y se ven en Ubicación y en el pie de la web.

- **Horario semanal**: se reutilizó el `jsonb` que ya existía (una tabla no aportaba nada: son
  7 días que se editan y se guardan juntos). Forma:
  `[{ "day": "monday", "ranges": [{ "open": "09:00", "close": "15:00" }, …] }, …]`.
  `CHECK private.is_valid_opening_hours(opening_hours)`:
  - los 7 días, una vez cada uno; sin franjas = cerrado;
  - hasta 2 franjas por día, `HH:MM`, en orden y sin superponerse;
  - cierre menor que la apertura = **termina al día siguiente** (ej. 19:00 → 01:00): solo la
    última franja del día y sin pisar la primera del día siguiente (también de domingo a lunes).
  - El panel exige marcar «Cierra al día siguiente» a mano; la base lo deduce de las horas.
- **Días especiales** (`opening_exceptions`): `date` única, `type` `closed` | `custom`,
  `ranges` (obligatorio y 1–2 franjas solo en `custom`; `NULL` en `closed`), `note` opcional
  (≤ 120, se ve en la web). Reemplaza al horario semanal ese día.
- **RLS**: anon y no-admin leen el horario y los días especiales **de hoy en adelante**
  (`date >= private.today_ar()`, hora de Córdoba); solo el admin crea, edita y borra, y ve
  también los pasados.
- **Limpieza**: `public.purge_past_opening_exceptions()` borra los días que ya pasaron y
  devuelve cuántos (`SECURITY INVOKER`: para quien no es admin borra 0). No es automática: el
  panel muestra "Borrar N días que ya pasaron".
- **Horario genérico inicial** (migración 21): todos los días de 9:00 a 23:00, solo si no había
  horario. El dueño lo cambia desde el panel.
- Tests: `supabase/tests/database/05_opening_hours.test.sql` y `scripts/test-security-api.mjs`.

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
- Las fotos de los banners NO van en el seed (un `.sql` no sube archivos): `npm run db:reset`
  corre después `scripts/upload-category-banners.mjs`.

> El seed **no** corre en producción. La carga de contenido inicial en el proyecto remoto se
> define en la Fase 7 (desde el CMS o con un script de contenido versionado).

## Tipos TypeScript

`npm run types:gen` → `EnCompa-iaFront/src/types/database.types.ts` (no editar a mano).
Regenerar después de cada migración.
