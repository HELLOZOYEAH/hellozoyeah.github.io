-- รันครั้งเดียวใน Supabase > SQL Editor *ก่อน* อัปหน้าเว็บที่มีช่องคลิป
-- เพิ่มคลิป YouTube / TikTok กับโดเนต (ตั้งแต่ 50 บาท) และยอดขั้นต่ำ 20 บาท · รันซ้ำได้

alter table public.slips  add column if not exists video_url   text;
alter table public.slips  add column if not exists video_start integer;
alter table public.alerts add column if not exists video_url   text;
alter table public.alerts add column if not exists video_start integer;

-- ตรวจซ้ำฝั่งฐานข้อมูล: ขั้นต่ำ 20 บาท, คลิปได้เฉพาะ 50 บาทขึ้นไป และต้องเป็นลิงก์ที่หน้าเว็บจัดรูปแล้ว (youtu.be/<id>, tiktok.com/embed/v2/<id> หรือลิงก์สั้น TikTok)
drop policy if exists "anyone can submit slip" on public.slips;
create policy "anyone can submit slip" on public.slips for insert to anon
  with check (
    amount >= 20 and amount <= 100000
    and char_length(name) between 1 and 40
    and char_length(message) <= 255
    and char_length(trans_ref) between 10 and 40
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
  insert into public.alerts (name, amount, message, video_url, video_start)
  values (new.name, new.amount, new.message, new.video_url, new.video_start);
  return new;
end $$;
