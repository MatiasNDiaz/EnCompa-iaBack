-- =============================================================================
-- En Compañía · 04 · Storage: bucket `site-media` y políticas
--
-- Decisión: el bucket se crea por migración (no en config.toml) porque
-- config.toml solo configura el entorno local; la migración se aplica igual en
-- local y en el proyecto remoto (`db push`), y queda versionada.
-- Ver docs/STORAGE.md.
-- =============================================================================

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'site-media',
  'site-media',
  -- Público: las imágenes son de una web pública. La lectura por URL pública no
  -- pasa por RLS; las escrituras sí.
  true,
  -- 50 MiB: techo para los videos de la galería. Las imágenes se limitan a 8 MiB
  -- en el formulario y en el servidor (Supabase admite un solo límite por bucket).
  52428800,
  array[
    'image/jpeg', 'image/png', 'image/webp', 'image/avif',
    'video/mp4', 'video/webm'
  ]
)
on conflict (id) do update set
  public             = excluded.public,
  file_size_limit    = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

-- -----------------------------------------------------------------------------
-- Políticas sobre storage.objects (solo para este bucket).
-- Sin política para anon: el público accede por URL pública (getPublicUrl), no
-- puede listar ni escribir.
-- Las carpetas permitidas son la organización lógica del bucket; cualquier otra
-- ruta se rechaza.
-- -----------------------------------------------------------------------------

create policy "site-media: admin lista y lee"
  on storage.objects for select to authenticated
  using (bucket_id = 'site-media' and (select private.is_admin()));

create policy "site-media: admin sube en carpetas permitidas"
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'site-media'
    and (select private.is_admin())
    and (storage.foldername(name))[1] in
      ('branding', 'products', 'gallery', 'tour', 'trainings', 'institutional')
  );

create policy "site-media: admin reemplaza en carpetas permitidas"
  on storage.objects for update to authenticated
  using (bucket_id = 'site-media' and (select private.is_admin()))
  with check (
    bucket_id = 'site-media'
    and (select private.is_admin())
    and (storage.foldername(name))[1] in
      ('branding', 'products', 'gallery', 'tour', 'trainings', 'institutional')
  );

create policy "site-media: admin borra"
  on storage.objects for delete to authenticated
  using (bucket_id = 'site-media' and (select private.is_admin()));
