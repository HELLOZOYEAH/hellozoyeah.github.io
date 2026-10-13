// ฟังก์ชันใช้ร่วม: CRC16, สร้าง QR พร้อมเพย์, อ่าน QR สลิป
function crc16(s) {
  let c = 0xffff;
  for (const b of new TextEncoder().encode(s)) {
    c ^= b << 8;
    for (let i = 0; i < 8; i++) c = (c & 0x8000 ? (c << 1) ^ 0x1021 : c << 1) & 0xffff;
  }
  return c.toString(16).toUpperCase().padStart(4, "0");
}

function tlv(id, v) { return id + String(v.length).padStart(2, "0") + v; }

function parseTlv(s) {
  const out = {};
  let i = 0;
  while (i + 4 <= s.length) {
    const id = s.substr(i, 2), len = parseInt(s.substr(i + 2, 2), 10);
    if (isNaN(len)) return null;
    out[id] = s.substr(i + 4, len);
    i += 4 + len;
  }
  return i === s.length ? out : null;
}

// payload พร้อมเพย์ (EMVCo) พร้อมยอดเงิน
function promptpayPayload(id, amount) {
  id = id.replace(/\D/g, "");
  const target = id.length >= 13
    ? tlv("02", id)
    : tlv("01", ("0000000000000" + "66" + id.replace(/^0/, "")).slice(-13));
  let p = tlv("00", "01") + tlv("01", amount ? "12" : "11") +
    tlv("29", tlv("00", "A000000677010111") + target) +
    tlv("53", "764") + (amount ? tlv("54", Number(amount).toFixed(2)) : "") +
    tlv("58", "TH") + "6304";
  return p + crc16(p);
}

// ตรวจ QR บนสลิปธนาคารไทย -> { bank, transRef } หรือ null
function parseSlipQr(text) {
  if (!text || !/9104[0-9A-F]{4}$/i.test(text)) return null;
  if (crc16(text.slice(0, -4)) !== text.slice(-4).toUpperCase()) return null;
  const top = parseTlv(text);
  if (!top || top["51"] !== "TH" || !top["00"]) return null;
  const inner = parseTlv(top["00"]);
  if (!inner || !inner["01"] || !inner["02"]) return null;
  return { bank: inner["01"], transRef: inner["02"] };
}

const BANKS = {
  "002": "กรุงเทพ", "004": "กสิกรไทย", "006": "กรุงไทย", "011": "ทหารไทยธนชาต",
  "014": "ไทยพาณิชย์", "025": "กรุงศรี", "030": "ออมสิน", "034": "ธ.ก.ส.",
  "069": "เกียรตินาคินภัทร", "022": "ซีไอเอ็มบี", "024": "ยูโอบี", "073": "แลนด์ แอนด์ เฮ้าส์",
};
