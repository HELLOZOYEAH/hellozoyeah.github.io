// เปลี่ยนเสียงในเบราว์เซอร์ ให้ตรงกับที่ ACEACE ทำจริงบนสตรีม (aceace/donations/voice.py EFFECTS)
// คนโดเนตกดฟังก่อนส่ง: เอฟเฟกต์ → ปรับดังเท่ากัน → เสียงพื้นหลังคลอใต้ (ขึ้นก่อน เบาลงตอนพูด จางหายตอนจบ)
(function () {
  const NAMES = { real: "ต้นฉบับ", vibrato: "เสียงสั่น", chipmunk: "ชิปมังก์", giant: "ยักษ์", robot: "หุ่นยนต์",
                  cave: "ถ้ำ", radio: "วิทยุ", game: "เกม 8-bit", underwater: "ใต้น้ำ", reverse: "ย้อนหลัง" };
  const HINTS = { real: "ไม่เปลี่ยน", vibrato: "แนะนำ", chipmunk: "สูงเล็ก", giant: "ต่ำทุ้ม", robot: "โรบอท",
                  cave: "ก้องสะท้อน", radio: "เหมือนโทรมา", game: "แตกแบบเกม", underwater: "อู้อี้", reverse: "ถอยหลัง" };

  // FFmpeg vibrato: เส้นหน่วง 5 ms ที่ความหน่วงแกว่งตามคลื่น sine ระหว่าง 0 ถึง depth x 5 ms
  function vibrato(x, sr, f, d) {
    const size = Math.round(sr * 0.005), out = new Float32Array(x.length);
    for (let i = 0; i < x.length; i++) {
      const at = i - d * (size - 1) * (1 - Math.cos(2 * Math.PI * f * i / sr)) / 2, k = Math.floor(at), frac = at - k;
      const a = k >= 0 ? x[k] : 0, b = k + 1 >= 0 && k + 1 < x.length ? x[k + 1] : 0;
      out[i] = a + (b - a) * frac;
    }
    return out;
  }
  const hann = n => Float32Array.from({ length: n }, (_, i) => 0.5 - 0.5 * Math.cos(2 * Math.PI * i / n));
  // สูงขึ้นหรือต่ำลงแต่ความเร็วเท่าเดิม: ตัดเสียงเป็นเม็ดเล็ก ๆ เล่นแต่ละเม็ดเร็วหรือช้าลง แล้วซ้อนกัน
  function pitch(x, p) {
    const N = 2048, H = 512, w = hann(N), out = new Float32Array(x.length), sum = new Float32Array(x.length);
    for (let o = -N; o < x.length; o += H) {
      for (let k = 0; k < N; k++) {
        const j = o + k;
        if (j < 0 || j >= x.length) continue;
        const at = o + k * p, i = Math.floor(at), frac = at - i;
        const v = i >= 0 && i + 1 < x.length ? x[i] + (x[i + 1] - x[i]) * frac : 0;
        out[j] += v * w[k]; sum[j] += w[k];
      }
    }
    for (let j = 0; j < out.length; j++) out[j] = sum[j] > 1e-3 ? out[j] / sum[j] : 0;
    return out;
  }
  function fft(re, im, inverse) {
    const n = re.length;
    for (let i = 1, j = 0; i < n; i++) {
      let bit = n >> 1;
      for (; j & bit; bit >>= 1) j ^= bit;
      j ^= bit;
      if (i < j) { [re[i], re[j]] = [re[j], re[i]]; [im[i], im[j]] = [im[j], im[i]]; }
    }
    for (let len = 2; len <= n; len <<= 1) {
      const angle = (inverse ? 2 : -2) * Math.PI / len, wr = Math.cos(angle), wi = Math.sin(angle);
      for (let i = 0; i < n; i += len) {
        let cr = 1, ci = 0;
        for (let k = 0; k < len / 2; k++) {
          const a = i + k, b = a + len / 2, tr = re[b] * cr - im[b] * ci, ti = re[b] * ci + im[b] * cr;
          re[b] = re[a] - tr; im[b] = im[a] - ti; re[a] += tr; im[a] += ti;
          [cr, ci] = [cr * wr - ci * wi, cr * wi + ci * wr];
        }
      }
    }
  }
  // หุ่นยนต์: เก็บแค่ความดังของแต่ละความถี่ ทิ้งเฟส (FFmpeg afftfilt แบบเดียวกัน)
  function robot(x) {
    const N = 512, H = 128, w = hann(N), out = new Float32Array(x.length), sum = new Float32Array(x.length);
    const re = new Float32Array(N), im = new Float32Array(N);
    for (let o = 0; o < x.length; o += H) {
      for (let k = 0; k < N; k++) { re[k] = (o + k < x.length ? x[o + k] : 0) * w[k]; im[k] = 0; }
      fft(re, im, false);
      // the upper half mirrors the lower (a real signal), as FFmpeg's half spectrum does
      for (let k = 0; k < N; k++) { const m = Math.hypot(re[k], im[k]); re[k] = 0; im[k] = k <= N / 2 ? m : -m; }
      fft(re, im, true);
      for (let k = 0; k < N && o + k < x.length; k++) { out[o + k] += re[k] / N * w[k]; sum[o + k] += w[k] * w[k]; }
    }
    for (let j = 0; j < out.length; j++) out[j] = sum[j] > 1e-3 ? out[j] / sum[j] : 0;
    return out;
  }
  // FFmpeg aecho: เสียงเดิม x in + เสียงสะท้อนแต่ละจังหวะ x decay แล้ว x out
  function echo(x, sr, inGain, outGain, delays, decays) {
    const out = new Float32Array(x.length);
    for (let i = 0; i < x.length; i++) {
      let v = x[i] * inGain;
      delays.forEach((ms, n) => { const j = i - Math.round(ms * sr / 1000); if (j >= 0) v += x[j] * decays[n]; });
      out[i] = v * outGain;
    }
    return out;
  }
  // ตัวกรองแบบเดียวกับ FFmpeg highpass / lowpass (2 pole, Q 0.707)
  function biquad(x, sr, type, f) {
    const w = 2 * Math.PI * f / sr, cos = Math.cos(w), alpha = Math.sin(w) / (2 * Math.SQRT1_2);
    const b0 = type === "low" ? (1 - cos) / 2 : (1 + cos) / 2, b1 = type === "low" ? 1 - cos : -(1 + cos), b2 = b0;
    const a0 = 1 + alpha, a1 = -2 * cos, a2 = 1 - alpha, out = new Float32Array(x.length);
    let x1 = 0, x2 = 0, y1 = 0, y2 = 0;
    for (let i = 0; i < x.length; i++) {
      const y = (b0 * x[i] + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2) / a0;
      x2 = x1; x1 = x[i]; y2 = y1; y1 = y; out[i] = y;
    }
    return out;
  }
  // ลดบิตและค้างค่าทีละช่วง แบบเสียงเกมเก่า (FFmpeg acrusher)
  function crush(x, bits, hold, mix) {
    const levels = Math.pow(2, bits - 1), out = new Float32Array(x.length);
    let held = 0;
    for (let i = 0; i < x.length; i++) {
      if (i % hold === 0) held = Math.round(x[i] * levels) / levels;
      out[i] = x[i] * (1 - mix) + held * mix;
    }
    return out;
  }
  function apply(effect, x, sr) {
    switch (effect) {
      case "vibrato": return vibrato(x, sr, 7.5, 1.0);
      case "chipmunk": return pitch(x, 1.45);
      case "giant": return pitch(x, 0.7);
      case "robot": return robot(x);
      case "cave": return echo(x, sr, 0.8, 0.85, [110, 230, 370], [0.5, 0.33, 0.2]);
      case "radio": return crush(biquad(biquad(x, sr, "high", 380), sr, "low", 3100), 10, 1, 0.4);
      case "game": return crush(x, 5, 6, 1);
      case "underwater": return echo(vibrato(biquad(x, sr, "low", 550), sr, 2.5, 0.25), sr, 0.6, 0.5, [40], [0.4]);
      case "reverse": return Float32Array.from(x).reverse();
      default: return Float32Array.from(x);
    }
  }
  // ดังเท่ากับเสียงอื่นแบบเดียวกับแอป (voice.py level 'gentle', 2026-10-18): เพิ่มลดทั้งคลิปทีเดียว เสียงดังเบาตามจริง
  // แล้ว Limiter นุ่ม ๆ กดเฉพาะช่วงที่ดังเกิน -1 dB (ลงใน 5 ms ก่อนถึงยอด คืนใน 150 ms) ไม่ตัดคลื่นทีละจุด
  function even(x, sr) {
    let sum = 0, n = 0;
    for (const v of x) if (Math.abs(v) > 0.003) { sum += v * v; n++; }
    if (!n) return Float32Array.from(x);
    const gain = Math.min(30, 0.25 / Math.sqrt(sum / n)), top = 0.89;
    const B = Math.max(1, Math.round(sr / 1000)), count = Math.ceil(x.length / B), need = new Float32Array(count);
    for (let i = 0; i < count; i++) {
      let m = 0;
      for (let k = i * B; k < Math.min(x.length, (i + 1) * B); k++) m = Math.max(m, Math.abs(x[k] * gain));
      need[i] = m > top ? top / m : 1;
    }
    const smooth = new Float32Array(count), back = 1 - Math.exp(-1 / 150);
    let g = 1;
    for (let i = 0; i < count; i++) {
      let want = 1;
      for (let j = i; j <= Math.min(count - 1, i + 5); j++) want = Math.min(want, need[j]);
      g = want < g ? want : g + (want - g) * back;
      smooth[i] = g;
    }
    const out = new Float32Array(x.length);
    for (let k = 0; k < x.length; k++) {
      const at = Math.min(count - 1, Math.max(0, k / B - 0.5)), i = Math.floor(at), f = at - i;
      const level = smooth[i] + ((smooth[Math.min(count - 1, i + 1)] || smooth[i]) - smooth[i]) * f;
      out[k] = Math.max(-top, Math.min(top, x[k] * gain * level));
    }
    return out;
  }
  function mono(buffer) {
    const out = new Float32Array(buffer.length);
    for (let c = 0; c < buffer.numberOfChannels; c++) buffer.getChannelData(c).forEach((v, i) => { out[i] += v / buffer.numberOfChannels; });
    return out;
  }
  // ทั้งชุดตามที่ OBS เล่น: BG ขึ้นก่อน lead วิ → เสียงคน (BG เบาลงเหลือ duck%) → BG จาง 1.5 วิ
  function render(voiceBuffer, effect, bgBuffer, s, ctx) {
    const sr = voiceBuffer.sampleRate, seconds = Math.max(1, +s.voice_seconds || 10);
    const voice = even(apply(effect, mono(voiceBuffer).slice(0, Math.round(seconds * sr)), sr), sr);
    const vGain = Math.max(0, Math.min(1, (s.voice_volume != null ? s.voice_volume : 80) / 100));
    const bg = bgBuffer ? mono(bgBuffer) : null;
    const lead = bg ? Math.round(Math.max(0, Math.min(3, +s.bg_lead || 0)) * sr) : 0, tail = bg ? Math.round(1.5 * sr) : 0;
    const total = lead + voice.length + tail, out = new Float32Array(total);
    const bgVol = Math.max(0, Math.min(1, (s.bg_volume != null ? s.bg_volume : 40) / 100));
    const duck = Math.min(bgVol, Math.max(0, (s.bg_duck != null ? s.bg_duck : 30) / 100)), ramp = Math.round(0.25 * sr);
    for (let i = 0; i < total; i++) {
      let v = i >= lead && i < lead + voice.length ? voice[i - lead] * vGain : 0;
      if (bg && bg.length) {
        const u = i - lead, level = i < lead ? bgVol * Math.min(1, i / (0.3 * sr))
          : u < voice.length ? bgVol + (duck - bgVol) * Math.min(1, u / ramp)
          : duck * Math.max(0, 1 - (u - voice.length) / tail);
        v += bg[i % bg.length] * level;
      }
      out[i] = Math.max(-1, Math.min(1, v));
    }
    const buffer = ctx.createBuffer(1, total, sr);
    buffer.copyToChannel(out, 0);
    return buffer;
  }
  window.VoiceFx = { NAMES, HINTS, apply, render };
})();
