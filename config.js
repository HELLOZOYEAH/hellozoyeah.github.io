// ตั้งค่าระบบโดเนท — แก้ไฟล์นี้ไฟล์เดียว
window.DONATE_CONFIG = {
  channelName: "hellosoyeah",
  promptpay: "0850235251",      // เบอร์พร้อมเพย์ (หรือเลขบัตร 13 หลัก)
  minAmount: 20,
  videoMinAmount: 20,  // ส่งคลิปได้ตั้งแต่ยอดนี้ · ACEACE ตั้งเองได้ผ่าน Supabase (setup-voice-fx.sql) · เสียงหรือคลิปได้อย่างเดียว
  videoSeconds: 30,
  voiceMinAmount: 20,  // อัดเสียงให้ ACE เปิดได้ตั้งแต่ยอดนี้ (ต้องรัน setup-voice.sql ก่อน · ตรงกับ ACEACE: เสียงจากคนโดเนต)
  voiceSeconds: 25,    // อัดได้นานสุด (วินาที) · ACEACE ตั้งเองได้ผ่าน Supabase และตัดที่ความยาวนี้อีกชั้น
  quickAmounts: [20, 50, 100],
  // จาก Supabase > Project Settings > API
  supabaseUrl: "https://qftetivangjrmyyrsqsn.supabase.co",
  supabaseAnonKey: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InFmdGV0aXZhbmdqcm15eXJzcXNuIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTE4NTA2NTgsImV4cCI6MjEwNzQyNjY1OH0.V-cUojP-61oVeaCtfznBQY1k-RH5PAe3-pz4STjyM2w",
  alertSeconds: 8,
};
