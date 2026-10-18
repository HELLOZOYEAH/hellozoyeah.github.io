-- รันครั้งเดียวใน Supabase > SQL Editor *หลัง* setup-voice-fx.sql และตั้งรหัสแอปแล้ว · รันซ้ำได้
-- ปิดรูเล็ก 3 ข้อ (2026-10-18):
--   1. ส่งโดเนตได้ไม่เกิน 3 ครั้งต่อนาทีต่อเครื่อง และรวมทั้งเว็บไม่เกิน 30 ครั้งต่อนาที
--   2. ที่เก็บรูปสลิปรับเฉพาะไฟล์ของโดเนตที่เพิ่งส่งจริง (วันที่/เลขรายการ) · ที่เก็บเสียงจำกัด 20 ไฟล์ต่อนาที
--   3. รายชื่อคนโดเนต (alerts) คนนอกอ่านไม่ได้แล้ว · ACEACE อ่านผ่านรหัสแอป (ace_alerts)
-- ** เปิด ACEACE รุ่นที่อ่านผ่านรหัสแอปก่อนรันไฟล์นี้ ไม่อย่างนั้นแอปรุ่นเก่าจะไม่เห็นโดเนตจากเว็บ **

-- 1. จำกัดจำนวนครั้ง: เก็บแค่ค่า hash ของ IP (ไม่เก็บ IP จริง) ไว้นับ · ตาราง slips คนนอกอ่านไม่ได้อยู่แล้ว
alter table public.slips add column if not exists sender text;

create or replace function public.slip_rate_limit() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  headers json := coalesce(nullif(current_setting('request.headers', true), ''), '{}')::json;
  ip text := coalesce(nullif(headers ->> 'cf-connecting-ip', ''), nullif(trim(split_part(headers ->> 'x-forwarded-for', ',', 1)), ''), '');
begin
  new.sender := case when ip = '' then null else encode(sha256(convert_to('donodotad:' || ip, 'UTF8')), 'hex') end;
  if (select count(*) from public.slips where created_at > now() - interval '1 minute') >= 30
     or (new.sender is not null and
         (select count(*) from public.slips where sender = new.sender and created_at > now() - interval '1 minute') >= 3) then
    raise exception 'too many donations, try again in a minute' using errcode = 'PT429';
  end if;
  return new;
end $$;

drop trigger if exists slip_rate_limit on public.slips;
create trigger slip_rate_limit before insert on public.slips
  for each row execute function public.slip_rate_limit();
create index if not exists slips_created_at on public.slips (created_at);

-- 2. ที่เก็บไฟล์
create or replace function public.slip_file_ok(p_name text) returns boolean
language sql stable security definer set search_path = public as $$
  select p_name ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}/[A-Za-z0-9_-]{10,40}\.(jpg|png|webp|heic)$'
     and exists (select 1 from public.slips
                 where slip_path = p_name and created_at > now() - interval '10 minutes');
$$;
create or replace function public.voice_uploads_ok() returns boolean
language sql stable security definer set search_path = public, storage as $$
  select (select count(*) from storage.objects
          where bucket_id = 'voices' and created_at > now() - interval '1 minute') < 20;
$$;
revoke all on function public.slip_file_ok(text) from public;
revoke all on function public.voice_uploads_ok() from public;
grant execute on function public.slip_file_ok(text) to anon;
grant execute on function public.voice_uploads_ok() to anon;

update storage.buckets set file_size_limit = 3000000 where id = 'slips';
drop policy if exists "anyone can upload slip" on storage.objects;
create policy "anyone can upload slip" on storage.objects for insert to anon
  with check (bucket_id = 'slips' and public.slip_file_ok(name));

drop policy if exists "anyone can upload voice" on storage.objects;
create policy "anyone can upload voice" on storage.objects for insert to anon
  with check (bucket_id = 'voices' and name ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}/[A-Za-z0-9]{10,40}\.(webm|m4a|mp4|ogg)$'
              and public.voice_uploads_ok());

-- 3. รายชื่อคนโดเนต: ปิดการอ่านของคนนอก (และหน้า alert.html แบบเก่า) · ACEACE อ่านด้วยรหัสแอป
drop policy if exists "anyone can read alerts" on public.alerts;
revoke select on public.alerts from anon, authenticated;
do $$
begin
  if exists (select 1 from pg_publication_tables
             where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'alerts') then
    alter publication supabase_realtime drop table public.alerts;
  end if;
end $$;

-- โดเนตหลังเลขที่ p_after เรียงจากเก่าไปใหม่ (ทีละไม่เกิน 50)
create or replace function public.ace_alerts(p_key text, p_after bigint, p_limit integer default 20) returns setof public.alerts
language plpgsql stable security definer set search_path = public, ace_private as $$
begin
  if not ace_private.key_ok(p_key) then raise exception 'wrong app key' using errcode = '42501'; end if;
  return query select * from public.alerts where id > coalesce(p_after, 0)
               order by id limit least(greatest(coalesce(p_limit, 20), 1), 50);
end $$;

-- เลขโดเนตล่าสุด (แอปเชื่อมครั้งแรกเริ่มอ่านต่อจากนี้ ไม่อ่านของเก่า) · 0 เมื่อยังไม่มี
create or replace function public.ace_last_alert(p_key text) returns bigint
language plpgsql stable security definer set search_path = public, ace_private as $$
begin
  if not ace_private.key_ok(p_key) then raise exception 'wrong app key' using errcode = '42501'; end if;
  return coalesce((select max(id) from public.alerts), 0);
end $$;

revoke all on function public.ace_alerts(text, bigint, integer) from public;
revoke all on function public.ace_last_alert(text) from public;
grant execute on function public.ace_alerts(text, bigint, integer) to anon;
grant execute on function public.ace_last_alert(text) to anon;
