// demo-scene.jsx — Demo Memo screens (list, recording, playback, onboarding)
// Mounts inside window.IOSDevice from ios-frame.jsx. No assets, no deps.
const { useState, useRef, useEffect, useCallback } = React;

// ── palette ───────────────────────────────────────────────
const ACCENT = '#ff9f0a';
const ACCENT_DEEP = '#ff7a00';
const rgbaAccent = (a) => `rgba(255,159,10,${a})`;

// warmth 0..1 → bar color (neutral grey → warm amber; hue stays in amber family)
function warmColor(warmth, alpha = 1) {
  const l = 0.74 - warmth * 0.07;
  const c = 0.008 + warmth * 0.16;
  const h = 72 - warmth * 10;
  return `oklch(${l} ${c} ${h} / ${alpha})`;
}

// seeded rng
function rng(seed) { let s = seed; return () => (s = (s * 16807) % 2147483647) / 2147483647; }

// theme tokens (light / dark)
function TH(dark) {
  return dark ? {
    pageBg: 'linear-gradient(180deg,#1c1c1e 0%,#000 100%)',
    text: '#fff', text2: 'rgba(235,235,245,0.6)', text3: 'rgba(235,235,245,0.4)', text4: 'rgba(235,235,245,0.3)',
    card: 'rgba(118,118,128,0.16)', divider: 'rgba(255,255,255,0.1)',
    barOff: 'rgba(235,235,245,0.22)', recBorder: 'rgba(255,255,255,0.24)',
    bar: 'rgba(30,30,32,0.65)', tickMaj: 'rgba(235,235,245,0.4)', tickMin: 'rgba(235,235,245,0.18)',
  } : {
    pageBg: 'linear-gradient(180deg,#fbfbfd 0%,#f2f2f6 100%)',
    text: '#1c1c1e', text2: 'rgba(60,60,67,0.5)', text3: 'rgba(60,60,67,0.4)', text4: 'rgba(60,60,67,0.3)',
    card: '#fff', divider: 'rgba(60,60,67,0.1)',
    barOff: 'rgba(120,120,128,0.28)', recBorder: 'rgba(0,0,0,0.14)',
    bar: 'rgba(255,255,255,0.6)', tickMaj: 'rgba(60,60,67,0.32)', tickMin: 'rgba(60,60,67,0.15)',
  };
}
function makeBars(n, seed) {
  const r = rng(seed);
  return Array.from({ length: n }, (_, i) => {
    const env = Math.sin((i / n) * Math.PI); // fade at edges
    return 0.12 + (0.25 + r() * 0.75) * (0.45 + env * 0.55);
  });
}

// live input sample by signal regime — drives clip / low-signal coaching in monitoring
function levelSample(signal) {
  const r = Math.random();
  if (signal === 'hot') return 0.6 + r * 0.5;      // 0.60..1.10 — frequently clips (>= 0.9)
  if (signal === 'quiet') return 0.05 + r * 0.11;  // 0.05..0.16 — stays flat
  return 0.2 + r * 0.55;                            // 0.20..0.75 — healthy, never clips
}

// ── generic pointer-drag hook ─────────────────────────────
function useDrag(onMove) {
  const ref = useRef(null);
  const start = useCallback((e) => {
    e.preventDefault();
    const el = ref.current;
    const handle = (ev) => {
      const p = ev.touches ? ev.touches[0] : ev;
      const r = el.getBoundingClientRect();
      onMove(p.clientX, p.clientY, r);
    };
    handle(e);
    const up = () => {
      window.removeEventListener('pointermove', handle);
      window.removeEventListener('pointerup', up);
    };
    window.addEventListener('pointermove', handle);
    window.addEventListener('pointerup', up);
  }, [onMove]);
  return { ref, onPointerDown: start };
}

// ── shared waveform (static, symmetric) ───────────────────
function Waveform({ bars, progress = 0, warmth = 0, space = 0, height = 132, playing = false, dark = false, clip = false }) {
  const neutral = dark ? 'rgba(235,235,245,0.22)' : 'rgba(120,120,128,0.28)';
  return (
    <div style={{ position: 'relative', height, width: '100%' }}>
      {/* ChromaVerb-style bloom: warm radial aura + faint expanding ring, widens with space */}
      <div style={{ position: 'absolute', inset: 0, display: 'flex', alignItems: 'center', justifyContent: 'center', pointerEvents: 'none' }}>
        <div style={{ width: `${58 + space * 66}%`, height: `${118 + space * 90}%`, borderRadius: '50%', background: `radial-gradient(closest-side, ${rgbaAccent(0.09 + space * 0.16)}, transparent 72%)`, filter: `blur(${7 + space * 11}px)`, transition: 'all .2s ease' }} />
      </div>
      <div style={{
        position: 'relative', height: '100%', width: '100%',
        display: 'flex', alignItems: 'center', gap: 3, justifyContent: 'center',
      }}>
        {bars.map((b, i) => {
          const played = i / bars.length <= progress;
          const col = played
            ? warmColor(0.35 + warmth * 0.65, 1)
            : warmColor(warmth * 0.5, dark ? 0.24 : 0.30);
          const base = played ? col : neutral;
          const isClip = clip && b >= 0.9;
          return (
            <div key={i} style={{
              flex: 1, minWidth: 0, height: `${b * 100}%`, borderRadius: 4,
              background: isClip ? `linear-gradient(to top, ${base} 64%, #ff453a 64%)` : base,
              boxShadow: isClip ? '0 0 7px rgba(255,69,58,0.6)' : (played && warmth > 0.3 ? `0 0 ${2 + warmth * 8}px ${rgbaAccent(warmth * 0.5)}` : 'none'),
              transition: 'background .12s, box-shadow .12s',
            }} />
          );
        })}
      </div>
    </div>
  );
}

// ── centre-locked scrub waveform ──────────────────────────
// The take scrolls UNDER a fixed centre marker (echoing the Enhance dial, where
// the tick scale scrolls under a fixed centre marker). Left of centre = played
// (warm), right = still to come (neutral). `marker` picks the treatment.
function ScrubWaveform({ bars, p, warmth = 0, height = 120, dark = false, marker = 'twin', timeLabel = '', played = 'amber', dim = '', fadeSpan = 9, fadeMin = 0.26, tall = '', dot = 'on', lineW = 3, edge = 12 }) {
  const t = TH(dark);
  const BAR_W = 5, GAP = 3, STEP = BAR_W + GAP;
  const n = bars.length;
  const playIdx = p * (n - 1);
  const neutral = t.barOff;
  // played-side (left of centre) colour — kept clearly distinct from the orange marker
  const playedTones = {
    amber: warmColor(0.35 + warmth * 0.65, 1),
    graphite: dark ? 'rgba(214,218,228,0.92)' : 'rgba(70,76,92,0.9)',
    teal: dark ? '#5ec9c7' : '#1c8385',
    bronze: dark ? '#cf7a24' : '#8f4e0e',
  };
  const AMB = (a) => warmColor(0.35 + warmth * 0.65, a); // warm amber at a given alpha
  // dim the amber as it approaches the marker so the orange playhead separates cleanly
  const amberAt = (i) => {
    const d = playIdx - i; // 0 at the marker, grows to the left
    if (dim === 'fade') return AMB(fadeMin + (1 - fadeMin) * Math.min(1, d / fadeSpan));          // eases off over `fadeSpan` bars, down to `fadeMin`
    if (dim === 'gradient') return AMB(0.3 + 0.7 * Math.min(1, playIdx > 0 ? d / playIdx : 1)); // ramp across whole played side
    if (dim === 'halo') return AMB(d < 3.5 ? 0.15 : 1);                          // crisp faint gap around the marker
    return AMB(1);
  };
  const playedSolid = playedTones[played] || playedTones.amber;
  const barColor = (i) => {
    if (i > playIdx) return neutral;
    return dim ? amberAt(i) : playedSolid;
  };
  const maxAmp = Math.max.apply(null, bars) || 1; // normalise so the tallest peak fits (no top/bottom clipping)
  const edgeMask = edge > 0 ? `linear-gradient(90deg, transparent, #000 ${edge}%, #000 ${100 - edge}%, transparent)` : 'none';
  return (
    <div style={{ position: 'relative', height, width: '100%' }}>
      {/* scrolling strip, edge-masked like the Enhance track */}
      <div style={{
        position: 'absolute', inset: 0, overflow: 'hidden',
        WebkitMaskImage: edgeMask,
        maskImage: edgeMask,
      }}>
        <div style={{ position: 'absolute', top: 0, bottom: 0, left: `calc(50% - ${playIdx * STEP}px)`, display: 'flex', alignItems: 'center', gap: GAP, willChange: 'left' }}>
          {bars.map((b, i) => (
            <div key={i} style={{ flex: 'none', width: BAR_W, height: `${(b / maxAmp) * 94}%`, borderRadius: 3, background: barColor(i), transition: 'background .1s' }} />
          ))}
        </div>
      </div>
      {/* fixed centre marker */}
      <div style={{ position: 'absolute', inset: 0, pointerEvents: 'none', zIndex: 2 }}>
        {marker === 'twin' && (() => {
          // `tall` extends the line past the bars and floats the dot above
          const T = ({ md: { lt: -4, lb: -4, dt: -13 }, lg: { lt: -12, lb: -10, dt: -22 }, xl: { lt: -22, lb: -16, dt: -32 } })[tall] || { lt: 8, lb: 8, dt: 0 };
          return (
            <React.Fragment>
              <div style={{ position: 'absolute', left: '50%', top: T.lt, bottom: T.lb, transform: 'translateX(-50%)', width: lineW, borderRadius: 2, background: ACCENT, boxShadow: `0 0 6px ${rgbaAccent(0.55)}` }} />
              {dot !== 'off' && <div style={{ position: 'absolute', left: '50%', top: T.dt, transform: 'translateX(-50%)', width: 12, height: 12, borderRadius: 999, background: ACCENT, boxShadow: `0 2px 6px ${rgbaAccent(0.5)}` }} />}
            </React.Fragment>
          );
        })()}
        {marker === 'needle' && (
          <React.Fragment>
            <div style={{ position: 'absolute', left: '50%', top: 27, bottom: 6, transform: 'translateX(-50%)', width: 2, borderRadius: 2, background: ACCENT, boxShadow: `0 0 6px ${rgbaAccent(0.55)}` }} />
            <div style={{ position: 'absolute', left: '50%', top: 0, transform: 'translateX(-50%)', padding: '3px 9px', borderRadius: 999, background: ACCENT, color: '#fff', fontSize: 12, fontWeight: 680, fontVariantNumeric: 'tabular-nums', letterSpacing: -0.2, boxShadow: `0 2px 7px ${rgbaAccent(0.5)}`, whiteSpace: 'nowrap' }}>{timeLabel}</div>
          </React.Fragment>
        )}
        {marker === 'split' && (
          <React.Fragment>
            <div style={{ position: 'absolute', left: '50%', top: 4, bottom: 13, transform: 'translateX(-50%)', width: 1.5, borderRadius: 2, background: rgbaAccent(0.42) }} />
            <div style={{ position: 'absolute', left: '50%', bottom: 0, transform: 'translateX(-50%)', width: 9, height: 9, borderRadius: 999, background: ACCENT, boxShadow: `0 1px 4px ${rgbaAccent(0.5)}` }} />
          </React.Fragment>
        )}
      </div>
    </div>
  );
}

