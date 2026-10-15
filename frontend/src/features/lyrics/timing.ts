export interface LyricWord {
  text: string;
  startTime: number;
  endTime: number;
}
export interface LyricLine {
  text: string;
  startTime: number;
  endTime: number;
  words: LyricWord[];
}
export function lineAt(lines: LyricLine[], position: number): number {
  let low = 0,
    high = lines.length - 1,
    found = -1;
  while (low <= high) {
    const mid = (low + high) >> 1;
    if (lines[mid].startTime <= position) {
      found = mid;
      low = mid + 1;
    } else high = mid - 1;
  }
  return found;
}
export function wordProgress(position: number, start: number, end: number) {
  return Math.max(
    0,
    Math.min(1, (position - start) / Math.max(1, end - start)),
  );
}
export function interpolate(
  position: number,
  anchor: number,
  now: number,
  playing: boolean,
  duration: number,
) {
  return Math.max(
    0,
    Math.min(duration, position + (playing ? Math.max(0, now - anchor) : 0)),
  );
}
export function timeLabel(ms: number) {
  const s = Math.floor(ms / 1000);
  return `${Math.floor(s / 60)}:${String(s % 60).padStart(2, '0')}`;
}
