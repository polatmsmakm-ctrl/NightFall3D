// محرك الحركة: نفس الكود يشتغل على السيرفر وعلى الجوال (توقّع الحركة محلياً ثم مطابقتها مع السيرفر)
(function (root) {
  const C = {
    DT: 1 / 30,            // خطوة المحاكاة الثابتة
    R: 14,                 // نصف قطر اللاعب
    DEAD: 0.12,            // المنطقة الميتة للجويستك
    RUN_AT: 0.6,           // أقل من كذا = مشي هادي، أكثر = جري
    // الناجي
    S_WALK: 78, S_RUN: 150, S_SPRINT: 205, S_CROUCH: 62, S_DOWNED: 28, S_BOOST: 200,
    HURT_K: 0.97,
    SPRINT_TIME: 3.6,      // ثواني ركض سريع من طاقة كاملة
    REGEN_TIME: 7.0,       // ثواني لتعبئة الطاقة كاملة
    REGEN_DELAY: 1.0,      // انتظار قبل ما تبدأ الطاقة ترجع
    EXH_UNTIL: 0.3,        // لو خلصت الطاقة لازم ترجع 30% قبل الركض
    // القاتل
    K_WALK: 86, K_RUN: 172,
    LUNGE_T: 0.34, LUNGE_SPEED: 265, ATK_T: 0.75,
    MISS_CD: 0.75, MISS_SLOW: 0.75, MISS_SLOW_K: 0.5,
    HIT_CD: 1.7, HIT_SLOW: 1.7, HIT_SLOW_K: 0.28,
    ATTACK_REACH: 60, ATTACK_ARC: 1.15,   // مدى الضربة ونصف زاوية المخروط (راديان)
    HIT_BOOST: 1.8,
    // تسارع
    ACCEL: 1150, DECEL: 1500, TURN_S: 14, TURN_K: 10,
  };

  function reset(p) {
    p.vx = 0; p.vy = 0; p.stam = 1; p.exh = false; p.rest = 0;
    p.cr = false; p.sp = false; p.boost = 0; p.slow = 0; p.slowK = 1;
    p.lunge = 0; p.lfa = 0; p.cd = 0; p.atk = 0; p.swing = false;
  }

  function resolveWalls(p, walls) {
    const R = C.R;
    for (let pass = 0; pass < 2; pass++) {
      for (let i = 0; i < walls.length; i++) {
        const x = walls[i][0], y = walls[i][1], w = walls[i][2], h = walls[i][3];
        const cx = Math.max(x, Math.min(p.x, x + w));
        const cy = Math.max(y, Math.min(p.y, y + h));
        const dx = p.x - cx, dy = p.y - cy;
        const d2 = dx * dx + dy * dy;
        if (d2 >= R * R) continue;
        if (d2 > 0.0001) {
          const d = Math.sqrt(d2), push = R - d;
          p.x += (dx / d) * push; p.y += (dy / d) * push;
        } else {
          const l = p.x - x, r = x + w - p.x, t = p.y - y, b = y + h - p.y;
          const m = Math.min(l, r, t, b);
          if (m === l) p.x = x - R; else if (m === r) p.x = x + w + R;
          else if (m === t) p.y = y - R; else p.y = y + h + R;
        }
      }
    }
  }

  // خطوة واحدة. inp = { dx, dy, sp, cr, act, aim }
  function step(p, inp, walls) {
    const dt = C.DT;
    if (p.cd > 0) p.cd -= dt;
    if (p.atk > 0) p.atk -= dt;
    if (p.boost > 0) p.boost -= dt;
    if (p.slow > 0) p.slow -= dt;
    if (p.st === 'dead' || p.st === 'escaped') { p.vx = p.vy = 0; p.sp = p.cr = false; return; }

    let ix = +inp.dx || 0, iy = +inp.dy || 0, len = Math.sqrt(ix * ix + iy * iy);
    if (len > 1) { ix /= len; iy /= len; len = 1; }
    if (len < C.DEAD) { ix = iy = 0; len = 0; }
    const killer = p.r === 'k', alive = p.st === 'alive';

    // انحناء + ركض + طاقة
    p.cr = !killer && alive && !!inp.cr;
    p.sp = !killer && alive && !!inp.sp && !p.cr && len >= C.RUN_AT && !p.exh && p.stam > 0;
    if (p.sp) {
      p.stam -= dt / C.SPRINT_TIME; p.rest = C.REGEN_DELAY;
      if (p.stam <= 0) { p.stam = 0; p.exh = true; p.sp = false; }
    } else {
      if (p.rest > 0) p.rest -= dt;
      else if (p.stam < 1) p.stam = Math.min(1, p.stam + dt / C.REGEN_TIME);
      if (p.exh && p.stam >= C.EXH_UNTIL) p.exh = false;
    }

    // بداية هجمة القاتل: اندفاعة قصيرة باتجاه الكاميرا
    if (killer && inp.act && p.cd <= 0 && p.lunge <= 0) {
      p.atk = C.ATK_T; p.lunge = C.LUNGE_T; p.cd = C.LUNGE_T + C.MISS_CD;
      p.lfa = (typeof inp.aim === 'number' && isFinite(inp.aim)) ? inp.aim : p.fa;
      p.swing = true;
    }

    // السرعة المطلوبة
    let tx = 0, ty = 0, accel = len > 0 ? C.ACCEL : C.DECEL;
    if (killer && p.lunge > 0) {
      tx = Math.cos(p.lfa) * C.LUNGE_SPEED; ty = Math.sin(p.lfa) * C.LUNGE_SPEED; accel = 6000;
      p.lunge -= dt;
      if (p.lunge <= 0) { p.lunge = 0; p.slow = C.MISS_SLOW; p.slowK = C.MISS_SLOW_K; }
    } else if (len > 0) {
      let max;
      if (killer) max = (len >= C.RUN_AT ? C.K_RUN : C.K_WALK) * (p.slow > 0 ? p.slowK : 1);
      else if (p.st === 'downed') max = C.S_DOWNED;
      else if (p.cr) max = C.S_CROUCH;
      else if (p.boost > 0) max = C.S_BOOST;
      else {
        max = p.sp ? C.S_SPRINT : (len >= C.RUN_AT ? C.S_RUN : C.S_WALK);
        if (p.hp === 1) max *= C.HURT_K;
      }
      tx = ix / len * max; ty = iy / len * max;
    }
    const dvx = tx - p.vx, dvy = ty - p.vy, dv = Math.sqrt(dvx * dvx + dvy * dvy), st = accel * dt;
    if (dv <= st) { p.vx = tx; p.vy = ty; } else { p.vx += dvx / dv * st; p.vy += dvy / dv * st; }

    // حركة + تصادم (الانزلاق على الجدران يطلع طبيعي من دفع الدائرة)
    const ox = p.x, oy = p.y;
    p.x += p.vx * dt; p.y += p.vy * dt;
    resolveWalls(p, walls);
    p.vx = (p.x - ox) / dt; p.vy = (p.y - oy) / dt;

    // دوران ناعم للجسم
    const spd = Math.sqrt(p.vx * p.vx + p.vy * p.vy);
    let tf = null;
    if (killer && (p.lunge > 0 || p.atk > C.ATK_T - 0.5)) tf = p.lfa;
    else if (spd > 10 && len > 0) tf = Math.atan2(iy, ix);
    if (tf !== null) {
      let da = tf - p.fa; while (da > Math.PI) da -= 2 * Math.PI; while (da < -Math.PI) da += 2 * Math.PI;
      const mx = (killer ? C.TURN_K : C.TURN_S) * dt;
      p.fa += Math.max(-mx, Math.min(mx, da));
      if (p.fa > Math.PI) p.fa -= 2 * Math.PI; else if (p.fa < -Math.PI) p.fa += 2 * Math.PI;
    }
  }

  // الحقول اللي يحتاجها العميل عشان يكمل التوقّع من حالة السيرفر
  const KEYS = ['x', 'y', 'vx', 'vy', 'fa', 'stam', 'exh', 'rest', 'cr', 'sp', 'boost', 'slow', 'slowK', 'lunge', 'lfa', 'cd', 'atk'];
  function pack(p) { const o = {}; for (const k of KEYS) o[k] = p[k]; return o; }
  function unpack(p, o) { for (const k of KEYS) p[k] = o[k]; }

  const SIM = { C, reset, step, resolveWalls, pack, unpack };
  if (typeof module !== 'undefined' && module.exports) module.exports = SIM;
  else root.SIM = SIM;
})(typeof window !== 'undefined' ? window : globalThis);
