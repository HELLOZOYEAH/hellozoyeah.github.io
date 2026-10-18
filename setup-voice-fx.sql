-- รันครั้งเดียวใน Supabase > SQL Editor *หลัง* setup-voice.sql และ *ก่อน* อัปหน้าเว็บที่มีเอฟเฟกต์เสียงกับเสียงพื้นหลัง · รันซ้ำได้
-- คนโดเนตเลือกเปลี่ยนเสียง (เอฟเฟกต์) และเสียงพื้นหลัง (BG) ได้ · รายการ BG กับค่าตั้งของหน้าโดเนตเก็บที่นี่
-- ACEACE แก้ได้เองด้วย "รหัสแอป" (ไม่ต้อง push หน้าเว็บ) · หลังรันไฟล์นี้ ไปที่ ACEACE > โดเนต > คัดลอก SQL รหัสแอป แล้วรันอีกครั้ง

alter table public.slips  add column if not exists voice_effect text;
alter table public.slips  add column if not exists voice_bg     text;
alter table public.alerts add column if not exists voice_effect text;
alter table public.alerts add column if not exists voice_bg     text;

-- รายการ BG: ทุกคนอ่านได้ (หน้าเว็บโหลดชื่อตอนเปิด และโหลดเสียงตอนคนดูเลือก) · แก้ได้เฉพาะผ่านรหัสแอป
create table if not exists public.voice_bgs (
  id         text primary key check (id ~ '^[a-z0-9]{6,24}$'),
  name       text not null check (char_length(name) between 1 and 20),
  sort       integer not null default 0,
  audio      text not null check (audio ~ '^data:audio/(mp4|webm);base64,' and char_length(audio) <= 1500000),
  updated_at timestamptz not null default now()
);
alter table public.voice_bgs enable row level security;
drop policy if exists "anyone can read voice bgs" on public.voice_bgs;
create policy "anyone can read voice bgs" on public.voice_bgs for select to anon using (true);

-- ค่าตั้งของหน้าโดเนต (ยอดขั้นต่ำอัดเสียง ความยาว เอฟเฟกต์ที่เปิด ความดัง BG): แถวเดียว ทุกคนอ่านได้
create table if not exists public.page_settings (
  id         integer primary key default 1 check (id = 1),
  settings   jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);
alter table public.page_settings enable row level security;
drop policy if exists "anyone can read page settings" on public.page_settings;
create policy "anyone can read page settings" on public.page_settings for select to anon using (true);

-- รหัสแอป: เก็บแค่ค่า hash ในที่ที่หน้าเว็บมองไม่เห็น · รหัสจริงอยู่ในเครื่องพี่ (ACEACE) เท่านั้น
create schema if not exists ace_private;
revoke all on schema ace_private from public, anon, authenticated;
create table if not exists ace_private.app_key (
  id   integer primary key default 1 check (id = 1),
  hash text not null check (hash ~ '^[0-9a-f]{64}$')
);

create or replace function ace_private.key_ok(p_key text) returns boolean
language sql stable security definer set search_path = ace_private, public as $$
  select exists (select 1 from ace_private.app_key
                 where hash = encode(sha256(convert_to(coalesce(p_key, ''), 'UTF8')), 'hex'));
$$;
revoke all on function ace_private.key_ok(text) from public, anon, authenticated;

-- ACEACE เรียกฟังก์ชันเหล่านี้ด้วยรหัสแอป (ผ่าน anon key) · รหัสผิด = ปฏิเสธ
create or replace function public.ace_put_bg(p_key text, p_id text, p_name text, p_sort integer, p_audio text) returns void
language plpgsql security definer set search_path = public, ace_private as $$
begin
  if not ace_private.key_ok(p_key) then raise exception 'wrong app key' using errcode = '42501'; end if;
  insert into public.voice_bgs (id, name, sort, audio, updated_at) values (p_id, p_name, p_sort, p_audio, now())
  on conflict (id) do update set name = excluded.name, sort = excluded.sort, audio = excluded.audio, updated_at = now();
end $$;

