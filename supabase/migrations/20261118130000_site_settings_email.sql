-- =============================================================================
-- En Compañía · 17 · Configuración del local: email y Facebook "web."
--
-- - site_settings.email: email de contacto del local (footer y /contacto).
-- - El link de Facebook que comparte la página usa el subdominio web.facebook.com:
--   se suma a los permitidos (www., m.). Sigue exigiendo https y el dominio de Facebook.
-- =============================================================================

alter table public.site_settings
  add column email text check (
    char_length(email) <= 254
    and email ~* '^[a-z0-9._%+-]+@[a-z0-9.-]+\.[a-z]{2,}$'
  );

comment on column public.site_settings.email is 'Email de contacto del local. NULL = la web no lo muestra.';

alter table public.site_settings drop constraint site_settings_facebook_url_check;
alter table public.site_settings
  add constraint site_settings_facebook_url_check
  check (facebook_url ~ '^https://(www\.|m\.|web\.)?facebook\.com/');
