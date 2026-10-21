-- =====================================================================
--  Migración 004 — Avisos automáticos sin usar la pantalla de Webhooks
--  Hace lo mismo que un Database Webhook: cada reserva nueva o cambiada
--  llama a la Edge Function "notificar-reserva".
--
--  ANTES DE CORRER: en la línea marcada con 👉 reemplaza PEGA_AQUI_TU_SERVICE_ROLE
--  por tu clave service_role (Project Settings → API Keys → Legacy API keys →
--  service_role → Reveal). Empieza con eyJ. Queda guardada cifrada en Supabase Vault.
--  Se puede correr más de una vez.
-- =====================================================================

create extension if not exists pg_net with schema extensions;

do $$
declare
  v_clave text := 'PEGA_AQUI_TU_SERVICE_ROLE';   -- 👉 pega tu clave aquí, entre las comillas
  v_id uuid;
begin
  if v_clave like 'PEGA_AQUI%' then
    raise exception 'Falta pegar la clave service_role en la línea marcada con 👉';
  end if;
  select id into v_id from vault.secrets where name = 'monse_service_role';
  if v_id is null then
    perform vault.create_secret(v_clave, 'monse_service_role', 'Clave para llamar a la función notificar-reserva');
  else
    perform vault.update_secret(v_id, v_clave);
  end if;
end $$;

create or replace function public.avisar_reserva()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_clave text;
begin
  select decrypted_secret into v_clave from vault.decrypted_secrets where name = 'monse_service_role';
  perform net.http_post(
    url := 'https://tbpqekxnlfhbzayivljv.supabase.co/functions/v1/notificar-reserva',
    body := jsonb_build_object(
      'type', tg_op, 'table', tg_table_name, 'schema', tg_table_schema,
      'record', to_jsonb(new),
      'old_record', case when tg_op = 'UPDATE' then to_jsonb(old) end),
    headers := jsonb_build_object('Content-Type', 'application/json', 'Authorization', 'Bearer ' || coalesce(v_clave, '')),
    timeout_milliseconds := 5000
  );
  return new;
end;
$$;
revoke all on function public.avisar_reserva() from public, anon, authenticated;

drop trigger if exists avisos_reservas on public.reservas;
create trigger avisos_reservas
  after insert or update on public.reservas
  for each row execute function public.avisar_reserva();

select 'Listo: los avisos quedaron conectados' as resultado;