create or replace function public.ace_name_bg(p_key text, p_id text, p_name text, p_sort integer) returns void
language plpgsql security definer set search_path = public, ace_private as $$
begin
  if not ace_private.key_ok(p_key) then raise exception 'wrong app key' using errcode = '42501'; end if;
  update public.voice_bgs set name = p_name, sort = p_sort, updated_at = now() where id = p_id;
end $$;

create or replace function public.ace_drop_bg(p_key text, p_id text) returns void
language plpgsql security definer set search_path = public, ace_private as $$
begin
  if not ace_private.key_ok(p_key) then raise exception 'wrong app key' using errcode = '42501'; end if;
  delete from public.voice_bgs where id = p_id;
end $$;

create or replace function public.ace_put_page(p_key text, p_settings jsonb) returns void
language plpgsql security definer set search_path = public, ace_private as $$
begin
  if not ace_private.key_ok(p_key) then raise exception 'wrong app key' using errcode = '42501'; end if;
  if jsonb_typeof(p_settings) <> 'object' or char_length(p_settings::text) > 4000 then raise exception 'bad settings'; end if;
  insert into public.page_settings (id, settings, updated_at) values (1, p_settings, now())
  on conflict (id) do update set settings = excluded.settings, updated_at = now();
end $$;

-- ACEACE ลองรหัสก่อนใช้ (ตอบ true / false อย่างเดียว)
create or replace function public.ace_check_key(p_key text) returns boolean
language sql stable security definer set search_path = public, ace_private as $$
  select ace_private.key_ok(p_key);
$$;

revoke all on function public.ace_put_bg(text, text, text, integer, text) from public;
revoke all on function public.ace_name_bg(text, text, text, integer) from public;
revoke all on function public.ace_drop_bg(text, text) from public;
revoke all on function public.ace_put_page(text, jsonb) from public;
revoke all on function public.ace_check_key(text) from public;
grant execute on function public.ace_put_bg(text, text, text, integer, text) to anon;
grant execute on function public.ace_name_bg(text, text, text, integer) to anon;
grant execute on function public.ace_drop_bg(text, text) to anon;
grant execute on function public.ace_put_page(text, jsonb) to anon;
grant execute on function public.ace_check_key(text) to anon;

-- เหมือน setup-voice.sql ทุกข้อ เพิ่มแค่: ชื่อเอฟเฟกต์ (a-z ยาว 2-12) และรหัส BG (a-z 0-9 ยาว 6-24) หรือไม่ใส่ · ได้เฉพาะเมื่อมีเสียง
drop policy if exists "anyone can submit slip" on public.slips;
create policy "anyone can submit slip" on public.slips for insert to anon
  with check (
    amount >= 20 and amount <= 100000
    and char_length(name) between 1 and 40
    and char_length(message) <= 255
    and char_length(trans_ref) between 10 and 40
    and (twitch is null or twitch ~ '^[a-z0-9_]{3,25}$')
    and (tiktok is null or tiktok ~ '^[a-z0-9_.]{2,24}$')
    and (twitch is null or tiktok is null)
    and (
      video_url is null
      or (amount >= 50
          and (video_url ~ '^https://youtu\.be/[A-Za-z0-9_-]{11}$'
               or video_url ~ '^https://www\.tiktok\.com/embed/v2/[0-9]{8,25}$'
               or video_url ~ '^https://(vm|vt)\.tiktok\.com/[A-Za-z0-9]{5,20}/$'
               or video_url ~ '^https://www\.tiktok\.com/t/[A-Za-z0-9]{5,20}/$')
          and (video_start is null or video_start between 0 and 21600))
    )
    and (video_url is not null or video_start is null)
    and (voice_path is null or voice_path ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}/[A-Za-z0-9]{10,40}\.(webm|m4a|mp4|ogg)$')
    and (voice_effect is null or (voice_path is not null and voice_effect ~ '^[a-z]{2,12}$'))
    and (voice_bg is null or (voice_path is not null and voice_bg ~ '^[a-z0-9]{6,24}$'))
  );

create or replace function public.slip_to_alert() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.alerts (name, amount, message, video_url, video_start, twitch, tiktok, voice_path, voice_effect, voice_bg)
  values (new.name, new.amount, new.message, new.video_url, new.video_start, new.twitch, new.tiktok, new.voice_path,
          new.voice_effect, new.voice_bg);
  return new;
end $$;
