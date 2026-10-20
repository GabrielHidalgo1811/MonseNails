-- =====================================================================
--  Migración 003 — Jornada laboral editable desde el panel
--  Pegar en: Supabase → SQL Editor → New query → Run (se puede correr más de una vez)
-- =====================================================================

-- Días y bloques en que atiende María (una sola fila, id = 1)
create table if not exists public.ajustes (
  id             smallint primary key default 1 check (id = 1),
  dias           smallint[] not null default '{1,2,3,4,5,6}',      -- 0 = domingo … 6 = sábado
  bloques        smallint[] not null default '{10,12,14,16,18}',   -- hora de inicio de cada bloque
  duracion       smallint   not null default 2 check (duracion between 1 and 4),  -- horas por bloque
  actualizado_en timestamptz not null default now()
);
insert into public.ajustes (id) values (1) on conflict (id) do nothing;

alter table public.ajustes enable row level security;
drop policy if exists "ajustes: todos leen" on public.ajustes;
create policy "ajustes: todos leen" on public.ajustes for select using (true);
drop policy if exists "ajustes: admin escribe" on public.ajustes;
create policy "ajustes: admin escribe" on public.ajustes
  for all to authenticated using (public.is_admin()) with check (public.is_admin());

-- Las horas ya no están fijas en 10, 12, 14, 16 y 18
alter table public.reservas drop constraint if exists reservas_hora_check;
alter table public.reservas add constraint reservas_hora_check check (hora between 0 and 23);

-- La reserva pública valida contra la jornada guardada
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
grant execute on function public.crear_reserva(uuid, date, smallint, text, text, text, text) to anon, authenticated;

select * from public.ajustes;
