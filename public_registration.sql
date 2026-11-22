-- CHARLES & MARY WEDDING: PUBLIC REGISTRATION MIGRATION
-- Run this in Supabase SQL Editor > New query.
-- Keeps the existing guests table and existing gate_check function.
-- Public link: no personal token required. Each successful submission gets a unique 4-digit code.

-- Generate unique 4-digit codes. The advisory lock prevents two simultaneous
-- registrations from choosing the same currently-unused code.
create or replace function public.make_code()
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  c text;
begin
  perform pg_advisory_xact_lock(124578, 1);
  loop
    c := lpad(floor(random() * 10000)::integer::text, 4, '0');
    exit when not exists (select 1 from public.guests where code = c);
  end loop;
  return c;
end;
$$;

-- Remove the old personal-token version of confirm_guest, if present.
drop function if exists public.confirm_guest(text, text, text, integer, integer, text);

-- Public registration: anybody with the link can submit their details.
create or replace function public.confirm_guest(
  p_name text,
  p_phone text,
  p_party integer,
  p_vehicles integer,
  p_plates text
)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_code text;
  v_name text := trim(coalesce(p_name, ''));
  v_phone text := trim(coalesce(p_phone, ''));
  v_plates text := upper(trim(coalesce(p_plates, '')));
begin
  if length(v_name) < 2
     or length(regexp_replace(v_phone, '\D', '', 'g')) < 9
     or p_party is null or p_party < 1 or p_party > 10
     or p_vehicles is null or p_vehicles < 0 or p_vehicles > 4
     or (p_vehicles > 0 and v_plates = '') then
    return json_build_object('ok', false, 'message', 'Please check the details and try again.');
  end if;

  insert into public.guests (
    name, phone, confirmed_party, vehicles, plates,
    code, status, confirmed_at
  ) values (
    v_name, v_phone, p_party, p_vehicles, v_plates,
    public.make_code(), 'confirmed', now()
  ) returning code into v_code;

  return json_build_object('ok', true, 'code', v_code);
end;
$$;

-- Keep direct table access closed. Allow the public page to submit registrations.
alter table public.guests enable row level security;
revoke all on public.guests from anon, authenticated;
revoke all on function public.confirm_guest(text, text, integer, integer, text) from public;
grant execute on function public.confirm_guest(text, text, integer, integer, text) to anon, authenticated;

-- Keep the existing gate RPC callable by the gate page (temporary PIN design).
revoke all on function public.gate_check(text, text, boolean) from public;
grant execute on function public.gate_check(text, text, boolean) to anon, authenticated;

-- Optional: verify registrations after running this script:
-- select name, phone, confirmed_party, vehicles, plates, code, status
-- from public.guests order by id desc;
