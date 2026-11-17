-- =============================================================================
-- En Compañía · 01 · Esquema inicial
-- Tablas, restricciones, índices y triggers. La seguridad (grants + RLS) está
-- en la migración rls_policies; las funciones de autorización en functions.
-- Ver docs/DATABASE.md para el porqué de cada decisión.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Esquema `private`: funciones internas. NO está expuesto por la Data API
-- (PostgREST solo expone `public`), así que nada de acá se puede llamar por RPC.
-- -----------------------------------------------------------------------------
create schema if not exists private;
revoke all on schema private from public;

-- Trigger común: mantiene updated_at.
create function private.set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

-- Validadores de paths de Storage (se usan en CHECK, por eso IMMUTABLE).
-- Formato esperado: "<carpeta>/<nombre-seguro>.<ext>", p. ej. "products/3f2a...c1.webp".
-- Solo minúsculas, dígitos, "-", "_" y "/": imposible un "../" o caracteres raros.
create function private.is_image_path(path text, folder text)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select path ~ ('^' || folder || '/[a-z0-9][a-z0-9/_-]*\.(jpg|jpeg|png|webp|avif)$');
$$;

create function private.is_video_path(path text, folder text)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select path ~ ('^' || folder || '/[a-z0-9][a-z0-9/_-]*\.(mp4|webm)$');
$$;

-- Slug: minúsculas, dígitos y guiones simples. Dominio reutilizable.
create domain public.slug as text
  check (value ~ '^[a-z0-9]+(-[a-z0-9]+)*$' and char_length(value) <= 120);

-- =============================================================================
-- CARTA
-- =============================================================================

create table public.categories (
  id          uuid primary key default gen_random_uuid(),
  parent_id   uuid references public.categories (id) on delete restrict,
  name        text not null check (char_length(btrim(name)) between 1 and 120),
  slug        public.slug not null unique,
  description text check (char_length(description) <= 1000),
  is_active   boolean not null default true,
  sort_order  integer not null default 0 check (sort_order >= 0),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  constraint categories_not_own_parent check (parent_id is null or parent_id <> id)
);
comment on table public.categories is
  'Categorías de la carta. Un solo nivel de anidación (categoría → subcategoría), forzado por trigger.';

-- Un solo nivel: el padre debe ser raíz, y una categoría con hijas no puede volverse hija.
create function private.enforce_category_depth()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.parent_id is not null then
    if exists (select 1 from public.categories where id = new.parent_id and parent_id is not null) then
      raise exception 'Una subcategoría no puede tener subcategorías propias.'
        using errcode = '23514';
    end if;
    if exists (select 1 from public.categories where parent_id = new.id) then
      raise exception 'Una categoría que tiene subcategorías no puede convertirse en subcategoría.'
        using errcode = '23514';
    end if;
  end if;
  return new;
end;
$$;

create trigger categories_enforce_depth
  before insert or update of parent_id on public.categories
  for each row execute function private.enforce_category_depth();

-- Índice de FK: lo usan el ON DELETE RESTRICT (buscar hijas) y el listado por padre.
create index categories_parent_sort_idx on public.categories (parent_id, sort_order);

create table public.products (
  id           uuid primary key default gen_random_uuid(),
  -- RESTRICT: borrar una categoría con productos falla (23503) y el CMS lo explica.
  category_id  uuid not null references public.categories (id) on delete restrict,
  name         text not null check (char_length(btrim(name)) between 1 and 120),
  slug         public.slug not null unique,
  description  text check (char_length(description) <= 1000),
  price        numeric(10, 2) check (price >= 0),
  image_path   text check (private.is_image_path(image_path, 'products')),
  is_available boolean not null default true,
  is_featured  boolean not null default false,
  sort_order   integer not null default 0 check (sort_order >= 0),
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);
comment on column public.products.price is 'NULL = sin precio publicado (la web no lo muestra).';

