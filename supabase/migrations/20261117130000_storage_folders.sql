-- =============================================================================
-- En Compañía · 10 · Storage: carpetas `categories` y `specials`
--
-- - categories/: banners de las secciones de la carta (antes iban bajo products/).
-- - specials/:   fotos del plato del día (tabla daily_specials, migración 15).
--
-- Las políticas de subida y reemplazo listan las carpetas permitidas: se recrean
-- con las dos nuevas. Lectura (admin) y borrado (admin) no dependen de la carpeta.
-- =============================================================================

drop policy "site-media: admin sube en carpetas permitidas" on storage.objects;
drop policy "site-media: admin reemplaza en carpetas permitidas" on storage.objects;

create policy "site-media: admin sube en carpetas permitidas"
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'site-media'
    and (select private.is_admin())
    and (storage.foldername(name))[1] in
      ('branding', 'products', 'categories', 'specials', 'gallery', 'tour', 'trainings', 'institutional')
  );

create policy "site-media: admin reemplaza en carpetas permitidas"
  on storage.objects for update to authenticated
  using (bucket_id = 'site-media' and (select private.is_admin()))
  with check (
    bucket_id = 'site-media'
    and (select private.is_admin())
    and (storage.foldername(name))[1] in
      ('branding', 'products', 'categories', 'specials', 'gallery', 'tour', 'trainings', 'institutional')
  );
