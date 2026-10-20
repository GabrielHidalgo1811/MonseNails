-- =====================================================================
--  Monse Nails Studio — base de datos para Supabase
--  Pegar completo en: Supabase → SQL Editor → New query → Run
--  Antes de correrlo, cambia el correo de María en la sección 6.
-- =====================================================================

-- ---------- 1. Tablas ----------
create table if not exists public.servicios (
  id          uuid primary key default gen_random_uuid(),
  nombre      text not null,
  descripcion text default '',
  precio      integer not null check (precio >= 0),          -- CLP
  estilo      text default 'color',                          -- ilustración de respaldo si no hay foto
  imagen      text,                                          -- foto principal (URL o ruta)
  galeria     text[] default '{}',                           -- fotos de referencia
  activo      boolean not null default true,                 -- false = oculto en la web
  orden       integer not null default 100,
  creado_en   timestamptz not null default now()
);

create table if not exists public.clientas (
  id             uuid primary key default gen_random_uuid(),
  nombre         text not null,
  apellido       text not null,
  correo         text not null,
  telefono       text not null,
  telefono_norm  text generated always as (right(regexp_replace(telefono, '\D', '', 'g'), 8)) stored,
  creada_en      timestamptz not null default now()
);
create unique index if not exists clientas_correo_uk on public.clientas (lower(correo));
create index if not exists clientas_tel_idx on public.clientas (telefono_norm);

create table if not exists public.reservas (
  id          uuid primary key default gen_random_uuid(),
  servicio_id uuid not null references public.servicios(id) on delete restrict,
  clienta_id  uuid not null references public.clientas(id) on delete cascade,
  fecha       date not null,
  hora        smallint not null check (hora between 0 and 23),          -- hora de inicio del bloque
  estado      text not null default 'confirmada' check (estado in ('confirmada', 'completada', 'cancelada')),
  precio      integer not null,                                         -- precio al momento de reservar
  gratis      boolean not null default false,                           -- 6.º servicio gratis
  creada_en   timestamptz not null default now()
);
-- un solo bloque activo por fecha y hora (evita dobles reservas)
create unique index if not exists reservas_bloque_uk on public.reservas (fecha, hora) where estado <> 'cancelada';
create index if not exists reservas_clienta_idx on public.reservas (clienta_id);

-- Jornada laboral: días y bloques en que atiende María (editable desde el panel, también en migraciones/003)
create table if not exists public.ajustes (
  id             smallint primary key default 1 check (id = 1),
  dias           smallint[] not null default '{1,2,3,4,5,6}',      -- 0 = domingo … 6 = sábado
  bloques        smallint[] not null default '{10,12,14,16,18}',   -- hora de inicio de cada bloque
  duracion       smallint   not null default 2 check (duracion between 1 and 4),  -- horas por bloque
  actualizado_en timestamptz not null default now()
);
insert into public.ajustes (id) values (1) on conflict (id) do nothing;

-- ---------- 2. Administradoras (quién puede entrar al panel) ----------
create table if not exists public.admins (
  email text primary key
);

create or replace function public.is_admin()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.admins where lower(email) = lower(coalesce(auth.jwt() ->> 'email', '')));
$$;

-- ---------- 3. Seguridad (Row Level Security) ----------
alter table public.servicios enable row level security;
alter table public.clientas  enable row level security;
alter table public.reservas  enable row level security;
alter table public.admins    enable row level security;
alter table public.ajustes   enable row level security;

drop policy if exists "ajustes: todos leen" on public.ajustes;
create policy "ajustes: todos leen" on public.ajustes for select using (true);
drop policy if exists "ajustes: admin escribe" on public.ajustes;
create policy "ajustes: admin escribe" on public.ajustes
  for all to authenticated using (public.is_admin()) with check (public.is_admin());

drop policy if exists "servicios: ver activos o admin" on public.servicios;
create policy "servicios: ver activos o admin" on public.servicios
  for select using (activo or public.is_admin());
drop policy if exists "servicios: admin escribe" on public.servicios;
create policy "servicios: admin escribe" on public.servicios
  for all to authenticated using (public.is_admin()) with check (public.is_admin());

