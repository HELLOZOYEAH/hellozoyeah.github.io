-- รันครั้งเดียวใน Supabase > SQL Editor *ก่อน* อัปหน้าเว็บที่มีปุ่มอัดเสียง (ต้องรัน setup-twitch.sql มาก่อนแล้ว) · รันซ้ำได้
-- คนโดเนตอัดเสียงสั้น ๆ ให้ ACE เปิดบนสตรีม (ACEACE ปรับดังเท่ากันและมี Limiter ก่อนเล่น · ตัดที่ความยาวที่ตั้งไว้ในแอป)

alter table public.slips  add column if not exists voice_path text;
alter table public.alerts add column if not exists voice_path text;

-- ที่เก็บเสียง: เปิดให้ฟังได้ (ACEACE ดาวน์โหลดไปเล่นบนสตรีมอยู่แล้ว) คนดูอัปโหลดได้อย่างเดียว ไฟล์ละไม่เกิน 2 MB
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('voices', 'voices', true, 2000000, array['audio/webm','audio/ogg','audio/mp4','audio/aac','audio/x-m4a','video/webm','video/mp4'])
on conflict (id) do update set public = true, file_size_limit = excluded.file_size_limit, allowed_mime_types = excluded.allowed_mime_types;
drop policy if exists "anyone can upload voice" on storage.objects;
create policy "anyone can upload voice" on storage.objects for insert to anon
  with check (bucket_id = 'voices' and name ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}/[A-Za-z0-9]{10,40}\.(webm|m4a|mp4|ogg)$');

-- เหมือน setup-twitch.sql ทุกข้อ เพิ่มแค่: ไฟล์เสียง (ชื่อตามที่หน้าเว็บตั้ง: วันที่/เลขรายการ.นามสกุล) หรือไม่ใส่
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
  );

create or replace function public.slip_to_alert() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.alerts (name, amount, message, video_url, video_start, twitch, tiktok, voice_path)
  values (new.name, new.amount, new.message, new.video_url, new.video_start, new.twitch, new.tiktok, new.voice_path);
  return new;
end $$;