function GlassBtn({ children, onClick, size = 64, dark = true, style = {} }) {
  return (
    <button onClick={onClick} style={{
      width: size, height: size, borderRadius: 999, border: 'none', cursor: 'pointer',
      position: 'relative', overflow: 'hidden', padding: 0, background: 'transparent',
      display: 'flex', alignItems: 'center', justifyContent: 'center', ...style,
    }}>
      <div style={{
        position: 'absolute', inset: 0, borderRadius: 999,
        backdropFilter: 'blur(14px) saturate(180%)', WebkitBackdropFilter: 'blur(14px) saturate(180%)',
        background: dark ? 'rgba(120,120,128,0.28)' : 'rgba(255,255,255,0.55)',
        boxShadow: 'inset 1.5px 1.5px 1px rgba(255,255,255,0.22), inset -1px -1px 1px rgba(255,255,255,0.08)',
        border: '0.5px solid rgba(255,255,255,0.18)',
      }} />
      <div style={{ position: 'relative', zIndex: 1, display: 'flex' }}>{children}</div>
    </button>
  );
}

const Ico = {
  wand: (c, s = 20) => <svg width={s} height={s} viewBox="0 0 24 24" fill="none"><path d="M5.5 20.5 L15 11" stroke={c} strokeWidth="2.6" strokeLinecap="round" /><path d="M15 11 L18 8" stroke={c} strokeWidth="2.6" strokeLinecap="round" /><path d="M18 3.5 v3.4 M16.3 5.2 h3.4" stroke={c} strokeWidth="1.5" strokeLinecap="round" /><path d="M21.6 10 v2.4 M20.4 11.2 h2.4" stroke={c} strokeWidth="1.3" strokeLinecap="round" /></svg>,
  play: (c = '#fff', s = 26) => <svg width={s} height={s} viewBox="0 0 24 24"><path d="M8 5.5v13l11-6.5-11-6.5z" fill={c} /></svg>,
  pause: (c = '#fff', s = 24) => <svg width={s} height={s} viewBox="0 0 24 24"><rect x="6" y="5" width="4" height="14" rx="1.4" fill={c} /><rect x="14" y="5" width="4" height="14" rx="1.4" fill={c} /></svg>,
  head: (c, s = 17) => <svg width={s} height={s} viewBox="0 0 24 24" fill="none"><path d="M4 13v-1a8 8 0 0116 0v1" stroke={c} strokeWidth="1.8" strokeLinecap="round" /><rect x="2.6" y="12.5" width="4" height="7" rx="2" fill={c} /><rect x="17.4" y="12.5" width="4" height="7" rx="2" fill={c} /></svg>,
  back: (c, s = 20) => <svg width={s} height={s} viewBox="0 0 12 20" fill="none"><path d="M10 2L2 10l8 8" stroke={c} strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round" /></svg>,
  check: (c, s = 20) => <svg width={s} height={s} viewBox="0 0 24 24" fill="none"><path d="M4 12.5l5 5 11-12" stroke={c} strokeWidth="2.6" strokeLinecap="round" strokeLinejoin="round" /></svg>,
  share: (c, s = 22) => <svg width={s} height={s} viewBox="0 0 24 24" fill="none"><path d="M12 3v13" stroke={c} strokeWidth="2" strokeLinecap="round" /><path d="M8 7l4-4 4 4" stroke={c} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" /><path d="M6 11v7a1.5 1.5 0 001.5 1.5h9A1.5 1.5 0 0018 18v-7" stroke={c} strokeWidth="2" strokeLinecap="round" /></svg>,
  trash: (c, s = 22) => <svg width={s} height={s} viewBox="0 0 24 24" fill="none"><path d="M5 7h14M10 7V5.5A1.5 1.5 0 0111.5 4h1A1.5 1.5 0 0114 5.5V7M7 7l1 12.5A1.5 1.5 0 009.5 21h5a1.5 1.5 0 001.5-1.5L17 7" stroke={c} strokeWidth="1.9" strokeLinecap="round" strokeLinejoin="round" /></svg>,
  plug: (c, s = 20) => <svg width={s} height={s} viewBox="0 0 24 24" fill="none"><path d="M9 3v5M15 3v5" stroke={c} strokeWidth="2" strokeLinecap="round" /><path d="M6.5 8h11v3a5.5 5.5 0 01-11 0z" stroke={c} strokeWidth="2" strokeLinejoin="round" /><path d="M12 16.5V21" stroke={c} strokeWidth="2" strokeLinecap="round" /></svg>,
};

// small monitoring pill (headphones + tone name)
function MonitorPill({ label, dark = true }) {
  const c = dark ? 'rgba(255,255,255,0.85)' : 'rgba(0,0,0,0.7)';
  return (
    <div style={{
      display: 'inline-flex', alignItems: 'center', gap: 7, padding: '7px 13px 7px 11px',
      borderRadius: 999, position: 'relative', overflow: 'hidden',
    }}>
      <div style={{
        position: 'absolute', inset: 0, borderRadius: 999,
        backdropFilter: 'blur(12px) saturate(180%)', WebkitBackdropFilter: 'blur(12px) saturate(180%)',
        background: dark ? 'rgba(120,120,128,0.24)' : 'rgba(255,255,255,0.6)',
        border: '0.5px solid rgba(255,255,255,0.18)',
      }} />
      <span style={{ position: 'relative', display: 'flex' }}>{Ico.head(ACCENT)}</span>
      <span style={{ position: 'relative', fontSize: 13.5, fontWeight: 590, color: c, letterSpacing: -0.2 }}>{label}</span>
    </div>
  );
}

// tone name from a single 0..1 amount
function toneName(v) {
  if (v < 0.06) return 'Dry';
  if (v < 0.32) return 'Room';
  if (v < 0.62) return 'Warm';
  if (v < 0.85) return 'Studio';
  return 'Hall';
}

// Photos-style "Enhance" dial: the tick scale scrolls under a fixed center marker.
function EnhanceSlider({ value, onChange, dark = false }) {
  const W = 300;             // visible track width
  const GAP = 14;            // px between ticks
  const N = 41;              // 0..1 in 40 steps
  const STRIP = (N - 1) * GAP;
  const t = TH(dark);
  const trackRef = useRef(null);
  const drag = useRef(null);
  const down = (e) => {
    e.preventDefault();
    const p0 = (e.touches ? e.touches[0] : e).clientX;
    drag.current = { p0, v0: value };
    const move = (ev) => {
      const px = (ev.touches ? ev.touches[0] : ev).clientX;
      const dv = (drag.current.p0 - px) / STRIP; // drag left → value up (scale scrolls left)
      onChange(Math.max(0, Math.min(1, drag.current.v0 + dv)));
    };
    const up = () => { window.removeEventListener('pointermove', move); window.removeEventListener('pointerup', up); };
    window.addEventListener('pointermove', move); window.addEventListener('pointerup', up);
  };
  // strip is centered, then shifted so the tick for `value` sits under the marker
  const offset = W / 2 - value * STRIP;
  return (
    <div style={{ width: W, display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 12 }}>
      <div style={{ display: 'flex', alignItems: 'center', gap: 7 }}>
        {Ico.wand(ACCENT, 18)}
        <span style={{ fontSize: 14, fontWeight: 640, color: dark ? ACCENT : ACCENT_DEEP, letterSpacing: 0.2 }}>Enhance · {toneName(value)}</span>
      </div>
      <div ref={trackRef} onPointerDown={down} style={{
        position: 'relative', width: '100%', height: 40, touchAction: 'none', cursor: 'ew-resize', overflow: 'hidden',
        WebkitMaskImage: 'linear-gradient(90deg, transparent, #000 16%, #000 84%, transparent)',
        maskImage: 'linear-gradient(90deg, transparent, #000 16%, #000 84%, transparent)',
      }}>
        <div style={{ position: 'absolute', top: 10, left: offset, display: 'flex', gap: GAP - 2, alignItems: 'center', willChange: 'left' }}>
          {Array.from({ length: N }).map((_, i) => {
            const major = i % 5 === 0;
            return <div key={i} style={{ flex: 'none', width: 2, height: major ? 20 : 11, borderRadius: 2, background: major ? t.tickMaj : t.tickMin }} />;
          })}
        </div>
        <div style={{ position: 'absolute', left: '50%', top: 5, transform: 'translateX(-50%)', width: 3, height: 30, borderRadius: 2, background: ACCENT, boxShadow: `0 0 6px ${rgbaAccent(0.55)}` }} />
        <div style={{ position: 'absolute', left: '50%', top: 2, transform: 'translateX(-50%)', width: 11, height: 11, borderRadius: 999, background: ACCENT, boxShadow: `0 2px 6px ${rgbaAccent(0.5)}` }} />
      </div>
    </div>
  );
}