drop policy if exists "clientas: solo admin" on public.clientas;
create policy "clientas: solo admin" on public.clientas
  for all to authenticated using (public.is_admin()) with check (public.is_admin());

drop policy if exists "reservas: solo admin" on public.reservas;
create policy "reservas: solo admin" on public.reservas
  for all to authenticated using (public.is_admin()) with check (public.is_admin());
-- (admins no tiene políticas: nadie la lee desde la web)

-- ---------- 4. Funciones públicas para la web ----------
-- Bloques ocupados de un día (sin exponer datos de clientas)
create or replace function public.bloques_ocupados(p_fecha date)
returns setof smallint language sql stable security definer set search_path = public as $$
  select hora from public.reservas where fecha = p_fecha and estado <> 'cancelada';
$$;

-- Cuántos servicios lleva una clienta (para mostrar sus sellos al reservar)
create or replace function public.visitas_de(p_correo text, p_telefono text)
returns integer language sql stable security definer set search_path = public as $$
  select count(*)::int from public.reservas r
  join public.clientas c on c.id = r.clienta_id
  where r.estado <> 'cancelada'
    and (lower(c.correo) = lower(nullif(trim(p_correo), ''))
         or (length(regexp_replace(coalesce(p_telefono, ''), '\D', '', 'g')) >= 8
             and c.telefono_norm = right(regexp_replace(p_telefono, '\D', '', 'g'), 8)));
$$;

-- Crear una reserva: valida día y bloque contra la jornada, registra a la clienta y aplica la regla 5 + 1 gratis
create or replace function public.crear_reserva(
  p_servicio uuid, p_fecha date, p_hora smallint,
  p_nombre text, p_apellido text, p_correo text, p_telefono text
) returns json language plpgsql security definer set search_path = public as $$
declare
  v_hoy      date := (now() at time zone 'America/Santiago')::date;
  v_aj       public.ajustes;
  v_precio   integer;
  v_clienta  uuid;
  v_visitas  integer;
  v_gratis   boolean;
  v_id       uuid;
begin
  select * into v_aj from public.ajustes where id = 1;
  if p_fecha <= v_hoy or p_fecha > v_hoy + 60 then raise exception 'Elige un día entre mañana y los próximos 60 días.'; end if;
  if not (extract(dow from p_fecha)::smallint = any (coalesce(v_aj.dias, '{1,2,3,4,5,6}'))) then raise exception 'Ese día el studio está cerrado.'; end if;
  if not (p_hora = any (coalesce(v_aj.bloques, '{10,12,14,16,18}'))) then raise exception 'Ese bloque no existe.'; end if;
  if coalesce(trim(p_nombre), '') = '' or coalesce(trim(p_apellido), '') = '' then raise exception 'Faltan nombre o apellido.'; end if;
  if p_correo !~* '^[^@\s]+@[^@\s]+\.[^@\s]+$' then raise exception 'El correo no es válido.'; end if;
  if length(regexp_replace(p_telefono, '\D', '', 'g')) < 8 then raise exception 'El teléfono no es válido.'; end if;

  select precio into v_precio from public.servicios where id = p_servicio and activo;
  if v_precio is null then raise exception 'Ese servicio ya no está disponible.'; end if;

  if exists (select 1 from public.reservas where fecha = p_fecha and hora = p_hora and estado <> 'cancelada') then
    raise exception 'Ese bloque se acaba de ocupar. Elige otro.';
  end if;

  select id into v_clienta from public.clientas
   where lower(correo) = lower(trim(p_correo))
      or telefono_norm = right(regexp_replace(p_telefono, '\D', '', 'g'), 8)
   order by creada_en limit 1;
  if v_clienta is null then
    insert into public.clientas (nombre, apellido, correo, telefono)
    values (trim(p_nombre), trim(p_apellido), lower(trim(p_correo)), trim(p_telefono))
    returning id into v_clienta;
  else
    update public.clientas set nombre = trim(p_nombre), apellido = trim(p_apellido), telefono = trim(p_telefono)
     where id = v_clienta;
  end if;

  select count(*) into v_visitas from public.reservas where clienta_id = v_clienta and estado <> 'cancelada';
  v_gratis := ((v_visitas + 1) % 6 = 0);

  insert into public.reservas (servicio_id, clienta_id, fecha, hora, precio, gratis)
  values (p_servicio, v_clienta, p_fecha, p_hora, v_precio, v_gratis)
  returning id into v_id;

  return json_build_object('id', v_id, 'precio', v_precio, 'gratis', v_gratis, 'visitas', v_visitas + 1, 'estado', 'confirmada');