-- Índice de FK: chequeo del RESTRICT al borrar categorías y listado de la carta.
create index products_category_sort_idx on public.products (category_id, sort_order);

-- =============================================================================
-- GALERÍA Y RECORRIDO
-- =============================================================================

create table public.gallery_items (
  id           uuid primary key default gen_random_uuid(),
  media_type   text not null check (media_type in ('image', 'video')),
  title        text not null check (char_length(btrim(title)) between 1 and 160),
  description  text check (char_length(description) <= 1000),
  media_path   text not null,
  poster_path  text,
  category     text not null
    check (category in ('espacio', 'cafe', 'tapas', 'cocktails', 'equipo', 'momentos')),
  is_published boolean not null default false,
  sort_order   integer not null default 0 check (sort_order >= 0),
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  -- Imagen: sin poster. Video: archivo de video y poster opcional (imagen).
  constraint gallery_items_media_check check (
    (media_type = 'image'
      and private.is_image_path(media_path, 'gallery')
      and poster_path is null)
    or
    (media_type = 'video'
      and private.is_video_path(media_path, 'gallery')
      and (poster_path is null or private.is_image_path(poster_path, 'gallery')))
  )
);
comment on column public.gallery_items.title is 'Se usa también como texto alternativo (alt).';

create table public.tour_images (
  id           uuid primary key default gen_random_uuid(),
  area         text not null check (area in ('salon', 'barra', 'rincones', 'detalles')),
  title        text not null check (char_length(btrim(title)) between 1 and 160),
  description  text check (char_length(description) <= 1000),
  image_path   text not null check (private.is_image_path(image_path, 'tour')),
  is_published boolean not null default false,
  sort_order   integer not null default 0 check (sort_order >= 0),
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);
comment on column public.tour_images.title is 'Se usa también como texto alternativo (alt).';

-- =============================================================================
-- CAPACITACIONES
-- =============================================================================

create table public.trainings (
  id                     uuid primary key default gen_random_uuid(),
  title                  text not null check (char_length(btrim(title)) between 1 and 160),
  slug                   public.slug not null unique,
  subtitle               text check (char_length(subtitle) <= 300),
  description            text check (char_length(description) <= 5000),
  organization           text check (char_length(organization) <= 160),
  instructor             text check (char_length(instructor) <= 160),
  certificate_name       text check (char_length(certificate_name) <= 200),
  certificate_image_path text check (private.is_image_path(certificate_image_path, 'trainings')),
  cover_image_path       text check (private.is_image_path(cover_image_path, 'trainings')),
  is_published           boolean not null default false,
  sort_order             integer not null default 0 check (sort_order >= 0),
  created_at             timestamptz not null default now(),
  updated_at             timestamptz not null default now()
);
comment on column public.trainings.subtitle is 'Bajada (p. ej. texto oficial 5.8 del CLAUDE.md).';
comment on column public.trainings.instructor is
  'NULL hasta confirmarlo con los diplomas (decisión Prompt 3).';

