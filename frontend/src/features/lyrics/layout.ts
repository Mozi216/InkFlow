import type { LyricLine, LyricWord } from './timing';
import { glyphs, timedGlyphs } from './graphemes.ts';
export type Composition =
  | 'flow'
  | 'headline'
  | 'editorial'
  | 'dialogue'
  | 'cascade'
  | 'refrain'
  | 'sustain';
export interface Token {
  text: string;
  startTime: number;
  endTime: number;
  letters: LyricWord[];
  widths: number[];
  units: number;
  space: boolean;
}
export interface PlacedToken extends Token {
  x: number;
  y: number;
  font: number;
  width: number;
  row: number;
  index: number;
}
export interface Plan {
  kind: Composition;
  language: 'latin' | 'cjk' | 'mixed';
  pages: PlacedToken[][];
  width: number;
  height: number;
  line: LyricLine;
  phrase: string;
  font: number;
}
export const clamp = (v: number, min = 0, max = 1) =>
  Math.max(min, Math.min(max, v));
const ease = (v: number) => {
  v = clamp(v);
  return v * v * (3 - 2 * v);
};
const fallbackWidth = (s: string) =>
  glyphs(s).reduce(
    (sum, c) =>
      sum +
      (/[\p{Script=Han}\p{Script=Hiragana}\p{Script=Katakana}]/u.test(c)
        ? 1
        : /[ilI.,'!|]/.test(c)
          ? 0.25
          : /[mwMW]/.test(c)
            ? 0.85
            : /\s/.test(c)
              ? 0.28
              : 0.53),
    0,
  );
export function languageTokens(
  line: LyricLine,
  estimate = true,
  measure: (s: string) => number = fallbackWidth,
): Token[] {
  const letters = timedGlyphs(line, estimate);
  const text = letters.map((l) => l.text).join('');
  const latin = (text.match(/[\p{Script=Latin}]/gu) || []).length;
  const cjk = (
    text.match(/[\p{Script=Han}\p{Script=Hiragana}\p{Script=Katakana}]/gu) || []
  ).length;
  const locale = cjk > latin ? 'ja' : 'en';
  const parts = Array.from(
    new Intl.Segmenter(locale, { granularity: 'word' }).segment(text),
  );
  const tokens: Token[] = [];
  let cursor = 0,
    space = false;
  for (const part of parts) {
    const count = glyphs(part.segment).length;
    const slice = letters.slice(cursor, cursor + count);
    cursor += count;
    if (!slice.length) continue;
    if (/^\s+$/.test(part.segment)) {
      space = true;
      continue;
    }
    if (!part.isWordLike && tokens.length) {
      const last = tokens.at(-1)!;
      last.text += part.segment;
      last.letters.push(...slice);
      last.endTime = slice.at(-1)!.endTime;
      last.units = measure(last.text);
      last.widths = last.letters.map((l) => measure(l.text));
      continue;
    }
    tokens.push({
      text: part.segment,
      startTime: slice[0].startTime,
      endTime: slice.at(-1)!.endTime,
      letters: slice,
      widths: slice.map((l) => measure(l.text)),
      units: Math.max(0.2, measure(part.segment)),
      space,
    });
    space = false;
  }
  return tokens;
}
export function makePlan(
  line: LyricLine,
  width: number,
  height: number,
  limit: number,
  mode: string,
  estimate = true,
  repeated = false,
  measure?: (s: string) => number,
  maxRows = 3,
): Plan {
  const tokens = languageTokens(line, estimate, measure);
  const latin = (line.text.match(/[\p{Script=Latin}]/gu) || []).length;
  const cjk = (
    line.text.match(
      /[\p{Script=Han}\p{Script=Hiragana}\p{Script=Katakana}]/gu,
    ) || []
  ).length;
  const language =
    latin > cjk * 2 ? 'latin' : cjk > latin * 2 ? 'cjk' : 'mixed';
  const duration = Math.max(1, line.endTime - line.startTime);
  const density = glyphs(line.text).length / (duration / 1000);
  const longest = Math.max(
    0,
    ...line.words.map((t) => t.endTime - t.startTime),
  );
  const kind: Composition =
    mode === 'flow'
      ? 'flow'
      : repeated
        ? 'refrain'
        : /[?？「」“”]/.test(line.text)
          ? 'dialogue'
          : tokens.length <= 4 && line.text.length < 22
            ? 'headline'
            : duration > 6500 && longest > 1100
              ? 'sustain'
              : language === 'latin'
                ? 'editorial'
                : density > 5.5
                  ? 'cascade'
                  : /[，、,；;]/.test(line.text)
                    ? 'dialogue'
                    : 'sustain';
  const safeW = Math.max(100, width - 104),
    safeH = Math.max(70, height - 116);
  const total = tokens.reduce((n, t) => n + t.units + (t.space ? 0.28 : 0), 0);
  const targetFont =
    limit * (kind === 'headline' ? 1.48 : kind === 'refrain' ? 1.15 : 1);
  const maxToken = Math.max(1, ...tokens.map((t) => t.units));
  const font = Math.max(
    14,
    Math.min(
      targetFont,
      safeW / (maxToken * 1.08),
      safeH / (kind === 'headline' ? 1.7 : 2.9),
    ),
  );
  const rowLimit = Math.max(
    1,
    Math.min(maxRows, Math.floor(safeH / (font * 1.55))),
  );
  // Deliberate phrase width and native word advances replace the old character grid.
  const rowWidth = Math.min(
    safeW,
    font *
      Math.max(
        5,
        Math.min(
          safeW / font,
          total / Math.min(rowLimit, Math.ceil((total * font) / safeW)),
        ),
      ),
  );
  const rows: Token[][] = [];
  let row: Token[] = [],
    units = 0;
  for (const t of tokens) {
    const advance = t.units + (row.length && t.space ? 0.28 : 0);
    if (row.length && (units + advance) * font > rowWidth) {
      rows.push(row);
      row = [];
      units = 0;
    }
    row.push(t);
    units += t.units + (row.length > 1 && t.space ? 0.28 : 0);
    if (/[，、,；;!?？！]$/.test(t.text) && units * font > rowWidth * 0.48) {
      rows.push(row);
      row = [];
      units = 0;
    }
  }
  if (row.length) rows.push(row);
  const pages: PlacedToken[][] = [];
  let index = 0;
  for (let start = 0; start < rows.length; start += rowLimit) {
    const group = rows.slice(start, start + rowLimit),
      placed: PlacedToken[] = [];
    const lineHeight = font * 1.55;
    group.forEach((r, ri) => {
      const rowUnits = r.reduce(
        (s, t, i) => s + t.units + (i && t.space ? 0.28 : 0),
        0,
      );
      const length = rowUnits * font;
      const offset =
        kind === 'cascade' ? (ri - (group.length - 1) / 2) * font * 0.4 : 0;
      let x =
        kind === 'editorial'
          ? Math.max(52, (width - rowWidth) / 2)
          : kind === 'dialogue'
            ? ri % 2
              ? width - length - 64
              : 64
            : (width - length) / 2 + offset;
      x = clamp(x, 52, width - length - 52);
      const y = height / 2 + 12 + (ri - (group.length - 1) / 2) * lineHeight;
      r.forEach((t, i) => {
        if (i && t.space) x += font * 0.28;
        const w = t.units * font;
        placed.push({
          ...t,
          x: x + w / 2,
          y,
          font,
          width: w,
          row: ri,
          index: index++,
        });
        x += w;
      });
    });
    pages.push(placed);
  }
  return {
    kind,
    language,
    pages,
    width,
    height,
    line,
    phrase:
      tokens
        .filter((t) => t.text.length > 1)
        .sort((a, b) => b.endTime - b.startTime - (a.endTime - a.startTime))[0]
        ?.text ||
      tokens[0]?.text ||
      '',
    font,
  };
}
export function animatePlan(plan: Plan, time: number, reduced = false) {
  const page = Math.max(
    0,
    plan.pages.findIndex(
      (_, i) => !plan.pages[i + 1] || time < plan.pages[i + 1][0].startTime,
    ),
  );
  const words = plan.pages[page] || [];
  const phase = clamp(
    (time - plan.line.startTime) /
      Math.max(1, plan.line.endTime - plan.line.startTime),
  );
  const motion = reduced ? 0 : 1;
  const glyphs = words.map((word) => {
    const fillUnits = word.letters.reduce(
      (sum, l, j) =>
        sum +
        word.widths[j] *
          clamp(
            l.endTime > l.startTime
              ? (time - l.startTime) / (l.endTime - l.startTime)
              : time >= l.startTime
                ? 1
                : 0,
          ),
      0,
    );
    const fill = clamp(
      fillUnits /
        Math.max(
          0.01,
          word.widths.reduce((a, b) => a + b, 0),
        ),
    );
    const active = time >= word.startTime && time < word.endTime;
    const hit = active
      ? Math.sin(
          clamp(
            (time - word.startTime) /
              Math.max(1, word.endTime - word.startTime),
          ) * Math.PI,
        )
      : 0;
    const enter = reduced ? 1 : ease((time - word.startTime + 240) / 240);
    let dx = 0,
      dy = 0,
      rotation = 0,
      scale = 1;
    if (plan.kind === 'headline')
      scale = 0.94 + 0.06 * enter + hit * 0.025 * motion;
    if (plan.kind === 'editorial') {
      dx = (1 - enter) * word.font * -0.28;
      dy = (1 - enter) * word.font * 0.12;
    }
    if (plan.kind === 'dialogue') {
      dx = (word.row % 2 ? 1 : -1) * (1 - enter) * word.font * 0.5;
    }
    if (plan.kind === 'cascade') {
      dy = (1 - enter) * word.font * 0.4;
      rotation = (1 - enter) * -3;
    }
    if (plan.kind === 'refrain') {
      scale = 1 + hit * 0.035 * motion;
      dy = -hit * word.font * 0.025 * motion;
    }
    if (plan.kind === 'sustain') {
      dy = Math.sin(phase * Math.PI) * -word.font * 0.045 * motion;
    }
    const extentX =
      (word.width / 2 + word.font * 0.04) * scale +
      Math.abs(rotation) * word.font * 0.015 +
      16;
    const extentY =
      word.font * 0.7 * scale + Math.abs(rotation) * word.width * 0.009 + 16;
    const x = clamp(word.x + dx * motion, extentX, plan.width - extentX),
      y = clamp(word.y + dy * motion, 45 + extentY, plan.height - extentY);
    return {
      ...word,
      x,
      y,
      rotation: rotation * motion,
      scale,
      fill: fill * 100,
      hit,
      opacity: 0.25 + 0.75 * enter,
      blur: (1 - enter) * 5 * motion,
    };
  });
  return { glyphs, page, phase, kind: plan.kind, language: plan.language };
}
