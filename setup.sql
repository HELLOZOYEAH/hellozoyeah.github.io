-- วางทั้งไฟล์ใน Supabase > SQL Editor แล้วกด Run ครั้งเดียว

-- สลิปทั้งหมด (คนดูเพิ่มได้อย่างเดียว อ่านไม่ได้) เลขรายการซ้ำ = ปฏิเสธ
create table public.slips (
  trans_ref  text primary key,
  bank       text not null,
  name       text not null,
  amount     numeric(10,2) not null,
  message    text not null default '',
  slip_path  text,
  created_at timestamptz not null default now()
);
alter table public.slips enable row level security;
create policy "anyone can submit slip" on public.slips for insert to anon
  with check (
    amount >= 10 and amount <= 100000
    and char_length(name) between 1 and 40
    and char_length(message) <= 255
    and char_length(trans_ref) between 10 and 40
  );

-- รายการแจ้งเตือนขึ้นจอ (มีแค่ชื่อ ยอด ข้อความ)
create table public.alerts (
  id         bigint generated always as identity primary key,
  name       text not null,
  amount     numeric(10,2) not null,
  message    text not null default '',
  created_at timestamptz not null default now()
);
alter table public.alerts enable row level security;
create policy "anyone can read alerts" on public.alerts for select to anon using (true);

create function public.slip_to_alert() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.alerts (name, amount, message) values (new.name, new.amount, new.message);
  return new;
end $$;
create trigger slip_to_alert after insert on public.slips
  for each row execute function public.slip_to_alert();

alter publication supabase_realtime add table public.alerts;

-- ที่เก็บรูปสลิป (ส่วนตัว อัปโหลดได้อย่างเดียว)
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('slips', 'slips', false, 5242880, array['image/jpeg','image/png','image/webp','image/heic']);
create policy "anyone can upload slip" on storage.objects for insert to anon
  with check (bucket_id = 'slips');
