-- รันครั้งเดียวใน Supabase > SQL Editor *หลัง* setup-voice-fx.sql และ *ก่อน* อัปหน้าเว็บที่ปรับความดังพื้นหลังได้ · รันซ้ำได้
-- (2026-10-18) คนโดเนตตั้งความดังเสียงพื้นหลังเอง (0-100) และอัดพร้อมเพลงได้ (voice_bg_sync: เสียงเริ่มพร้อมเพลง ไม่มีช่วงเพลงนำ)
-- ทั้งสองค่าใส่ได้เฉพาะเมื่อเลือกเสียงพื้นหลัง · ไม่ใส่ = ใช้ค่าที่สตรีมเมอร์ตั้งในแอป

alter table public.slips  add column if not exists voice_bg_volume integer;
alter table public.slips  add column if not exists voice_bg_sync   boolean;
alter table public.alerts add column if not exists voice_bg_volume integer;
alter table public.alerts add column if not exists voice_bg_sync   boolean;

-- เหมือน setup-voice-fx.sql เพิ่มแค่สองบรรทัดท้าย
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
      or (amount >= 20
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
    and (video_url is null or voice_path is null)
    and (voice_bg_volume is null or (voice_bg is not null and voice_bg_volume between 0 and 100))
    and (voice_bg_sync is null or voice_bg is not null)
  );

create or replace function public.slip_to_alert() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.alerts (name, amount, message, video_url, video_start, twitch, tiktok, voice_path, voice_effect, voice_bg,
                             voice_bg_volume, voice_bg_sync)
  values (new.name, new.amount, new.message, new.video_url, new.video_start, new.twitch, new.tiktok, new.voice_path,
          new.voice_effect, new.voice_bg, new.voice_bg_volume, new.voice_bg_sync);
  return new;
end $$;