// ══════════════════════════════════════════════════════════
// TAKE SCREEN — the single "take" view, driven by `mode`
// ══════════════════════════════════════════════════════════
/**
 * TakeScreen — the app's one "take" view (formerly split into RecordingScreen +
 * PlaybackScreen). A single shared layout — header · title · waveform · timer ·
 * Enhance slider · transport — where only the HEADER and TRANSPORT change per
 * state. The block above the slider (title/waveform/timer) is top-anchored the
 * same way in every state, so the waveform never shifts as the state changes.
 *
 * STATES — pass the starting one as `mode`:
 *   'monitor'    Record-flow entry. Live input, nothing captured yet.
 *                · Header:  Cancel  ·  🎧 Monitoring
 *                · Timer:   greyed 00:00
 *                · Tray:    Enhance + "Dial in the sound…" + ◉ Record button
 *                · Waveform is live; input coaching (quiet/hot) may surface.
 *   'recording'  Actively capturing. Timer counts up. Live metering continues.
 *                · Header:  Cancel  ·  (right side empty / chrome-free)
 *                · Tray:    Play (disabled) + ▪ Stop.
 *   'stopped'    Take just finished, still in the record flow.
 *                · Header:  Cancel  ·  Share  Done
 *                · Tray:    Play + Resume (labelled). Waveform scrubs.
 *   'playback'   The SAME take reopened later from the Demos list — a separate
 *                entry point that never captures.
 *                · Header:  ‹ Demos  ·  Share  Done
 *                · Editable title, scrubbable waveform, single Play button.
 *
 * In-flow path:  monitor → recording → stopped  (Resume → back to recording).
 * `signal` ('good' | 'quiet' | 'hot') drives the live-metering coaching demo.
 * `wired` (default true): monitoring needs wired headphones. When false the
 * header reads a dimmed "Monitoring off" and the hint line explains why —
 * recording itself is unaffected.
 */
