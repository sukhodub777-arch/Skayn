-- Supabase → SQL Editor → вставить → Run (один раз, после supabase_setup.sql)
-- Облачная история: копия состояния смены ПЕРЕД первым изменением в каждом часе, хранится 30 дней.

create table if not exists shift_history (
  name text not null,
  bucket timestamptz not null,
  roster jsonb not null,
  days jsonb not null,
  primary key (name, bucket)
);
alter table shift_history enable row level security;

create or replace function _hist() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if (old.roster is distinct from new.roster or old.days is distinct from new.days)
     and (jsonb_array_length(old.roster) > 0 or old.days <> '{}'::jsonb) then
    insert into shift_history(name, bucket, roster, days)
    values (old.name, date_trunc('hour', now()), old.roster, old.days)
    on conflict (name, bucket) do nothing;
    delete from shift_history where name = old.name and bucket < now() - interval '30 days';
  end if;
  return new;
end $$;

drop trigger if exists shifts_hist on shifts;
create trigger shifts_hist before update on shifts for each row execute function _hist();

create or replace function list_history(p_name text, p_pass text) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if not _auth(p_name, p_pass) then return jsonb_build_object('ok', false); end if;
  return jsonb_build_object('ok', true, 'items', coalesce((
    select jsonb_agg(bucket order by bucket desc) from (
      select bucket from shift_history where name = upper(p_name) order by bucket desc limit 100) t), '[]'::jsonb));
end $$;

create or replace function get_history(p_name text, p_pass text, p_bucket timestamptz) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r shift_history;
begin
  if not _auth(p_name, p_pass) then return jsonb_build_object('ok', false); end if;
  select * into r from shift_history where name = upper(p_name) and bucket = p_bucket;
  if not found then return jsonb_build_object('ok', false); end if;
  return jsonb_build_object('ok', true, 'roster', r.roster, 'days', r.days);
end $$;

grant execute on function list_history(text, text) to anon;
grant execute on function get_history(text, text, timestamptz) to anon;