exception when unique_violation then
  raise exception 'Ese bloque se acaba de ocupar. Elige otro.';
end;
$$;

revoke all on function public.crear_reserva(uuid, date, smallint, text, text, text, text) from public;
grant execute on function public.bloques_ocupados(date) to anon, authenticated;
grant execute on function public.visitas_de(text, text) to anon, authenticated;
grant execute on function public.crear_reserva(uuid, date, smallint, text, text, text, text) to anon, authenticated;

-- ---------- 4b. Panel: permiso y tiempo real (también en migraciones/002) ----------
-- El panel pregunta si el correo con que entró María está autorizado
create or replace function public.soy_admin()
returns boolean language sql stable security definer set search_path = public as $$
  select public.is_admin();
$$;
grant execute on function public.soy_admin() to authenticated;

-- El panel se actualiza solo cuando entra una reserva nueva (Realtime)
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
     and not exists (select 1 from pg_publication_tables
                     where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'reservas') then
    alter publication supabase_realtime add table public.reservas;
  end if;
end $$;

-- ---------- 5. Fotos (Storage) ----------
insert into storage.buckets (id, name, public) values ('fotos', 'fotos', true)
on conflict (id) do nothing;

drop policy if exists "fotos: admin sube" on storage.objects;
create policy "fotos: admin sube" on storage.objects
  for insert to authenticated with check (bucket_id = 'fotos' and public.is_admin());
drop policy if exists "fotos: admin edita" on storage.objects;
create policy "fotos: admin edita" on storage.objects
  for update to authenticated using (bucket_id = 'fotos' and public.is_admin());
drop policy if exists "fotos: admin borra" on storage.objects;
create policy "fotos: admin borra" on storage.objects
  for delete to authenticated using (bucket_id = 'fotos' and public.is_admin());

-- ---------- 6. Datos iniciales ----------
-- CAMBIA este correo por el que María usará para entrar al panel:
insert into public.admins (email) values ('maria@ejemplo.cl') on conflict do nothing;

insert into public.servicios (nombre, descripcion, precio, estilo, imagen, galeria, orden)
select * from (values
  ('Manicura rusa', 'Limpieza profunda de cutícula con torno, sin esmalte. Uñas prolijas y naturales.', 5000, 'rusa',
     'fotos/rusa-1.jpg', array['fotos/rusa-1.jpg','fotos/rusa-2.jpg','fotos/rusa-3.jpg'], 1),
  ('Manicura rusa + nivelación + color', 'Manicura rusa, nivelación con base rubber y esmaltado semipermanente en el tono que elijas.', 15000, 'color',
     'fotos/polygel-3.jpg', array['fotos/polygel-3.jpg','fotos/polygel-2.jpg'], 2),
  ('Soft gel', 'Extensión con tips de soft gel: largo y forma a tu gusto, livianas y resistentes.', 15000, 'softgel',
     'fotos/softgel-1.jpg', array['fotos/softgel-1.jpg','fotos/softgel-2.jpg','fotos/softgel-3.jpg'], 3),
  ('Polygel', 'Construcción con polygel para uñas firmes y de forma perfecta. Ideal para francesa o diseño.', 18000, 'polygel',
     'fotos/polygel-1.jpg', array['fotos/polygel-1.jpg','fotos/polygel-2.jpg','fotos/polygel-3.jpg'], 4),
  ('Pedicura + semipermanente', 'Pedicura completa con limpieza, limado y esmaltado semipermanente de larga duración.', 10000, 'pedi',
     'fotos/pedi-2.jpg', array['fotos/pedi-2.jpg','fotos/pedi-3.jpg','fotos/pedi-1.jpg'], 5)
) as v(nombre, descripcion, precio, estilo, imagen, galeria, orden)
where not exists (select 1 from public.servicios);