-- Fotos del equipo durante la capacitación (varias por capacitación, ordenables).
-- CASCADE borra solo filas: la Server Action debe borrar también los archivos en Storage.
create table public.training_images (
  id          uuid primary key default gen_random_uuid(),
  training_id uuid not null references public.trainings (id) on delete cascade,
  image_path  text not null check (private.is_image_path(image_path, 'trainings')),
  alt_text    text not null check (char_length(btrim(alt_text)) between 1 and 200),
  sort_order  integer not null default 0 check (sort_order >= 0),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

-- Índice de FK: cascade al borrar la capacitación y listado ordenado de sus fotos.
create index training_images_training_sort_idx on public.training_images (training_id, sort_order);

-- =============================================================================
-- CONTENIDO INSTITUCIONAL Y CONFIGURACIÓN
-- =============================================================================

create table public.site_content (
  id         uuid primary key default gen_random_uuid(),
  section    text not null unique check (section in (
    'home_hero', 'offer_coffee', 'offer_tapas', 'offer_cocktails',
    'history', 'essence', 'mission', 'vision', 'values', 'differentiation'
  )),
  title      text check (char_length(title) <= 200),
  subtitle   text check (char_length(subtitle) <= 300),
  content    text check (char_length(content) <= 10000),
  quote      text check (char_length(quote) <= 500),
  -- Lista de ítems {title, description}. Solo en secciones que la usan (hoy: values).
  -- La forma de cada ítem se valida con Zod en el frontend y en el servidor.
  items      jsonb,
  image_path text check (private.is_image_path(image_path, 'institutional')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint site_content_items_check check (
    items is null or (section = 'values' and jsonb_typeof(items) = 'array')
  )
);

create table public.site_settings (
  id                         uuid primary key default gen_random_uuid(),
  -- Fila única: la columna solo admite TRUE y es UNIQUE → como máximo una fila.
  singleton                  boolean not null default true unique check (singleton),
  business_name              text not null check (char_length(btrim(business_name)) between 1 and 120),
  address                    text check (char_length(address) <= 300),
  phone                      text check (phone ~ '^\+?[0-9 ()-]{6,20}$'),
  whatsapp                   text check (whatsapp ~ '^\+?[0-9]{8,15}$'),
  instagram_url              text check (instagram_url ~ '^https://(www\.)?instagram\.com/'),
  facebook_url               text check (facebook_url ~ '^https://(www\.|m\.)?facebook\.com/'),
  tiktok_url                 text check (tiktok_url ~ '^https://(www\.)?tiktok\.com/'),
  -- Horarios estructurados por día; forma validada con Zod. NULL = la web oculta el bloque.
  opening_hours              jsonb check (opening_hours is null or jsonb_typeof(opening_hours) = 'array'),
  google_maps_embed_url      text check (google_maps_embed_url ~ '^https://www\.google\.com/maps/embed'),
  google_maps_directions_url text check (google_maps_directions_url ~ '^https://'),
  logo_path                  text check (private.is_image_path(logo_path, 'branding')),
  hero_media_path            text check (
    private.is_image_path(hero_media_path, 'branding')
    or private.is_video_path(hero_media_path, 'branding')
  ),
  created_at                 timestamptz not null default now(),
  updated_at                 timestamptz not null default now()
);

-- La fila única es estructura (no dato de desarrollo): existe también en producción.
insert into public.site_settings (business_name) values ('En Compañía');

-- =============================================================================
-- PERFILES (administradores)
-- =============================================================================

create table public.profiles (
  id         uuid primary key references auth.users (id) on delete cascade,
  full_name  text check (char_length(full_name) <= 120),
  -- Sin default: un perfil solo existe si se creó deliberadamente con su rol.
  role       text not null check (role in ('admin')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
comment on table public.profiles is
  'Perfiles con rol. No hay registro público ni escritura desde la API: se crean desde un entorno confiable.';

-- =============================================================================
-- TRIGGERS updated_at
-- =============================================================================

create trigger categories_set_updated_at      before update on public.categories      for each row execute function private.set_updated_at();
create trigger products_set_updated_at        before update on public.products        for each row execute function private.set_updated_at();
create trigger gallery_items_set_updated_at   before update on public.gallery_items   for each row execute function private.set_updated_at();
create trigger tour_images_set_updated_at     before update on public.tour_images     for each row execute function private.set_updated_at();
create trigger trainings_set_updated_at       before update on public.trainings       for each row execute function private.set_updated_at();
create trigger training_images_set_updated_at before update on public.training_images for each row execute function private.set_updated_at();
create trigger site_content_set_updated_at    before update on public.site_content    for each row execute function private.set_updated_at();
create trigger site_settings_set_updated_at   before update on public.site_settings   for each row execute function private.set_updated_at();
create trigger profiles_set_updated_at        before update on public.profiles        for each row execute function private.set_updated_at();
