-- =============================================================================
-- En Compañía · 24 · Novedades
--
-- Publicaciones de novedades, eventos, promociones y propuestas especiales
-- (por ejemplo "Noche de chicas"): imagen o video, título, descripción, fecha del
-- evento opcional y un mensaje final destacado.
--
--   · Imagen: archivo de imagen en news/, sin portada.
--     Video: archivo MP4/WebM en news/ y portada (imagen) OBLIGATORIA.
--   · published_at se completa la PRIMERA vez que se publica y se conserva aunque se
--     oculte y se vuelva a publicar: el orden de la lista no salta.
--   · anon ve solo las publicadas; el admin ve todas y es el único que escribe.
--   · Storage: se agrega la carpeta news/ a las políticas de subida (las de lectura y
--     borrado no dependen de la carpeta). Tamaños: el bucket ya limita a 50 MiB (videos);
--     las imágenes se limitan a 8 MiB en el panel y en el servidor.
-- =============================================================================

create table public.news_posts (
  id              uuid primary key default gen_random_uuid(),
  title           text not null check (char_length(btrim(title)) between 1 and 120),
  slug            public.slug not null unique,
  description     text not null check (char_length(btrim(description)) between 1 and 1500),
  closing_message text check (char_length(btrim(closing_message)) between 1 and 200),
  media_type      text not null check (media_type in ('image', 'video')),
  media_path      text not null,
  poster_path     text,
  event_date      date,
  is_published    boolean not null default false,
  published_at    timestamptz,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  constraint news_posts_media check (
    (media_type = 'image'
      and private.is_image_path(media_path, 'news')
      and poster_path is null)
    or
    (media_type = 'video'
      and private.is_video_path(media_path, 'news')
      and poster_path is not null
      and private.is_image_path(poster_path, 'news'))
  ),
  constraint news_posts_published_at check (not is_published or published_at is not null)
);

comment on table public.news_posts is
  'Novedades: eventos, promociones y propuestas especiales. La web muestra solo las publicadas, de la más reciente a la más vieja (published_at).';
comment on column public.news_posts.description is 'Texto principal. Los párrafos se separan con una línea en blanco.';
comment on column public.news_posts.closing_message is 'Opcional. Mensaje final destacado (ej. "¡Te esperamos!").';
comment on column public.news_posts.poster_path is 'Portada del video (obligatoria si es video; NULL si es imagen).';
comment on column public.news_posts.published_at is 'Se completa la primera vez que se publica y no cambia al ocultar.';

create index news_posts_published_idx on public.news_posts (published_at desc) where is_published;

-- published_at: la primera vez que se publica.
create function private.set_news_published_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.is_published and new.published_at is null then
    new.published_at := now();
  end if;
  return new;
end;
$$;

create trigger news_posts_set_published_at
  before insert or update on public.news_posts
  for each row execute function private.set_news_published_at();

create trigger news_posts_set_updated_at
  before update on public.news_posts
  for each row execute function private.set_updated_at();

revoke all on function private.set_news_published_at() from public, anon, authenticated;

-- -----------------------------------------------------------------------------
-- Privilegios y RLS
-- -----------------------------------------------------------------------------
revoke all on table public.news_posts from anon, authenticated;
grant select on table public.news_posts to anon, authenticated;
grant insert, update, delete on table public.news_posts to authenticated;

alter table public.news_posts enable row level security;

create policy "news_posts: lectura pública de publicadas"
  on public.news_posts for select to anon, authenticated
  using (is_published);

create policy "news_posts: admin lee todo"
  on public.news_posts for select to authenticated
  using ((select private.is_admin()));

create policy "news_posts: admin crea"
  on public.news_posts for insert to authenticated
  with check ((select private.is_admin()));

create policy "news_posts: admin edita"
  on public.news_posts for update to authenticated
  using ((select private.is_admin()))
  with check ((select private.is_admin()));

create policy "news_posts: admin borra"
  on public.news_posts for delete to authenticated
  using ((select private.is_admin()));

-- -----------------------------------------------------------------------------
-- Storage: carpeta news/
-- -----------------------------------------------------------------------------
drop policy "site-media: admin sube en carpetas permitidas" on storage.objects;
drop policy "site-media: admin reemplaza en carpetas permitidas" on storage.objects;

create policy "site-media: admin sube en carpetas permitidas"
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'site-media'
    and (select private.is_admin())
    and (storage.foldername(name))[1] in
      ('branding', 'products', 'categories', 'specials', 'news', 'gallery', 'tour', 'trainings', 'institutional')
  );

create policy "site-media: admin reemplaza en carpetas permitidas"
  on storage.objects for update to authenticated
  using (bucket_id = 'site-media' and (select private.is_admin()))
  with check (
    bucket_id = 'site-media'
    and (select private.is_admin())
    and (storage.foldername(name))[1] in
      ('branding', 'products', 'categories', 'specials', 'news', 'gallery', 'tour', 'trainings', 'institutional')
  );
