-- รันครั้งเดียวใน Supabase > SQL Editor *ก่อน* อัปหน้าเว็บที่มีช่องชื่อ Twitch / TikTok (ต้องรัน setup-video.sql มาก่อนแล้ว) · รันซ้ำได้
-- คนโดเนตบอกได้ว่าดูจาก Twitch หรือ TikTok (ไม่บังคับ) · ชื่อ Twitch: ACEACE ให้หัวใจบัญชีนั้นและผูกชื่อโดเนตให้เอง

alter table public.slips  add column if not exists twitch text;
alter table public.alerts add column if not exists twitch text;
alter table public.slips  add column if not exists tiktok text;
alter table public.alerts add column if not exists tiktok text;

-- เหมือน setup-video.sql ทุกข้อ เพิ่มแค่: ชื่อ Twitch (a-z 0-9 _ ยาว 3-25) หรือชื่อ TikTok (a-z 0-9 _ . ยาว 2-24) อย่างใดอย่างหนึ่ง หรือไม่ใส่
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
  );

create or replace function public.slip_to_alert() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.alerts (name, amount, message, video_url, video_start, twitch, tiktok)
  values (new.name, new.amount, new.message, new.video_url, new.video_start, new.twitch, new.tiktok);
  return new;
end $$;

