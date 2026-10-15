import type { LyricLine, LyricWord } from './timing';

export function glyphs(text: string): string[] {
  return Array.from(
    new Intl.Segmenter(undefined, { granularity: 'grapheme' }).segment(text),
    (x) => x.segment,
  );
}
export function displayWords(line: LyricLine, estimate: boolean): LyricWord[] {
  if (line.words.length) return line.words;
  if (!estimate) return [];
  const chars = glyphs(line.text);
  const weights = chars.map((c) => (/[\s，。！？、,.!?…]/u.test(c) ? 0.35 : 1));
  const total = weights.reduce((a, b) => a + b, 0) || 1;
  let elapsed = 0;
  const duration = Math.max(1, line.endTime - line.startTime);
  return chars.map((text, i) => {
    const startTime = line.startTime + (elapsed / total) * duration;
    elapsed += weights[i];
    return {
      text,
      startTime,
      endTime: line.startTime + (elapsed / total) * duration,
    };
  });
}
export function timedGlyphs(line: LyricLine, estimate: boolean): LyricWord[] {
  const words = displayWords(line, estimate);
  if (!words.length)
    return glyphs(line.text).map((text) => ({
      text,
      startTime: line.startTime,
      endTime: line.startTime,
    }));
  return words.flatMap((word) => {
    const chars = glyphs(word.text);
    return chars.map((text, i) => ({
      text,
      startTime:
        word.startTime + ((word.endTime - word.startTime) * i) / chars.length,
      endTime:
        word.startTime +
        ((word.endTime - word.startTime) * (i + 1)) / chars.length,
    }));
  });
}