function TakeScreen({ mode: modeProp, dark = false, signal = 'good', wired = true, countIn = '', explain = '', monitoring = false, scrub = '', played = 'amber', dim = '', fadeSpan = 9, fadeMin = 0.26, tall = '', dot = 'on', lineW = 3, edge = 12 }) {
  const scrubMarker = (scrub && scrub !== 'false') ? scrub : null; // 'twin' | 'needle' | 'split' — centre-locked playhead treatment
  const isWired = !(wired === false || wired === 'false');
  const isMonitoring = monitoring === true || monitoring === 'true'; // live monitoring is a post-MVP feature; MVP record screen has no monitor state
  const explainMode = (explain && explain !== 'false') ? explain : null;
  const isDark = dark === true || dark === 'true';
  const th = TH(isDark);
  const mode0 = modeProp || 'monitor';
  const [mode, setMode] = useState(mode0);
  const isPlayback = mode === 'playback';
  const isLive = mode === 'monitor' || mode === 'recording' || mode === 'countin'; // live input on screen
  const isRec = mode === 'recording';
  const total = 37; // take length in seconds

  const [enhance, setEnhance] = useState(0.5);
  const [share, setShare] = useState(false);
  const [showExp, setShowExp] = useState(isMonitoring && !!explainMode && !isWired); // monitoring explainer sheet
  const [name, setName] = useState('New Demo 1');
  const nextNum = useRef(1); // auto-incrementing default name for each new take
  const [t, setT] = useState(mode0 === 'recording' ? 23.4 : mode0 === 'monitor' ? 0 : total);
  const [liveBars, setLiveBars] = useState(() => Array.from({ length: 48 }, () => levelSample(signal)));
  const idleBars = useRef(Array.from({ length: 48 }, () => 0.05)).current; // flat resting line shown when NOT recording
  const takeBars = useRef(makeBars(220, 11)).current; // full-detail take; playback/stopped show a rolling window over it (same look as the live record view)
  const [coach, setCoach] = useState('ok'); // 'ok' | 'low' | 'hot'
  const hotRef = useRef(0);
  // shared playhead: `p` 0..1, advanced by `playing` — used by stopped preview & playback
  const [p, setP] = useState(mode0 === 'playback' ? 0.32 : 1);
  const [playing, setPlaying] = useState(false);
  // count-in: 'button' | 'timer' | 'numeral' — three beats before capture starts
  const countStyle = (countIn && countIn !== 'false') ? countIn : null;
  const [count, setCount] = useState(4);
  const countTimer = useRef(null);
  useEffect(() => () => clearInterval(countTimer.current), []);

  // playhead animation (stopped preview + playback)
  useEffect(() => {
    if (!playing) return;
    const id = setInterval(() => setP((x) => (x >= 1 ? (setPlaying(false), 1) : x + 1 / (total * 16.6))), 60);
    return () => clearInterval(id);
  }, [playing]);
  // live metering + input coaching — ONLY while actually recording (idle/flat otherwise, so it never looks like it's capturing)
  useEffect(() => {
    if (mode !== 'recording') return;
    const id = setInterval(() => {
      setT((x) => x + 0.1);
      setLiveBars((b) => {
        const nb = b.slice(1);
        nb.push(levelSample(signal));
        const recent = nb.slice(-18);
        const avg = recent.reduce((a, c) => a + c, 0) / recent.length;
        const peak = Math.max(...nb.slice(-5));
        const now = performance.now();
        if (peak >= 0.9) hotRef.current = now + 900; // hold the warning briefly past the peak
        const c = now < hotRef.current ? 'hot' : (avg < 0.19 && peak < 0.42 ? 'low' : 'ok');
        queueMicrotask(() => setCoach((pc) => (pc === c ? pc : c)));
        return nb;
      });
    }, 95);
    return () => clearInterval(id);
  }, [mode, signal]);
  // reset coaching + live bars to rest whenever we leave the recording state
  useEffect(() => { if (mode !== 'recording') { setCoach('ok'); } }, [mode]);

  // timer reads elapsed time while live, playhead position otherwise
  const disp = isLive ? t : p * total;
  const mm = String(Math.floor(disp / 60)).padStart(2, '0');
  const ss = String(Math.floor(disp % 60)).padStart(2, '0');
  const cs = String(Math.floor((disp * 100) % 100)).padStart(2, '0'); // two decimal places

  const startRec = () => {
    setName('New Demo ' + nextNum.current); nextNum.current += 1; // auto-name each new recording
    if (countStyle) {
      setMode('countin'); setCount(4);
      countTimer.current = setInterval(() => setCount((c) => {
        if (c <= 1) { clearInterval(countTimer.current); setT(0); setMode('recording'); return 4; }
        return c - 1;
      }), 1000);
    } else { setT(0); setMode('recording'); }
  };
  const doStop = () => { setMode('stopped'); setP(1); setPlaying(false); };
  const doResume = () => { setPlaying(false); setMode('recording'); };
  const doPlay = () => { if (playing) { setPlaying(false); } else { if (p >= 1) setP(0); setPlaying(true); } };
  const doCancel = () => { clearInterval(countTimer.current); setMode('monitor'); setT(0); setLiveBars(Array.from({ length: 48 }, () => levelSample(signal))); setCoach('ok'); setP(1); setPlaying(false); };

  const scrubTap = useDrag((x, _y, r) => setP(Math.max(0, Math.min(1, (x - r.left) / r.width))));
  // centre-locked scrub: relative drag, 1:1 with the waveform (drag left → advance)
  const scrubRel = {
    onPointerDown: (e) => {
      e.preventDefault();
      const p0 = (e.touches ? e.touches[0] : e).clientX;
      const start = p;
      const range = (takeBars.length - 1) * 8; // total strip width (BAR_W+GAP = 8)
      const move = (ev) => {
        const px = (ev.touches ? ev.touches[0] : ev).clientX;
        setP(Math.max(0, Math.min(1, start + (p0 - px) / range)));
      };
      const up = () => { window.removeEventListener('pointermove', move); window.removeEventListener('pointerup', up); };
      window.addEventListener('pointermove', move); window.addEventListener('pointerup', up);
    },
  };
  const scrubTimeLabel = (() => { const s = Math.round(p * total); return `${Math.floor(s / 60)}:${String(s % 60).padStart(2, '0')}`; })();

  const playIco = (s) => playing ? Ico.pause(isDark ? ACCENT : ACCENT_DEEP, s) : Ico.play(isDark ? ACCENT : ACCENT_DEEP, s);
  const labeled = (btn, label) => <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 8 }}>{btn}<span style={{ fontSize: 13, color: th.text2, fontWeight: 500 }}>{label}</span></div>;
  const playBtn = (size, disabled) => <button onClick={doPlay} disabled={disabled} style={{ width: size, height: size, borderRadius: 999, border: 'none', cursor: disabled ? 'default' : 'pointer', background: rgbaAccent(isDark ? 0.2 : 0.14), display: 'flex', alignItems: 'center', justifyContent: 'center', opacity: disabled ? 0.35 : 1, transition: 'opacity .2s' }}>{playIco(Math.round(size * 0.42))}</button>;
  const resumeBtn = (size, disabled) => <button onClick={doResume} disabled={disabled} style={{ width: size, height: size, borderRadius: 999, border: `4px solid ${th.recBorder}`, boxSizing: 'border-box', padding: 0, cursor: disabled ? 'default' : 'pointer', background: 'transparent', display: 'flex', alignItems: 'center', justifyContent: 'center', opacity: disabled ? 0.35 : 1, transition: 'opacity .2s' }}><div style={{ width: size * 0.4, height: size * 0.4, borderRadius: 999, background: ACCENT }} /></button>;
  const stopBtn = (size) => <button onClick={doStop} style={{ width: size, height: size, borderRadius: 999, border: `4px solid ${th.recBorder}`, boxSizing: 'border-box', padding: 0, cursor: 'pointer', background: 'transparent', display: 'flex', alignItems: 'center', justifyContent: 'center' }}><div style={{ width: size * 0.4, height: size * 0.4, borderRadius: 9, background: ACCENT }} /></button>;

  const coachMap = {
    low: { c: th.text2, txt: 'Move a little closer', ico: (
      <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke={th.text2} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M4 6l5 6-5 6" /><path d="M20 6l-5 6 5 6" /></svg>
    ) },
    hot: { c: '#ff453a', txt: 'A little hot — ease back', ico: (
      <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="#ff453a" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M12 4l9 15H3z" /><path d="M12 10v3.4" /><circle cx="12" cy="16.8" r="0.6" fill="#ff453a" /></svg>
    ) },
  };
  const coachInfo = (mode === 'recording' && coach !== 'ok') ? coachMap[coach] : null;

  const recordBtn = (size) => <button onClick={startRec} style={{ width: size, height: size, borderRadius: 999, border: `4px solid ${th.recBorder}`, boxSizing: 'border-box', padding: 0, background: 'transparent', cursor: 'pointer', display: 'flex', alignItems: 'center', justifyContent: 'center' }}><div style={{ width: size * 0.78, height: size * 0.78, borderRadius: 999, background: ACCENT }} /></button>;
  const countBtn = (size) => <button onClick={doCancel} style={{ width: size, height: size, borderRadius: 999, border: `4px solid ${th.recBorder}`, boxSizing: 'border-box', padding: 0, background: 'transparent', cursor: 'pointer', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>{countStyle === 'button' ? <span key={count} style={{ fontSize: 28, fontWeight: 560, color: ACCENT, fontVariantNumeric: 'tabular-nums', display: 'inline-block', animation: 'ciFade 1s ease' }}>{count}</span> : <div style={{ width: 24, height: 24, borderRadius: 7, background: ACCENT, opacity: 0.55 }} />}</button>;

  // Record flow keeps a fixed two-button layout across every state (Play left, main action right)
  // so the UI never jumps between one and two buttons. Play stays disabled until a take exists.
  const canPlay = mode === 'stopped' || isPlayback;
  let mainBtn, mainLabel;
  if (mode === 'recording') { mainBtn = stopBtn(66); mainLabel = 'Stop'; }
  else if (mode === 'countin') { mainBtn = countBtn(66); mainLabel = 'Record'; }
  else if (mode === 'stopped' || isPlayback) { mainBtn = resumeBtn(66, playing); mainLabel = 'Resume'; }
  else { mainBtn = recordBtn(66); mainLabel = 'Record'; } // monitor / ready
  const flowTransport = (
    <div style={{ display: 'flex', gap: 44 }}>
      {labeled(playBtn(66, !canPlay), playing ? 'Pause' : 'Play')}
      {labeled(mainBtn, mainLabel)}
    </div>
  );

  // ── HEADER: left is Cancel (record flow) or ‹ Demos (playback) ─────
  const header = (
    <div style={{ padding: '56px 20px 0' }}>
      <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', height: 26 }}>
        {isPlayback ? (
          <div style={{ display: 'flex', alignItems: 'center', gap: 3, color: ACCENT, fontSize: 17, fontWeight: 500 }}>{Ico.back(ACCENT, 18)}<span>Demos</span></div>
        ) : (
          <button onClick={doCancel} style={{ border: 'none', background: 'transparent', color: ACCENT, fontSize: 17, fontWeight: 500, cursor: 'pointer', padding: 0 }}>Cancel</button>
        )}
        {(mode === 'monitor' || mode === 'countin') ? (
          isMonitoring ? (
            (explainMode && !isWired) ? (
              <button onClick={() => setShowExp(true)} style={{ display: 'flex', alignItems: 'center', gap: 6, border: 'none', background: 'transparent', padding: 0, cursor: 'pointer' }}>
                {Ico.head(th.text3, 16)}<span style={{ fontSize: 14, fontWeight: 590, color: th.text3 }}>Monitoring off</span>
                <svg width="15" height="15" viewBox="0 0 24 24" fill="none" style={{ marginLeft: -1 }}><circle cx="12" cy="12" r="9" stroke={th.text3} strokeWidth="1.8" /><path d="M12 11v5.4" stroke={th.text3} strokeWidth="2" strokeLinecap="round" /><circle cx="12" cy="7.6" r="1.15" fill={th.text3} /></svg>
              </button>
            ) : (
              <div style={{ display: 'flex', alignItems: 'center', gap: 6 }}>{Ico.head(isWired ? ACCENT : th.text3, 16)}<span style={{ fontSize: 14, fontWeight: 590, color: isWired ? th.text2 : th.text3 }}>{isWired ? 'Monitoring' : 'Monitoring off'}</span></div>
            )
          ) : <span />
        ) : mode === 'recording' ? <span /> : (
          <div style={{ display: 'flex', alignItems: 'center', gap: 18 }}>
            <button onClick={() => setShare(true)} style={{ border: 'none', background: 'transparent', cursor: 'pointer', padding: 0, display: 'flex' }}>{Ico.share(ACCENT, 22)}</button>
            <span style={{ color: ACCENT, fontSize: 17, fontWeight: 590, cursor: 'pointer' }}>Done</span>
          </div>
        )}
      </div>
    </div>
  );

  // ── WAVEFORM: live rolling while capturing; playback/stopped show a rolling window that scrolls with the playhead ──
  const WIN = 48;
  const winStart = Math.max(0, Math.min(takeBars.length - WIN, Math.round(p * (takeBars.length - WIN))));
  const playWindow = takeBars.slice(winStart, winStart + WIN);
  const liveWaveEl = isRec
    ? <Waveform bars={liveBars} progress={1} warmth={enhance} space={enhance * 0.7} height={120} dark={isDark} clip />
    : <Waveform bars={idleBars} progress={0} warmth={0} space={0} height={120} dark={isDark} />; // monitor / count-in: flat rest, no reaction
  const playWaveEl = <Waveform bars={playWindow} progress={1} warmth={enhance} space={enhance * 0.7} height={120} dark={isDark} />;
  const scrubEl = <ScrubWaveform bars={takeBars} p={p} warmth={enhance} height={120} dark={isDark} marker={scrubMarker} timeLabel={scrubTimeLabel} played={played} dim={dim} fadeSpan={Number(fadeSpan)} fadeMin={Number(fadeMin)} tall={tall} dot={dot} lineW={Number(lineW)} edge={Number(edge)} />;

  // ── TRANSPORT: record and playback are one view — the same two-button layout in every state ──
  const transport = flowTransport;

  return (
    <IOSDevice dark={isDark}>
      <div style={{ height: '100%', position: 'relative', display: 'flex', flexDirection: 'column', background: th.pageBg, fontFamily: '-apple-system, system-ui' }}>
        {header}
        <div style={{ flex: 1, display: 'flex', flexDirection: 'column', justifyContent: 'flex-start', alignItems: 'center', padding: '90px 24px 0' }}>
          {isPlayback ? (
            <input value={name} onChange={(e) => setName(e.target.value)} style={{ border: 'none', outline: 'none', background: 'transparent', textAlign: 'center', width: '100%', fontSize: 24, fontWeight: 680, color: th.text, letterSpacing: -0.4, lineHeight: 1.25, padding: 0, margin: 0 }} />
          ) : (
            <div style={{ fontSize: 24, fontWeight: 680, color: th.text, letterSpacing: -0.4, lineHeight: 1.25 }}>{name}</div>
          )}
          <div style={{ fontSize: 14, color: th.text2, marginTop: 2, marginBottom: 30 }}>Today · 3:14 PM</div>
          {isLive ? liveWaveEl : (scrubMarker
            ? <div {...scrubRel} style={{ width: '100%', touchAction: 'none', cursor: 'ew-resize' }}>{scrubEl}</div>
            : <div {...scrubTap} style={{ width: '100%', touchAction: 'none', cursor: 'pointer' }}>{playWaveEl}</div>)}
          <div style={{ marginTop: 30, fontVariantNumeric: 'tabular-nums', fontWeight: 300, fontSize: 56, letterSpacing: -1, color: (mode === 'monitor' || mode === 'countin') ? th.text4 : th.text }}>
            {mode === 'countin' && countStyle === 'timer' ? (
              <span key={count} style={{ color: isDark ? ACCENT : ACCENT_DEEP, display: 'inline-block', animation: 'ciFade 1s ease' }}>{count}</span>
            ) : (
              <React.Fragment>{mm}:{ss}<span style={{ color: th.text3 }}>.{cs}</span></React.Fragment>
            )}
          </div>
          {/* input-coaching line — record flow only (playback has no live meter) */}
          {!isPlayback && (
            <div style={{ height: 24, marginTop: 14, display: 'flex', alignItems: 'center', gap: 7, fontSize: 14, fontWeight: 570, letterSpacing: -0.2, opacity: coachInfo ? 1 : 0, transition: 'opacity .25s ease', color: coachInfo ? coachInfo.c : 'transparent' }}>
              {coachInfo && coachInfo.ico}
              <span>{coachInfo ? coachInfo.txt : ''}</span>
            </div>
          )}
        </div>
        {/* transport tray */}
        <div style={{ padding: '0 0 42px', display: 'flex', flexDirection: 'column', alignItems: 'center', gap: isPlayback ? 26 : 20 }}>
          <EnhanceSlider value={enhance} onChange={setEnhance} dark={isDark} />
          {isMonitoring && mode === 'monitor' && <div style={{ fontSize: 13, color: th.text3 }}>{isWired ? 'Dial in the sound, then record' : 'Plug in wired headphones to hear yourself'}</div>}
          {transport}
        </div>
        {countStyle && <style>{`@keyframes ciFade{0%{opacity:0;transform:scale(1.25)}22%{opacity:1;transform:scale(1)}100%{opacity:1;transform:scale(1)}}@keyframes ciNum{0%{opacity:0;transform:scale(1.35)}18%{opacity:1;transform:scale(1)}80%{opacity:1}100%{opacity:.85;transform:scale(.97)}}`}</style>}
        {mode === 'countin' && countStyle === 'numeral' && (
          <div style={{ position: 'absolute', inset: 0, zIndex: 60, display: 'flex', alignItems: 'center', justifyContent: 'center', pointerEvents: 'none', background: isDark ? 'rgba(0,0,0,0.4)' : 'rgba(249,249,251,0.6)', backdropFilter: 'blur(4px)', WebkitBackdropFilter: 'blur(4px)' }}>
            <span key={count} style={{ fontSize: 132, fontWeight: 200, letterSpacing: -4, color: isDark ? '#fff' : '#1c1c1e', fontVariantNumeric: 'tabular-nums', display: 'inline-block', animation: 'ciNum 1s cubic-bezier(.2,.7,.3,1)' }}>{count}</span>
          </div>
        )}
        {showExp && <MonitorSheet dark={isDark} onClose={() => setShowExp(false)} />}
        {share && <ShareSheet demo={{ name, dur: '0:37' }} onClose={() => setShare(false)} dark={isDark} />}
      </div>
    </IOSDevice>
  );
}


// ══════════════════════════════════════════════════════════
// iOS share sheet (UIActivityViewController-style)
// ══════════════════════════════════════════════════════════
// iOS confirmation action sheet (destructive)
function ConfirmSheet({ demo, onConfirm, onCancel, dark = false }) {
  const [up, setUp] = useState(false);
  useEffect(() => { const r = requestAnimationFrame(() => setUp(true)); return () => cancelAnimationFrame(r); }, []);
  const close = (cb) => { setUp(false); setTimeout(cb, 240); };
  if (!demo) return null;
  const glass = dark ? 'rgba(44,44,46,0.9)' : 'rgba(250,250,252,0.9)';
  const txt2 = dark ? 'rgba(235,235,245,0.5)' : 'rgba(60,60,67,0.5)';
  const cancelBg = dark ? 'rgba(58,58,60,0.94)' : 'rgba(255,255,255,0.96)';
  const cancelTxt = dark ? '#fff' : '#1c1c1e';
  return (
    <div style={{ position: 'absolute', inset: 0, zIndex: 110, display: 'flex', flexDirection: 'column', justifyContent: 'flex-end', fontFamily: '-apple-system, system-ui' }}>
      <div onClick={() => close(onCancel)} style={{ position: 'absolute', inset: 0, background: `rgba(0,0,0,${up ? (dark ? 0.5 : 0.28) : 0})`, transition: 'background .24s' }} />
      <div style={{ position: 'relative', padding: '0 8px 10px', transform: up ? 'translateY(0)' : 'translateY(115%)', transition: 'transform .32s cubic-bezier(.32,.72,0,1)' }}>
        <div style={{ borderRadius: 14, overflow: 'hidden', background: glass, backdropFilter: 'blur(34px) saturate(180%)', WebkitBackdropFilter: 'blur(34px) saturate(180%)', marginBottom: 8 }}>
          <div style={{ padding: '15px 16px 13px', textAlign: 'center', fontSize: 13, color: txt2, lineHeight: 1.35, borderBottom: `0.5px solid ${dark ? 'rgba(255,255,255,0.12)' : 'rgba(60,60,67,0.12)'}` }}>Delete “{demo.name}”? This can’t be undone.</div>
          <button onClick={() => close(onConfirm)} style={{ width: '100%', border: 'none', background: 'transparent', cursor: 'pointer', padding: '15px 0', fontSize: 19, fontWeight: 590, color: '#ff3b30' }}>Delete Recording</button>
        </div>
        <button onClick={() => close(onCancel)} style={{ width: '100%', border: 'none', borderRadius: 14, cursor: 'pointer', padding: '16px 0', fontSize: 19, fontWeight: 680, color: ACCENT, background: cancelBg, backdropFilter: 'blur(34px) saturate(180%)', WebkitBackdropFilter: 'blur(34px) saturate(180%)' }}>Cancel</button>
      </div>
    </div>
  );
}

// share-sheet app icon tile (AirDrop / Messages / Mail / …)
function AppTile({ bg, label, children, dark = false }) {
  return (
    <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 7, width: 66, flexShrink: 0 }}>
      <div style={{ width: 60, height: 60, borderRadius: 15, background: bg, display: 'flex', alignItems: 'center', justifyContent: 'center', boxShadow: '0 1px 3px rgba(0,0,0,0.12)' }}>{children}</div>
      <span style={{ fontSize: 11.5, color: dark ? 'rgba(235,235,245,0.75)' : 'rgba(60,60,67,0.75)', textAlign: 'center', lineHeight: 1.15 }}>{label}</span>
    </div>
  );
}
const G = {
  airdrop: <svg width="30" height="30" viewBox="0 0 24 24" fill="none"><path d="M7 13a7 7 0 0110 0" stroke="#fff" strokeWidth="1.8" strokeLinecap="round" /><path d="M9.5 16a3.5 3.5 0 015 0" stroke="#fff" strokeWidth="1.8" strokeLinecap="round" /><circle cx="12" cy="19.5" r="1.4" fill="#fff" /></svg>,
  bubble: <svg width="30" height="30" viewBox="0 0 24 24" fill="none"><path d="M4 11c0-3.3 3.1-6 8-6s8 2.7 8 6-3.1 6-8 6c-.9 0-1.8-.1-2.6-.3L5 18.5l1-3A5.4 5.4 0 014 11z" fill="#fff" /></svg>,
  mail: <svg width="30" height="30" viewBox="0 0 24 24" fill="none"><rect x="3.5" y="6" width="17" height="12" rx="2.5" stroke="#fff" strokeWidth="1.6" /><path d="M5 8l7 5 7-5" stroke="#fff" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round" /></svg>,
  notes: <svg width="30" height="30" viewBox="0 0 24 24" fill="none"><path d="M7 6h10M7 10h10M7 14h6" stroke="#fff" strokeWidth="1.9" strokeLinecap="round" /></svg>,
  copy: <svg width="28" height="28" viewBox="0 0 24 24" fill="none"><rect x="8" y="8" width="11" height="11" rx="2.5" stroke="#fff" strokeWidth="1.8" /><path d="M5.5 15.5A2 2 0 014 13.5v-7A2.5 2.5 0 016.5 4h7a2 2 0 012 1.5" stroke="#fff" strokeWidth="1.8" strokeLinecap="round" /></svg>,
  link: (c) => <svg width="21" height="21" viewBox="0 0 24 24" fill="none"><path d="M10 14a3.5 3.5 0 005 0l3-3a3.5 3.5 0 00-5-5l-1 1" stroke={c} strokeWidth="1.8" strokeLinecap="round" /><path d="M14 10a3.5 3.5 0 00-5 0l-3 3a3.5 3.5 0 005 5l1-1" stroke={c} strokeWidth="1.8" strokeLinecap="round" /></svg>,
  folder: (c) => <svg width="21" height="21" viewBox="0 0 24 24" fill="none"><path d="M3.5 8.5A2 2 0 015.5 6.5h3l2 2h8A2 2 0 0120.5 10.5v6a2 2 0 01-2 2h-13a2 2 0 01-2-2z" stroke={c} strokeWidth="1.8" strokeLinejoin="round" /></svg>,
  wave: (c) => <svg width="21" height="21" viewBox="0 0 24 24" fill="none"><path d="M5 12v0M9 8v8M13 5v14M17 9v6M21 12v0" stroke={c} strokeWidth="2" strokeLinecap="round" /></svg>,
};
function ShareSheet({ demo, onClose, dark = false }) {
  const [up, setUp] = useState(false);
  useEffect(() => { const r = requestAnimationFrame(() => setUp(true)); return () => cancelAnimationFrame(r); }, []);
  const close = () => { setUp(false); setTimeout(onClose, 260); };
  if (!demo) return null;
  const actions = [['Copy Link', G.link], ['Save to Files', G.folder], ['Export Audio…', G.wave]];
  const sheetBg = dark ? 'rgba(44,44,46,0.82)' : 'rgba(244,244,247,0.82)';
  const grab = dark ? 'rgba(235,235,245,0.3)' : 'rgba(60,60,67,0.22)';
  const txt = dark ? '#fff' : '#1c1c1e';
  const txt2 = dark ? 'rgba(235,235,245,0.5)' : 'rgba(60,60,67,0.5)';
  const rowCard = dark ? 'rgba(118,118,128,0.24)' : '#fff';
  const rowDiv = dark ? 'rgba(255,255,255,0.1)' : 'rgba(60,60,67,0.1)';
  const glyphC = dark ? '#fff' : '#1c1c1e';
  return (
    <div style={{ position: 'absolute', inset: 0, zIndex: 100, display: 'flex', flexDirection: 'column', justifyContent: 'flex-end', fontFamily: '-apple-system, system-ui' }}>
      <div onClick={close} style={{ position: 'absolute', inset: 0, background: `rgba(0,0,0,${up ? (dark ? 0.5 : 0.28) : 0})`, transition: 'background .26s' }} />
      <div style={{ position: 'relative', margin: 8, borderRadius: 40, overflow: 'hidden', transform: up ? 'translateY(0)' : 'translateY(115%)', transition: 'transform .34s cubic-bezier(.32,.72,0,1)' }}>
        <div style={{ position: 'absolute', inset: 0, background: sheetBg, backdropFilter: 'blur(34px) saturate(180%)', WebkitBackdropFilter: 'blur(34px) saturate(180%)' }} />
        <div style={{ position: 'relative', padding: '11px 16px 40px' }}>
          <div style={{ width: 40, height: 5, borderRadius: 3, background: grab, margin: '0 auto 16px' }} />
          <div style={{ display: 'flex', alignItems: 'center', gap: 12, padding: '0 2px 16px' }}>
            <div style={{ width: 46, height: 46, borderRadius: 11, background: rgbaAccent(0.16), display: 'flex', alignItems: 'center', justifyContent: 'center' }}>{Ico.wand(dark ? ACCENT : ACCENT_DEEP, 24)}</div>
            <div style={{ flex: 1, minWidth: 0 }}>
              <div style={{ fontSize: 16, fontWeight: 600, color: txt }}>{demo.name}</div>
              <div style={{ fontSize: 13, color: txt2 }}>Audio · {demo.dur || '0:37'}</div>
            </div>
            <button onClick={close} style={{ width: 30, height: 30, borderRadius: 999, border: 'none', background: dark ? 'rgba(235,235,245,0.18)' : 'rgba(120,120,128,0.18)', color: txt2, fontSize: 14, cursor: 'pointer', flexShrink: 0 }}>✕</button>
          </div>
          <div style={{ display: 'flex', gap: 12, overflowX: 'auto', padding: '6px 2px 20px' }}>
            <AppTile bg="linear-gradient(180deg,#3d8bff,#0a6cff)" label="AirDrop" dark={dark}>{G.airdrop}</AppTile>
            <AppTile bg="#34c759" label="Messages" dark={dark}>{G.bubble}</AppTile>
            <AppTile bg="linear-gradient(180deg,#3d9bff,#0a84ff)" label="Mail" dark={dark}>{G.mail}</AppTile>
            <AppTile bg="#f7c948" label="Notes" dark={dark}>{G.notes}</AppTile>
            <AppTile bg="#8e8e93" label="Copy" dark={dark}>{G.copy}</AppTile>
          </div>
          <div style={{ background: rowCard, borderRadius: 16, overflow: 'hidden' }}>
            {actions.map(([label, glyph], i) => (
              <div key={label} style={{ display: 'flex', alignItems: 'center', minHeight: 52, padding: '0 16px', position: 'relative', cursor: 'pointer' }}>
                <span style={{ flex: 1, fontSize: 17, color: txt }}>{label}</span>
                {glyph(glyphC)}
                {i < actions.length - 1 && <div style={{ position: 'absolute', left: 16, right: 0, bottom: 0, height: 0.5, background: rowDiv }} />}
              </div>
            ))}
          </div>
        </div>
      </div>
    </div>
  );
}

