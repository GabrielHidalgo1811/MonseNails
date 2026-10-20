-- =====================================================================
--  Actualización 002: calendario del panel y avisos automáticos
--  Para quien ya corrió schema.sql antes del 20-10-2026.
--  Pegar en Supabase → SQL Editor → Run (se puede correr más de una vez).
-- =====================================================================

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

-- Revisión: este correo debe ser el mismo con que María entra al panel.
-- Si no aparece el suyo, corre:  insert into public.admins (email) values ('correo-de-maria@...');
select email as "correos autorizados para el panel" from public.admins;
