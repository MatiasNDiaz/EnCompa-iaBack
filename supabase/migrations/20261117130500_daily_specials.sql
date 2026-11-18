-- =============================================================================
-- En Compañía · 15 · Plato del día
--
-- Una fila por momento del día (mañana, mediodía, tarde/noche). Las 3 filas se crean
-- ACÁ (no en el seed) para que existan también en producción: el panel solo las edita.
--
--   · `moment` único → nunca hay dos platos para el mismo momento.
--   · El admin solo puede ACTUALIZAR (no insertar ni borrar): las 3 filas son fijas.
--   · No se puede publicar un espacio sin foto y sin título (CHECK).
--   · anon ve solo los publicados; el admin ve y edita los 3.
--   · Fotos en site-media/specials/ (la carpeta ya está permitida desde la migración 10).
-- =============================================================================

-- Ingredientes: lista corta de textos no vacíos (se valida igual con Zod en el panel).
-- Función propia porque un CHECK no admite subconsultas (unnest).
create function private.is_valid_ingredient_list(items text[])
returns boolean
language sql
immutable
set search_path = ''
as $$
  select items is null
      or (
        cardinality(items) <= 20
        and array_position(items, null) is null
        and not exists (
          select 1 from unnest(items) as item
          where char_length(btrim(item)) not between 1 and 80
        )
      );
$$;

comment on function private.is_valid_ingredient_list(text[]) is
  'Lista de ingredientes: hasta 20 ítems de 1 a 80 caracteres, sin vacíos ni NULL.';

create table public.daily_specials (
  id           uuid primary key default gen_random_uuid(),
  moment       public.day_moment not null unique,
  image_path   text check (private.is_image_path(image_path, 'specials')),
  title        text check (char_length(btrim(title)) between 1 and 120),
  subtitle     text check (char_length(subtitle) <= 160),
  body         text check (char_length(body) <= 1000),
  price        numeric(10, 2) check (price >= 0),
  ingredients  text[] check (private.is_valid_ingredient_list(ingredients)),
  is_published boolean not null default false,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  constraint daily_specials_publishable check (
    not is_published or (image_path is not null and title is not null)
  )
);

comment on table public.daily_specials is
  'Plato del día: una fila fija por momento (morning, midday, evening). El panel solo las actualiza.';
comment on column public.daily_specials.price is 'Opcional. NULL = la web no muestra precio.';
comment on column public.daily_specials.ingredients is 'Opcional. Lista de ingredientes (la web los muestra como lista).';
comment on constraint daily_specials_publishable on public.daily_specials is
  'Un plato publicado tiene foto y título.';

create trigger daily_specials_set_updated_at
  before update on public.daily_specials
  for each row execute function private.set_updated_at();

-- Las 3 filas, vacías y sin publicar.
insert into public.daily_specials (moment) values ('morning'), ('midday'), ('evening');

-- -----------------------------------------------------------------------------
-- Privilegios: anon solo lee; el admin lee y actualiza (sin INSERT ni DELETE).
-- -----------------------------------------------------------------------------
revoke all on table public.daily_specials from anon, authenticated;
grant select on table public.daily_specials to anon, authenticated;
grant update on table public.daily_specials to authenticated;

revoke all on function private.is_valid_ingredient_list(text[]) from public, anon, authenticated;
grant execute on function private.is_valid_ingredient_list(text[]) to authenticated, service_role;

alter table public.daily_specials enable row level security;

create policy "daily_specials: lectura pública de publicados"
  on public.daily_specials for select to anon, authenticated
  using (is_published);

create policy "daily_specials: admin lee todo"
  on public.daily_specials for select to authenticated
  using ((select private.is_admin()));

create policy "daily_specials: admin edita"
  on public.daily_specials for update to authenticated
  using ((select private.is_admin()))
  with check ((select private.is_admin()));
