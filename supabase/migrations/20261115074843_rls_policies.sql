-- =============================================================================
-- En Compañía · 03 · Privilegios y Row Level Security
--
-- Defensa en dos capas:
--   1. GRANT/REVOKE: `anon` solo tiene SELECT. Aunque una política estuviera mal
--      escrita, PostgreSQL rechaza cualquier escritura de `anon` (42501).
--   2. RLS: decide QUÉ filas ve/escribe cada rol. Escritura solo si
--      private.is_admin() es verdadero.
-- Las políticas usan `(select private.is_admin())` para que PostgreSQL evalúe la
-- función una vez por consulta (initPlan) y no una vez por fila.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Privilegios por tabla
-- -----------------------------------------------------------------------------
-- Tablas de contenido con CRUD completo para el admin.
revoke all on table
  public.categories, public.products, public.gallery_items, public.tour_images,
  public.trainings, public.training_images, public.site_content
from anon, authenticated;

grant select on table
  public.categories, public.products, public.gallery_items, public.tour_images,
  public.trainings, public.training_images, public.site_content
to anon, authenticated;

grant insert, update, delete on table
  public.categories, public.products, public.gallery_items, public.tour_images,
  public.trainings, public.training_images, public.site_content
to authenticated;

-- site_settings: fila única creada por migración. Solo se lee y se actualiza.
revoke all on table public.site_settings from anon, authenticated;
grant select on table public.site_settings to anon, authenticated;
grant update on table public.site_settings to authenticated;

-- profiles: nadie escribe desde la API (evita que un usuario se otorgue el rol admin).
revoke all on table public.profiles from anon, authenticated;
grant select on table public.profiles to authenticated;

-- -----------------------------------------------------------------------------
-- 2. Activar RLS en todas las tablas expuestas
-- -----------------------------------------------------------------------------
alter table public.categories      enable row level security;
alter table public.products        enable row level security;
alter table public.gallery_items   enable row level security;
alter table public.tour_images     enable row level security;
alter table public.trainings       enable row level security;
alter table public.training_images enable row level security;
alter table public.site_content    enable row level security;
alter table public.site_settings   enable row level security;
alter table public.profiles        enable row level security;

-- -----------------------------------------------------------------------------
-- 3. Políticas
-- -----------------------------------------------------------------------------

-- categories ------------------------------------------------------------------
create policy "categories: lectura pública de activas"
  on public.categories for select to anon, authenticated
  using (private.is_category_visible(id));

create policy "categories: admin lee todo"
  on public.categories for select to authenticated
  using ((select private.is_admin()));

create policy "categories: admin crea"
  on public.categories for insert to authenticated
  with check ((select private.is_admin()));

create policy "categories: admin edita"
  on public.categories for update to authenticated
  using ((select private.is_admin()))
  with check ((select private.is_admin()));

create policy "categories: admin borra"
  on public.categories for delete to authenticated
  using ((select private.is_admin()));

-- products --------------------------------------------------------------------
create policy "products: lectura pública de disponibles en categorías visibles"
  on public.products for select to anon, authenticated
  using (is_available and private.is_category_visible(category_id));

create policy "products: admin lee todo"
  on public.products for select to authenticated
  using ((select private.is_admin()));

create policy "products: admin crea"
  on public.products for insert to authenticated
  with check ((select private.is_admin()));

create policy "products: admin edita"
  on public.products for update to authenticated
  using ((select private.is_admin()))
  with check ((select private.is_admin()));

create policy "products: admin borra"
  on public.products for delete to authenticated
  using ((select private.is_admin()));

-- gallery_items ---------------------------------------------------------------
create policy "gallery_items: lectura pública de publicados"
  on public.gallery_items for select to anon, authenticated
  using (is_published);

create policy "gallery_items: admin lee todo"
  on public.gallery_items for select to authenticated
  using ((select private.is_admin()));

create policy "gallery_items: admin crea"
  on public.gallery_items for insert to authenticated
  with check ((select private.is_admin()));

create policy "gallery_items: admin edita"
  on public.gallery_items for update to authenticated
  using ((select private.is_admin()))
  with check ((select private.is_admin()));

create policy "gallery_items: admin borra"
  on public.gallery_items for delete to authenticated
  using ((select private.is_admin()));

-- tour_images -----------------------------------------------------------------
create policy "tour_images: lectura pública de publicadas"
  on public.tour_images for select to anon, authenticated
  using (is_published);

create policy "tour_images: admin lee todo"
  on public.tour_images for select to authenticated
  using ((select private.is_admin()));

create policy "tour_images: admin crea"
  on public.tour_images for insert to authenticated
  with check ((select private.is_admin()));

create policy "tour_images: admin edita"
  on public.tour_images for update to authenticated
  using ((select private.is_admin()))
  with check ((select private.is_admin()));

create policy "tour_images: admin borra"
  on public.tour_images for delete to authenticated
  using ((select private.is_admin()));

-- trainings -------------------------------------------------------------------
create policy "trainings: lectura pública de publicadas"
  on public.trainings for select to anon, authenticated
  using (is_published);

create policy "trainings: admin lee todo"
  on public.trainings for select to authenticated
  using ((select private.is_admin()));

create policy "trainings: admin crea"
  on public.trainings for insert to authenticated
  with check ((select private.is_admin()));

create policy "trainings: admin edita"
  on public.trainings for update to authenticated
  using ((select private.is_admin()))
  with check ((select private.is_admin()));

create policy "trainings: admin borra"
  on public.trainings for delete to authenticated
  using ((select private.is_admin()));

-- training_images -------------------------------------------------------------
-- Visible si su capacitación es visible. La subconsulta a `trainings` pasa por la
-- RLS de `trainings` (otra tabla: no hay recursión).
create policy "training_images: lectura pública si la capacitación está publicada"
  on public.training_images for select to anon, authenticated
  using (exists (
    select 1 from public.trainings t
    where t.id = training_id and t.is_published
  ));

create policy "training_images: admin lee todo"
  on public.training_images for select to authenticated
  using ((select private.is_admin()));

create policy "training_images: admin crea"
  on public.training_images for insert to authenticated
  with check ((select private.is_admin()));

create policy "training_images: admin edita"
  on public.training_images for update to authenticated
  using ((select private.is_admin()))
  with check ((select private.is_admin()));

create policy "training_images: admin borra"
  on public.training_images for delete to authenticated
  using ((select private.is_admin()));

-- site_content ----------------------------------------------------------------
create policy "site_content: lectura pública"
  on public.site_content for select to anon, authenticated
  using (true);

create policy "site_content: admin crea"
  on public.site_content for insert to authenticated
  with check ((select private.is_admin()));

create policy "site_content: admin edita"
  on public.site_content for update to authenticated
  using ((select private.is_admin()))
  with check ((select private.is_admin()));

create policy "site_content: admin borra"
  on public.site_content for delete to authenticated
  using ((select private.is_admin()));

-- site_settings ---------------------------------------------------------------
create policy "site_settings: lectura pública"
  on public.site_settings for select to anon, authenticated
  using (true);

create policy "site_settings: admin edita"
  on public.site_settings for update to authenticated
  using ((select private.is_admin()))
  with check ((select private.is_admin()));

-- profiles --------------------------------------------------------------------
-- Cada usuario autenticado ve solo su propio perfil (el layout del CMS lo usa).
create policy "profiles: cada usuario lee el suyo"
  on public.profiles for select to authenticated
  using (id = (select auth.uid()));
