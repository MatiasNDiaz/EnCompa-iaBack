# Storage — bucket `site-media`

## Configuración

| Propiedad | Valor | Motivo |
|---|---|---|
| Creación | Migración `*_storage.sql` | `config.toml` solo afecta el entorno local; la migración se aplica igual en remoto y queda versionada |
| Lectura | Pública | Las imágenes son de una web pública. Se accede por URL pública (`getPublicUrl()`), sin listar |
| Límite por archivo | **50 MiB** | Techo para videos de la galería |
| MIME permitidos | `image/jpeg`, `image/png`, `image/webp`, `image/avif`, `video/mp4`, `video/webm` | Formatos web modernos. **SVG excluido** (puede contener scripts: riesgo de XSS) |

### Límites por tipo

Supabase admite **un solo límite por bucket**, por eso el bucket tiene 50 MiB (videos) y las
imágenes se limitan a **8 MiB** en dos lugares:
1. El formulario del CMS (Zod en el cliente).
2. **El servidor**: la Server Action valida tipo MIME y tamaño del archivo subido antes de guardar
   el path en la base. Si no cumple, borra el archivo y devuelve el error.

### ⚠️ Límite global del proyecto remoto

Además del límite del bucket, cada proyecto de Supabase tiene un **límite global de subida** que
depende del plan y se configura en el Dashboard (Storage → Settings). El efectivo es el menor de
los dos. En local está en 50 MiB (`config.toml`). **Revisarlo al vincular el proyecto remoto.**

## Organización

```text
site-media/
├── branding/       logo (raster), imagen/video principal
├── products/       fotos de productos
├── gallery/        fotos y videos de la galería (+ posters)
├── tour/           fotos del recorrido
├── trainings/      portadas, certificados y fotos del equipo
└── institutional/  imágenes de site_content
```

Los logos en **SVG** (exportados del original) van en `EnCompa-iaFront/public/brand/`, versionados
con el código, no en el bucket.

## Políticas (`storage.objects`, solo `bucket_id = 'site-media'`)

| Operación | Quién | Condición extra |
|---|---|---|
| SELECT (listar/leer por API) | admin | — |
| INSERT | admin | Primera carpeta ∈ las 6 permitidas |
| UPDATE (reemplazo) | admin | Ídem |
| DELETE | admin | — |
| Lectura por URL pública | cualquiera | (no pasa por RLS: bucket público) |

`anon` y los usuarios autenticados sin rol admin no pueden subir, reemplazar, borrar ni listar.

## Reglas para el código (Fases 3 y 5)

- **Subida desde el cliente directo a Storage** con la sesión del admin (las políticas protegen),
  y luego una Server Action guarda el path. Evita el límite de body de las Server Actions y no
  carga archivos en memoria del servidor.
- **Nombres**: `<carpeta>/<uuid>.<ext>`, extensión derivada del MIME validado. Nunca el nombre
  original. La base valida el formato del path (`private.is_image_path` / `is_video_path`).
- **Solo se guarda el path**, nunca binarios ni URLs. URLs con `getPublicUrl()`.
- **Consistencia Storage ↔ PostgreSQL:**
  - Reemplazar: subir el nuevo → actualizar la fila → borrar el anterior. Si falla la fila,
    borrar el recién subido.
  - Eliminar: borrar la fila → borrar el archivo. Si falla el borrado del archivo, se registra
    (queda huérfano, nunca una fila apuntando a un archivo inexistente).
  - `training_images` se borra en cascada con su capacitación: la Server Action borra también
    todos los archivos asociados (fotos, portada y certificado).
- El borrado directo por SQL de `storage.objects` está bloqueado por Supabase (trigger
  `protect_objects_delete`): siempre usar la API de Storage.
