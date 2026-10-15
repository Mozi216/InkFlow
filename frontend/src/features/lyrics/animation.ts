import { makePlan, animatePlan, clamp, type Plan } from './layout.ts';
import type { LyricLine } from './timing';

export const mvModes = ['columns', 'scatter', 'collage', 'cinema'] as const;
export type MVMode = (typeof mvModes)[number];
export interface MVPlan {
  base: Plan;
  mode: MVMode | 'flow';
  width: number;
  height: number;
}
const smooth = (n: number) => {
  n = clamp(n);
  return 1 - Math.pow(1 - n, 3);
};
function chooseMode(
  style: string,
  text: string,
  duration: number,
  repeated: boolean,
  language: string,
): MVMode | 'flow' {
  if (style === 'flow') return 'flow';
  if (mvModes.includes(style as MVMode)) return style as MVMode;
  if (repeated) return 'cinema';
  if (/[!！?？「」“”]/.test(text)) return 'collage';
  if (text.length / (duration / 1000) > 5.5) return 'collage';
  if (language === 'latin') return 'scatter';
  if (duration > 6500) return 'columns';
  return 'collage';
}

export function makeMVPlan(
  line: LyricLine,
  width: number,
  height: number,
  font: number,
  style: string,
  estimate: boolean,
  repeated: boolean,
  measure?: (s: string) => number,
  maxRows = 2,
): MVPlan {
  const base = makePlan(
    line,
    width,
    height,
    font,
    'flow',
    estimate,
    repeated,
    measure,
    maxRows,
  );
  const duration = line.endTime - line.startTime;
  const mode = chooseMode(style, line.text, duration, repeated, base.language);
  // Keep whole English words. CJK vertical writing is shaped as individual timed glyphs.
  if (mode === 'columns' && base.language !== 'latin') {
    const all = base.pages.flat().flatMap((t) =>
      t.letters
        .filter((l) => !/^\s+$/.test(l.text))
        .map((l) => ({
          ...t,
          text: l.text,
          letters: [l],
          widths: [1],
          units: 1,
          startTime: l.startTime,
          endTime: l.endTime,
          space: false,
        })),
    );
    const f = Math.min(font, (height - 110) / 3.7),
      rows = Math.min(3, Math.max(1, Math.floor((height - 110) / (f * 1.25))));
    const cols = Math.max(
      1,
      Math.min(7, Math.floor((width - 120) / (f * 1.8))),
    );
    base.pages = [];
    for (let start = 0; start < all.length; start += rows * cols) {
      const group = all.slice(start, start + rows * cols),
        count = Math.ceil(group.length / rows);
      base.pages.push(
        group.map((t, i) => {
          const column = Math.floor(i / rows),
            size = f * [1, 0.96, 1.03, 0.98][column % 4],
            stagger = [0, 0.32, 0.12, 0.48][column % 4] * f;
          return {
            ...t,
            index: start + i,
            font: size,
            width: size,
            row: i % rows,
            x: width / 2 + (count / 2 - 0.5 - column) * f * 1.25,
            y: 42 + size * 0.75 + (i % rows) * f * 1.25 + stagger,
          };
        }),
      );
    }
  }
  if (mode !== 'columns' || base.language === 'latin') {
    for (const page of base.pages) {
      const rows = [...new Set(page.map((t) => t.row))];
      for (const row of rows) {
        const group = page.filter((t) => t.row === row),
          left = Math.min(...group.map((t) => t.x - t.width / 2)),
          right = Math.max(...group.map((t) => t.x + t.width / 2));
        for (const t of group) {
          t.x += (width - left - right) / 2;
          t.y = 42 + t.font * 0.75 + row * t.font * 1.3;
        }
      }
    }
  }
  if (mode === 'scatter') {
    const seed = Array.from(line.text).reduce(
      (n, c) => n + c.codePointAt(0)!,
      0,
    );
    const all = base.pages.flat().flatMap((t) =>
      base.language === 'cjk'
        ? t.letters
            .filter((l) => !/^\s+$/.test(l.text))
            .map((l) => ({
              ...t,
              text: l.text,
              letters: [l],
              widths: [1],
              units: 1,
              startTime: l.startTime,
              endTime: l.endTime,
              space: false,
            }))
        : [t],
    );
    const rowWidth = Math.min(
      width - 120,
      base.font * (base.language === 'latin' ? 16 : 12),
    );
    const groups: (typeof all)[] = [];
    let group: typeof all = [],
      used = 0;
    all.forEach((t, i) => {
      const factor = [1.12, 0.84, 1, 0.92, 1.06][(i + seed) % 5];
      t.font = base.font * factor;
      t.width = t.units * t.font;
      const gap = t.space ? base.font * 0.3 : base.font * 0.1;
      if (group.length && used + t.width + gap > rowWidth) {
        groups.push(group);
        group = [];
        used = 0;
      }
      group.push({ ...t, index: i });
      used += t.width + gap;
    });
    if (group.length) groups.push(group);
    base.pages = [];
    const capacity = height < 240 ? 1 : 2;
    for (let start = 0; start < groups.length; start += capacity) {
      const page: typeof all = [];
      groups.slice(start, start + capacity).forEach((group, row) => {
        const length = group.reduce(
          (n, t, i) =>
            n +
            t.width +
            (i ? (t.space ? base.font * 0.3 : base.font * 0.1) : 0),
          0,
        );
        let x = (width - length) / 2;
        group.forEach((t, i) => {
          if (i) x += t.space ? base.font * 0.3 : base.font * 0.1;
          const stagger =
            [0, 0.28, -0.1, 0.15][(t.index + seed) % 4] * base.font;
          page.push({
            ...t,
            row,
            x: x + t.width / 2,
            y: 48 + base.font * 0.85 + row * base.font * 1.65 + stagger,
          });
          x += t.width;
        });
      });
      base.pages.push(page);
    }
  }
  return { base, mode, width, height };
}
export function animateMV(plan: MVPlan, time: number, reduced = false) {
  const basic = animatePlan(plan.base, time, reduced),
    { mode, width: w, height: h } = plan;
  const words = plan.base.pages[basic.page] || [];
  const active = Math.max(
    0,
    words.findIndex((t, i) => time < t.endTime || i === words.length - 1),
  );
  const focus = words[active];
  const beat = focus
    ? clamp(
        (time - focus.startTime) /
          Math.max(250, focus.endTime - focus.startTime),
      )
    : 0;
  const enter = smooth((time - plan.base.line.startTime + 80) / 650);
  const wave = Math.sin(beat * Math.PI);
  const motion = reduced ? 0 : 1;
  const glyphs = basic.glyphs.map((t, i) => {
    let x = t.x,
      y = words[i].y,
      font = t.font,
      rotation = 0,
      scale = 1,
      opacity = t.opacity,
      blur = 0,
      depth = 0;
    const local = smooth((time - t.startTime + 220) / 220);
    if (mode === 'columns') {
      if (plan.base.language === 'latin') {
        // Latin reads in sentences, never in a sparse character/word grid.
        const row = words.filter((v) => v.row === t.row),
          allLeft = Math.min(...words.map((v) => v.x - v.width / 2));
        const rowLeft = Math.min(...row.map((v) => v.x - v.width / 2));
        x = t.x - rowLeft + allLeft;
        y = words[i].y;
      }
      const arrival =
        plan.base.language === 'latin'
          ? smooth(
              (time -
                (words.find((v) => v.row === t.row)?.startTime || 0) +
                220) /
                220,
            )
          : local;
      y += (1 - arrival) * 24 * motion;
      opacity = 0.45 + 0.55 * arrival;
      blur = (1 - arrival) * 2 * motion;
      if (plan.base.language !== 'latin') {
        x += Math.sin(basic.phase * Math.PI * 2 + i * 0.25) * 3 * motion;
        rotation = Math.sin(words[i].x * 0.017) * 1.4 * motion;
      }
    } else if (mode === 'scatter') {
      const arrival = smooth((time - t.startTime + 360) / 360);
      const tilt = ((t.index * 7 + plan.base.line.text.length) % 11) - 5;
      x +=
        (1 - arrival) *
        (i % 2 ? 4 : -4) *
        motion *
        (plan.base.language === 'latin' ? 0 : 1);
      y += (1 - arrival) * 18 * motion;
      rotation = tilt * motion * (plan.base.language === 'latin' ? 0.45 : 1);
      opacity = 0.42 + 0.58 * arrival;
      scale = 0.94 + 0.06 * arrival;
      blur = (1 - arrival) * 1.2 * motion;
    } else if (mode === 'collage') {
      // Typeset word tiles: alternating diagonal baselines and paper polarity.
      const row = t.row;
      rotation = (row % 2 ? 1 : -1) * (plan.base.language === 'latin' ? 2 : 4);
      const rowEnter = smooth(
        (time - plan.base.line.startTime - row * 90 + 100) / 700,
      );
      y += (row % 2 ? 1 : -1) * 2;
      x += (1 - rowEnter) * (row % 2 ? -26 : 26) * motion;
      scale = 1;
      opacity = 0.65 + 0.35 * local;
      rotation += Math.sin(basic.phase * Math.PI + i * 0.7) * 0.65 * motion;
    } else if (mode === 'cinema') {
      // 旧版 MV 的缓推镜头：前景保持可读，背景叠字提供纵深。
      const cameraProgress = basic.phase * motion;
      x += (x - w / 2) * cameraProgress * 0.035 + (1 - enter) * 18 * motion;
      y += (t.x - w / 2) * -0.035 * motion;
      rotation = -2 * motion;
      scale = 0.98 + cameraProgress * 0.04;
      opacity = 0.6 + 0.4 * local;
    }
    if (reduced) {
      rotation = 0;
      blur = 0;
      scale = 1;
    }
    const width = t.units * font;
    const rad = (Math.abs(rotation) * Math.PI) / 180;
    const ex =
      ((width * Math.cos(rad) + font * 1.5 * Math.sin(rad)) * scale) / 2 + 40;
    const ey =
      ((font * 1.5 * Math.cos(rad) + width * Math.sin(rad)) * scale) / 2 + 40;
    // Fit the complete transformed glyph, glow and paper inside the native window.
    const fit = Math.min(1, (w - 48) / (ex * 2), (h - 76) / (ey * 2));
    scale *= fit;
    x = clamp(x, ex * fit, w - ex * fit);
    y = clamp(y, ey * fit, h - ey * fit);
    return {
      ...t,
      x,
      y,
      font,
      width,
      rotation,
      scale,
      opacity,
      blur,
      depth,
      local,
      motion,
      hero: i === active,
    };
  });
  return {
    ...basic,
    kind: mode,
    glyphs,
    active,
    beat,
    wave,
    enter,
    focus: focus?.text || plan.base.phrase,
  };
}