// ══════════════════════════════════════════════════════════
// MONITORING EXPLAINER — tapping the dimmed "Monitoring off" pill
// (no wired headphones) raises a standard iOS medium-detent sheet
// ══════════════════════════════════════════════════════════

// Medium-detent info sheet (UISheetPresentationController): grabber,
// symbol, title, body, a wired-only callout, and one filled OK.
// Dismiss on backdrop or OK.
function MonitorSheet({ dark, onClose }) {
  const [up, setUp] = useState(false);
  useEffect(() => { const r = requestAnimationFrame(() => setUp(true)); return () => cancelAnimationFrame(r); }, []);
  const close = () => { setUp(false); setTimeout(onClose, 300); };
  const sheetBg = dark ? 'rgba(28,28,30,0.99)' : 'rgba(255,255,255,0.99)';
  const grab = dark ? 'rgba(235,235,245,0.3)' : 'rgba(60,60,67,0.22)';
  const txt = dark ? '#fff' : '#1c1c1e';
  const txt2 = dark ? 'rgba(235,235,245,0.6)' : 'rgba(60,60,67,0.6)';
  const noteBg = dark ? 'rgba(118,118,128,0.2)' : 'rgba(120,120,128,0.1)';
  return (
    <div style={{ position: 'absolute', inset: 0, zIndex: 100, display: 'flex', flexDirection: 'column', justifyContent: 'flex-end', fontFamily: '-apple-system, system-ui' }}>
      <div onClick={close} style={{ position: 'absolute', inset: 0, background: `rgba(0,0,0,${up ? (dark ? 0.5 : 0.28) : 0})`, transition: 'background .3s' }} />
      <div style={{ position: 'relative', background: sheetBg, borderTopLeftRadius: 16, borderTopRightRadius: 16, padding: '11px 24px 40px', transform: up ? 'translateY(0)' : 'translateY(100%)', transition: 'transform .36s cubic-bezier(.32,.72,0,1)' }}>
        <div style={{ width: 40, height: 5, borderRadius: 3, background: grab, margin: '0 auto 22px' }} />
        <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', textAlign: 'center' }}>
          <div style={{ width: 62, height: 62, borderRadius: 999, background: rgbaAccent(0.14), display: 'flex', alignItems: 'center', justifyContent: 'center', marginBottom: 18 }}>{Ico.head(dark ? ACCENT : ACCENT_DEEP, 30)}</div>
          <div style={{ fontSize: 20, fontWeight: 700, color: txt, letterSpacing: -0.4, whiteSpace: 'nowrap' }}>Live Monitoring</div>
          <div style={{ fontSize: 14.5, lineHeight: 1.5, color: txt2, marginTop: 9, maxWidth: 292, textWrap: 'pretty' }}>Monitoring plays the mic back in your headphones, so you hear exactly how a take sounds while you record it.</div>
          <div style={{ display: 'flex', alignItems: 'center', gap: 11, marginTop: 20, padding: '12px 15px', borderRadius: 12, background: noteBg, width: '100%', boxSizing: 'border-box' }}>
            <span style={{ flexShrink: 0, display: 'flex' }}>{Ico.plug(dark ? ACCENT : ACCENT_DEEP, 20)}</span>
            <span style={{ fontSize: 13.5, lineHeight: 1.4, color: txt, textAlign: 'left', fontWeight: 500 }}>Works with wired headphones only — Bluetooth adds too much delay to hear yourself in time.</span>
          </div>
        </div>
        <button onClick={close} style={{ width: '100%', marginTop: 26, padding: '15px 0', borderRadius: 14, border: 'none', cursor: 'pointer', background: ACCENT, color: '#fff', fontSize: 17, fontWeight: 640, boxShadow: `0 6px 18px ${rgbaAccent(0.34)}` }}>OK</button>
      </div>
    </div>
  );
}

// swipe-left row → Share / Delete (iOS list convention)
function SwipeRow({ children, onShare, onDelete, dark = false }) {
  const [x, setX] = useState(0);
  const down = (e) => {
    const sx = (e.touches ? e.touches[0] : e).clientX, b = x;
    const move = (ev) => { const cx = (ev.touches ? ev.touches[0] : ev).clientX; setX(Math.max(-152, Math.min(0, b + (cx - sx)))); };
    const up = (ev) => { const cx = (ev.touches ? ev.touches[0] : ev).clientX; setX(b + (cx - sx) < -64 ? -152 : 0); window.removeEventListener('pointermove', move); window.removeEventListener('pointerup', up); };
    window.addEventListener('pointermove', move); window.addEventListener('pointerup', up);
  };
  const actBtn = (bg, glyph, label, cb) => (
    <button onClick={cb} style={{ width: 76, border: 'none', background: bg, color: '#fff', cursor: 'pointer', display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', gap: 3, fontSize: 12, fontWeight: 500 }}>
      {glyph}{label}
    </button>
  );
  return (
    <div style={{ position: 'relative', overflow: 'hidden' }}>
      <div style={{ position: 'absolute', top: 0, right: 0, bottom: 0, display: 'flex' }}>
        {actBtn('#0a84ff', Ico.share('#fff', 19), 'Share', () => { setX(0); onShare(); })}
        {actBtn('#ff3b30', Ico.trash('#fff', 19), 'Delete', () => { setX(0); onDelete && onDelete(); })}
      </div>
      <div onPointerDown={down} style={{ position: 'relative', transform: `translateX(${x}px)`, transition: 'transform .2s', background: dark ? '#2c2c2e' : '#fff', touchAction: 'pan-y' }}>{children}</div>
    </div>
  );
}

// ══════════════════════════════════════════════════════════
// DEMOS — home list (light)
// ══════════════════════════════════════════════════════════
function DemosListScreen({ empty = false, dark = false, emptyStyle = 'symbol' } = {}) {
  const isEmpty = empty === true || empty === 'true';
  const isDark = dark === true || dark === 'true';
  const eStyle = emptyStyle || 'symbol';
  const t = TH(isDark);
  const [demos, setDemos] = useState([
    { name: 'New Demo 3', meta: 'Today · 3:14 PM', dur: '0:37', enhanced: true },
    { name: 'Chorus — fast', meta: 'Today · 11:02 AM', dur: '0:21', enhanced: true },
    { name: 'Bridge hum', meta: 'Yesterday', dur: '1:12', enhanced: false },
    { name: 'Verse idea 2', meta: 'Monday', dur: '0:48', enhanced: false },
    { name: 'Riff in D', meta: 'Sunday', dur: '0:15', enhanced: true },
  ]);
  const [share, setShare] = useState(null);
  const [confirm, setConfirm] = useState(null);
  return (
    <IOSDevice dark={isDark}>
      <div style={{ height: '100%', position: 'relative', display: 'flex', flexDirection: 'column', background: t.pageBg, fontFamily: '-apple-system, system-ui' }}>
        <div style={{ padding: '64px 20px 12px' }}>
          <div style={{ fontSize: 34, fontWeight: 700, color: t.text, letterSpacing: 0.3 }}>Demos</div>
        </div>
        <div style={{ flex: 1, overflow: 'auto', padding: '4px 16px 120px', display: isEmpty ? 'flex' : 'block', flexDirection: 'column', justifyContent: 'center', alignItems: 'center' }}>
          {isEmpty ? (
            eStyle === 'illustrated' ? (
              <div style={{ textAlign: 'center', maxWidth: 268, marginTop: -26, display: 'flex', flexDirection: 'column', alignItems: 'center' }}>
                <div style={{ display: 'flex', alignItems: 'center', gap: 5, height: 64, marginBottom: 28 }}>
                  {[0.26, 0.48, 0.7, 0.42, 0.9, 0.6, 1, 0.6, 0.9, 0.42, 0.7, 0.48, 0.26].map((h, i) => (
                    <div key={i} style={{ width: 5, height: `${h * 100}%`, borderRadius: 999, background: `linear-gradient(180deg, ${ACCENT}, ${ACCENT_DEEP})`, opacity: 0.35 + h * 0.55 }} />
                  ))}
                </div>
                <div style={{ fontSize: 22, fontWeight: 700, color: t.text, letterSpacing: -0.4, marginBottom: 8 }}>Your demos live here</div>
                <div style={{ fontSize: 15, lineHeight: 1.5, color: t.text2, textWrap: 'balance' }}>Record an idea the moment it strikes — Enhance makes it sound studio-ready.</div>
              </div>
            ) : eStyle === 'rows' ? (
              <div style={{ width: '100%', maxWidth: 300, marginTop: -14 }}>
                <div style={{ fontSize: 22, fontWeight: 700, color: t.text, letterSpacing: -0.4, textAlign: 'center', marginBottom: 26 }}>Welcome to Demo Memos</div>
                <div style={{ display: 'flex', flexDirection: 'column', gap: 22 }}>
                  {[
                    { g: <svg width="19" height="19" viewBox="0 0 24 24"><circle cx="12" cy="12" r="7" fill={ACCENT_DEEP} /></svg>, h: 'Record in a tap', s: 'Catch the idea before it’s gone.' },
                    { g: Ico.wand(ACCENT_DEEP, 20), h: 'One Enhance dial', s: 'Warm it up until it sounds right.' },
                    { g: Ico.share(ACCENT_DEEP, 20), h: 'Share anywhere', s: 'Send a demo straight from the app.' },
                  ].map((r, i) => (
                    <div key={i} style={{ display: 'flex', alignItems: 'center', gap: 16 }}>
                      <div style={{ flex: 'none', width: 42, height: 42, borderRadius: 12, display: 'flex', alignItems: 'center', justifyContent: 'center', background: isDark ? 'rgba(255,159,10,0.18)' : 'rgba(255,159,10,0.13)' }}>{r.g}</div>
                      <div style={{ textAlign: 'left' }}>
                        <div style={{ fontSize: 16, fontWeight: 600, color: t.text, letterSpacing: -0.2 }}>{r.h}</div>
                        <div style={{ fontSize: 13.5, color: t.text2, marginTop: 1 }}>{r.s}</div>
                      </div>
                    </div>
                  ))}
                </div>
              </div>
            ) : (
              <div style={{ textAlign: 'center', maxWidth: 252, marginTop: -20, display: 'flex', flexDirection: 'column', alignItems: 'center' }}>
                <div style={{ fontSize: 22, fontWeight: 700, color: t.text, letterSpacing: -0.4, marginBottom: 8 }}>Capture your first demo</div>
                <div style={{ fontSize: 15, lineHeight: 1.5, color: t.text2, textWrap: 'balance' }}>Hit ‘New Demo’ to record an idea, shape it with Enhance, and share it anywhere.</div>
              </div>
            )
          ) : (
            <React.Fragment>
              <div style={{ width: '100%', background: isDark ? '#2c2c2e' : t.card, borderRadius: 22, overflow: 'hidden', boxShadow: isDark ? 'none' : '0 1px 3px rgba(0,0,0,0.04)' }}>
            {demos.map((m, i) => (
              <SwipeRow key={m.name} onShare={() => setShare(m)} onDelete={() => setConfirm(m)} dark={isDark}>
                <div style={{ display: 'flex', alignItems: 'center', minHeight: 66, padding: '0 16px', position: 'relative', background: 'transparent' }}>
                  <div style={{ flex: 1 }}>
                    <div style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
                      <span style={{ fontSize: 17, fontWeight: 590, color: t.text, letterSpacing: -0.3 }}>{m.name}</span>
                    </div>
                    <div style={{ fontSize: 14, color: t.text2, marginTop: 2 }}>{m.meta}</div>
                  </div>
                  <span style={{ fontSize: 15, color: t.text3, fontVariantNumeric: 'tabular-nums' }}>{m.dur}</span>
                  {i < demos.length - 1 && <div style={{ position: 'absolute', left: 16, right: 0, bottom: 0, height: 0.5, background: t.divider }} />}
                </div>
              </SwipeRow>
            ))}
          </div>
          <div style={{ fontSize: 12.5, color: t.text3, textAlign: 'center', padding: '14px 0' }}>Swipe a demo to share</div>
            </React.Fragment>
          )}
        </div>
        {/* floating liquid-glass New Demo capsule — content scrolls beneath it */}
        <div style={{ position: 'absolute', left: 0, right: 0, bottom: 0, padding: '16px 0 40px', display: 'flex', justifyContent: 'center', pointerEvents: 'none', background: `linear-gradient(to top, ${isDark ? 'rgba(0,0,0,0.35)' : 'rgba(242,242,247,0.55)'} 30%, transparent)` }}>
          <button style={{ pointerEvents: 'auto', display: 'flex', alignItems: 'center', gap: 9, padding: '13px 24px', borderRadius: 999, cursor: 'pointer', background: rgbaAccent(0.9), backdropFilter: 'blur(24px) saturate(1.6)', WebkitBackdropFilter: 'blur(24px) saturate(1.6)', border: '0.5px solid rgba(255,255,255,0.4)', boxShadow: `0 8px 24px ${rgbaAccent(0.35)}, inset 0 1px 0 rgba(255,255,255,0.35)` }}>
            <svg width="18" height="18" viewBox="0 0 24 24" fill="none"><rect x="9" y="3" width="6" height="11" rx="3" fill="#fff" /><path d="M6 11a6 6 0 0012 0" stroke="#fff" strokeWidth="2" strokeLinecap="round" /><path d="M12 17v3.5" stroke="#fff" strokeWidth="2" strokeLinecap="round" /></svg>
            <span style={{ fontSize: 16, fontWeight: 640, color: '#fff', letterSpacing: -0.2 }}>New Demo</span>
          </button>
        </div>
        {share && <ShareSheet demo={share} onClose={() => setShare(null)} dark={isDark} />}
        {confirm && <ConfirmSheet demo={confirm} dark={isDark} onCancel={() => setConfirm(null)} onConfirm={() => { setDemos((xs) => xs.filter((y) => y !== confirm)); setConfirm(null); }} />}
      </div>
    </IOSDevice>
  );
}

// ══════════════════════════════════════════════════════════
// ONBOARDING — shown once on first launch
// ══════════════════════════════════════════════════════════

// app icon: rounded-rect, orange, mic glyph
function AppIcon({ size = 84, radius }) {
  const r = radius ?? size * 0.225;
  return (
    <div style={{
      width: size, height: size, borderRadius: r, position: 'relative', overflow: 'hidden',
      background: `linear-gradient(160deg, ${ACCENT} 0%, ${ACCENT_DEEP} 100%)`,
      boxShadow: `0 10px 30px ${rgbaAccent(0.4)}, inset 0 1px 1px rgba(255,255,255,0.4)`,
      display: 'flex', alignItems: 'center', justifyContent: 'center',
    }}>
      <div style={{ position: 'absolute', inset: 0, background: 'linear-gradient(180deg,rgba(255,255,255,0.28),transparent 46%)' }} />
      <svg width={size * 0.52} height={size * 0.52} viewBox="0 0 24 24" fill="none" style={{ position: 'relative' }}>
        <rect x="9" y="2.5" width="6" height="12" rx="3" fill="#fff" />
        <path d="M5.5 11a6.5 6.5 0 0013 0" stroke="#fff" strokeWidth="2.1" strokeLinecap="round" />
        <path d="M12 17.5V21" stroke="#fff" strokeWidth="2.1" strokeLinecap="round" />
      </svg>
    </div>
  );
}

// ── A — "What's New" feature list (iOS system style) ──────
function OnboardFeatures({ dark = false }) {
  const isDark = dark === true || dark === 'true';
  const t = TH(isDark);
  const feats = [
    { ico: (c) => <svg width="26" height="26" viewBox="0 0 24 24" fill="none"><rect x="9" y="2.5" width="6" height="12" rx="3" fill={c} /><path d="M5.5 11a6.5 6.5 0 0013 0" stroke={c} strokeWidth="2.1" strokeLinecap="round" /><path d="M12 17.5V21" stroke={c} strokeWidth="2.1" strokeLinecap="round" /></svg>, title: 'Voice Memos, but for demos', body: 'Open it and go — the same one-tap simplicity you know, made for catching musical ideas.' },
    { ico: (c) => Ico.wand(c, 24), title: 'One Enhance dial', body: 'A single slider warms and widens your whole sound. No menus, no mixing.' },
    { ico: (c) => Ico.share(c, 24), title: 'Share anywhere', body: 'Send takes straight to Messages, Mail or Files with the native share sheet.' },
  ];
  return (
    <IOSDevice dark={isDark}>
      <div style={{ height: '100%', display: 'flex', flexDirection: 'column', background: t.pageBg, fontFamily: '-apple-system, system-ui' }}>
        <div style={{ flex: 1, overflow: 'auto', padding: '56px 34px 28px', display: 'flex', flexDirection: 'column', justifyContent: 'center' }}>
          <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', marginBottom: 44 }}>
            <div style={{ fontSize: 32, fontWeight: 720, color: t.text, letterSpacing: -0.6, textAlign: 'center', lineHeight: 1.12 }}>
              Welcome to<br /><span style={{ color: isDark ? ACCENT : ACCENT_DEEP }}>Demo Memos</span>
            </div>
          </div>
          <div style={{ display: 'flex', flexDirection: 'column', gap: 30 }}>
            {feats.map((f) => (
              <div key={f.title} style={{ display: 'flex', gap: 18, alignItems: 'flex-start' }}>
                <div style={{ width: 34, flexShrink: 0, display: 'flex', justifyContent: 'center', paddingTop: 2 }}>{f.ico(isDark ? ACCENT : ACCENT_DEEP)}</div>
                <div>
                  <div style={{ fontSize: 16.5, fontWeight: 640, color: t.text, letterSpacing: -0.2 }}>{f.title}</div>
                  <div style={{ fontSize: 14.5, lineHeight: 1.42, color: t.text2, marginTop: 3, textWrap: 'pretty' }}>{f.body}</div>
                </div>
              </div>
            ))}
          </div>
        </div>
        <div style={{ padding: '18px 24px 44px' }}>
          <button style={{ width: '100%', padding: '16px 0', borderRadius: 15, border: 'none', cursor: 'pointer', background: ACCENT, color: '#fff', fontSize: 17, fontWeight: 640, letterSpacing: -0.2, boxShadow: `0 6px 18px ${rgbaAccent(0.34)}` }}>Continue</button>
        </div>
      </div>
    </IOSDevice>
  );
}


// ══════════════════════════════════════════════════════════
// WAVEFORM STUDY — lifecycle · playback · Enhance reaction
// One GPU surface on device (SwiftUI Canvas / Metal); here a
// single flex row of bars, animated with rAF-style intervals.
// ══════════════════════════════════════════════════════════
const REDUCED = typeof window !== 'undefined' && window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches;

// per-bar "active" (amber) amount 0..1 for a given phase
function activeAmount(phase, i, N, prog) {
  if (phase === 'playing' || phase === 'scrub' || phase === 'preview') return i / (N - 1) <= prog ? 1 : 0;
  if (phase === 'recording' || phase === 'start') return Math.max(0, 1 - (N - 1 - i) / (N * 0.4)); // live edge on the right
  return 0; // armed · stopped · paused → neutral overview
}

// the reactive bar meter. `space`/`warmth` derive from Enhance.
function BarMeter({ bars, phase, prog = 1, enhance = 0.5, dark = false, height = 96, showHead = false }) {
  const N = bars.length;
  const warmth = enhance;
  const space = enhance * 0.7;
  const neutral = dark ? 'rgba(235,235,245,0.22)' : 'rgba(120,120,128,0.26)';
  return (
    <div style={{ position: 'relative', height, width: '100%' }}>
      {/* ChromaVerb-style bloom: warm radial aura + faint expanding ring, grows with Enhance */}
      <div style={{ position: 'absolute', inset: 0, display: 'flex', alignItems: 'center', justifyContent: 'center', pointerEvents: 'none' }}>
        <div style={{ width: `${58 + space * 66}%`, height: `${118 + space * 90}%`, borderRadius: '50%', background: `radial-gradient(closest-side, ${rgbaAccent(0.09 + space * 0.15)}, transparent 72%)`, filter: `blur(${6 + space * 9}px)`, transition: 'all .2s ease' }} />
      </div>
      <div style={{ position: 'relative', height: '100%', width: '100%', display: 'flex', alignItems: 'center', gap: 3, justifyContent: 'center' }}>
        {bars.map((b, i) => {
          const a = activeAmount(phase, i, N, prog);
          const col = a > 0
            ? warmColor(0.35 + warmth * 0.65, 0.55 + a * 0.45)
            : warmColor(warmth * 0.5, dark ? 0.24 : 0.30); // neutral bars warm ever so slightly with Enhance
          const base = a > 0 ? col : neutral;
          const atHead = showHead && i / (N - 1) <= prog && (i + 1) / (N - 1) > prog;
          return (
            <div key={i} style={{
              flex: 1, minWidth: 0, height: `${Math.max(6, b * 100)}%`, borderRadius: 4,
              background: atHead ? ACCENT : base,
              boxShadow: a > 0 && warmth > 0.3 ? `0 0 ${2 + warmth * a * 8}px ${rgbaAccent(warmth * a * 0.5)}` : 'none',
              transition: 'background .1s, box-shadow .12s',
            }} />
          );
        })}
      </div>
    </div>
  );
}

// self-animating waveform for a single state
function LiveWave({ phase, enhance = 0.5, dark = false, height = 96 }) {
  const N = 46;
  const [bars, setBars] = useState(() => (phase === 'armed' ? Array.from({ length: N }, () => 0.05) : makeBars(N, 7)));
  const [prog, setProg] = useState(phase === 'playing' ? 0.0 : phase === 'scrub' ? 0.46 : phase === 'preview' ? 0.0 : phase === 'stopped' || phase === 'paused' ? 0 : 1);
  useEffect(() => {
    if (REDUCED) return;
    if (phase === 'armed') return; // armed = ready, not capturing → waveform rests flat, no reaction
    if (phase === 'recording' || phase === 'start') {
      const id = setInterval(() => setBars((b) => { const nb = b.slice(1); const env = 0.4 + Math.random() * 0.6; nb.push(0.12 + env * (0.55 + Math.random() * 0.45)); return nb; }), 95);
      return () => clearInterval(id);
    }
    if (phase === 'playing') {
      const id = setInterval(() => setProg((p) => (p >= 1 ? 0 : p + 0.006)), 40);
      return () => clearInterval(id);
    }
  }, [phase]);
  return <BarMeter bars={bars} phase={phase} prog={prog} enhance={enhance} dark={dark} height={height} showHead={phase === 'playing' || phase === 'scrub'} />;
}

// small status chip under a tile (REC dot / play / monitoring)
function StatusChip({ kind, label, dark }) {
  const txt = dark ? 'rgba(235,235,245,0.7)' : 'rgba(60,60,67,0.6)';
  const dot = kind === 'rec' ? '#ff3b30' : kind === 'play' ? ACCENT : null;
  return (
    <div style={{ display: 'flex', alignItems: 'center', gap: 7, fontSize: 12.5, fontWeight: 560, color: txt, letterSpacing: -0.1 }}>
      {kind === 'monitor' ? Ico.head(ACCENT, 14) : dot ? (
        <span style={{ width: 8, height: 8, borderRadius: 999, background: dot, boxShadow: kind === 'rec' ? '0 0 0 0 rgba(255,59,48,0.5)' : 'none', animation: kind === 'rec' && !REDUCED ? 'wsRecPulse 1.6s ease-in-out infinite' : 'none' }} />
      ) : null}
      <span style={{ fontVariantNumeric: 'tabular-nums' }}>{label}</span>
    </div>
  );
}

function WaveformStudy({ dark = false } = {}) {
  const isDark = dark === true || dark === 'true';
  const th = TH(isDark);
  const [enh, setEnh] = useState(0.6);
  const studyBars = useRef(makeBars(80, 9)).current; // long take for the centre-locked scrub tiles
  const [playP, setPlayP] = useState(0.08);
  useEffect(() => {
    if (REDUCED) return;
    const id = setInterval(() => setPlayP((x) => (x >= 0.985 ? 0.08 : x + 0.004)), 40);
    return () => clearInterval(id);
  }, []);
  // shared props for the final centre-locked scrub marker (matches 1c / 2c)
  const SCRUB = { marker: 'twin', dim: 'fade', fadeSpan: 6, fadeMin: 0.45, tall: 'md', dot: 'off', lineW: 4, edge: 0 };
  const panelBg = isDark ? '#1c1c1e' : '#ffffff';
  const tileBg = isDark ? 'rgba(118,118,128,0.14)' : '#f6f6f8';
  const H = (t) => <div style={{ fontSize: 12, fontWeight: 680, letterSpacing: 0.6, textTransform: 'uppercase', color: th.text3, margin: '2px 0 14px' }}>{t}</div>;

  const Tile = ({ phase, title, note, chip, enhance = enh, w, waveOverride }) => (
    <div style={{ flex: w ? 'none' : 1, width: w, background: tileBg, borderRadius: 18, padding: '15px 16px 14px', display: 'flex', flexDirection: 'column' }}>
      <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: 12 }}>
        <span style={{ fontSize: 14.5, fontWeight: 640, color: th.text, letterSpacing: -0.2 }}>{title}</span>
        {chip}
      </div>
      {waveOverride || <LiveWave phase={phase} enhance={enhance} dark={isDark} height={88} />}
      <div style={{ fontSize: 12, lineHeight: 1.45, color: th.text2, marginTop: 12, textWrap: 'pretty' }}>{note}</div>
    </div>
  );

  const steps = [['Dry', 0.02], ['Room', 0.28], ['Warm', 0.52], ['Studio', 0.76], ['Hall', 0.97]];
  const bigBars = useRef(makeBars(56, 3)).current;

  return (
    <div style={{ width: 936, background: panelBg, borderRadius: 30, padding: '32px 34px 36px', boxShadow: isDark ? '0 1px 2px rgba(0,0,0,0.4)' : '0 1px 3px rgba(0,0,0,0.06)', fontFamily: '-apple-system, system-ui', boxSizing: 'border-box' }}>
      <style>{`@keyframes wsRecPulse{0%,100%{box-shadow:0 0 0 0 rgba(255,59,48,.45)}50%{box-shadow:0 0 0 5px rgba(255,59,48,0)}}`}</style>
      <div style={{ fontSize: 21, fontWeight: 720, color: th.text, letterSpacing: -0.4, marginBottom: 4 }}>Recording waveform — states & motion</div>
      <div style={{ fontSize: 13.5, lineHeight: 1.5, color: th.text2, maxWidth: 620, marginBottom: 30, textWrap: 'pretty' }}>Same bar language as the live screens, one GPU surface on device. Enhance reads as a subtle warm bloom that widens with “space” — a quiet nod to ChromaVerb, never a literal reverb tail.</div>

      {H('Recording lifecycle')}
      <div style={{ display: 'flex', gap: 14, marginBottom: 30 }}>
        <Tile phase="armed" title="Armed" chip={<StatusChip kind="ready" label="Ready" dark={isDark} />} note="Ready to record, but nothing is captured yet — so the waveform rests flat. It only reacts to sound once recording starts." enhance={0} />
        <Tile phase="start" title="Start" chip={<StatusChip kind="rec" label="0:00.4" dark={isDark} />} note="Tap record: timer runs, bars begin writing in from the right edge, bloom ignites." enhance={0.55} />
        <Tile phase="recording" title="Recording" chip={<StatusChip kind="rec" label="0:23.4" dark={isDark} />} note="Steady scroll. Live amber edge on the right fades into neutral history to the left." enhance={0.6} />
        <Tile phase="stopped" title="Stopped" chip={<StatusChip kind="play" label="0:37" dark={isDark} />} note="Snaps to the centre-locked review: playhead at the end, the whole take to its left — ready to scrub or resume." waveOverride={<ScrubWaveform bars={studyBars} p={1} warmth={enh} height={88} dark={isDark} {...SCRUB} />} />
      </div>

      {H('Playback · centre-locked playhead')}
      <div style={{ display: 'flex', gap: 14, marginBottom: 30 }}>
        {[
          { title: 'Paused', chip: <StatusChip kind="play" label="0:00" dark={isDark} />, p: 0, note: 'Playhead parked on the centre line; the take waits to its right. Nothing moves.' },
          { title: 'Playing', chip: <StatusChip kind="play" label="0:16 / 0:37" dark={isDark} />, p: playP, note: 'The take scrolls left under the fixed centre marker — played bars (warm) pass to the left, upcoming (neutral) arrive from the right.' },
          { title: 'Scrubbing', chip: <StatusChip kind="play" label="↔ 0:19" dark={isDark} />, p: 0.5, note: 'Drag the wave left/right; the marker holds the centre and time tracks it — the same model as the Enhance dial.' },
        ].map((tl) => (
          <div key={tl.title} style={{ flex: 1, background: tileBg, borderRadius: 18, padding: '15px 16px 14px', display: 'flex', flexDirection: 'column' }}>
            <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: 12 }}>
              <span style={{ fontSize: 14.5, fontWeight: 640, color: th.text, letterSpacing: -0.2 }}>{tl.title}</span>
              {tl.chip}
            </div>
            <ScrubWaveform bars={studyBars} p={tl.p} warmth={enh} height={88} dark={isDark} {...SCRUB} />
            <div style={{ fontSize: 12, lineHeight: 1.45, color: th.text2, marginTop: 12, textWrap: 'pretty' }}>{tl.note}</div>
          </div>
        ))}
      </div>

      {H('Enhance reaction · drag to feel it')}
      <div style={{ background: tileBg, borderRadius: 18, padding: '20px 20px 22px', display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 18 }}>
        <div style={{ width: '100%', maxWidth: 560 }}>
          <BarMeter bars={bigBars} phase="playing" prog={1} enhance={enh} dark={isDark} height={110} />
        </div>
        <EnhanceSlider value={enh} onChange={setEnh} dark={isDark} />
        <div style={{ display: 'flex', gap: 12, width: '100%', marginTop: 4 }}>
          {steps.map(([label, v]) => (
            <div key={label} style={{ flex: 1, display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 8 }}>
              <div style={{ width: '100%' }}><BarMeter bars={makeBars(20, v * 100 + 1)} phase="stopped" enhance={v} dark={isDark} height={44} /></div>
              <span style={{ fontSize: 11.5, fontWeight: 600, color: Math.abs(v - enh) < 0.12 ? (isDark ? ACCENT : ACCENT_DEEP) : th.text3, letterSpacing: 0.1 }}>{label}</span>
            </div>
          ))}
        </div>
      </div>
    </div>
  );
}

// One take view; the record-flow and playback entry points are just it started
// in a different `mode` (monitor / playback / stopped).
Object.assign(window, { TakeScreen, DemosListScreen, OnboardFeatures, WaveformStudy });
