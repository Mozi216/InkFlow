import { writeFile, mkdir } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { makeMVPlan, animateMV } from '../../frontend/src/features/lyrics/animation.ts';
import { ambientMotion } from '../../frontend/src/features/lyrics/ambient-motion.ts';

const texts = ['让风穿过安静的窗，把光轻轻留下', 'Let the light stay with us'];
const cases = [];
const word = (w) => ({ t: w.text, s: w.startTime / 1000, e: w.endTime / 1000 });
for (const text of texts) {
  const chars = Array.from(text);
  const line = { text, startTime: 1000, endTime: 9000, words: chars.map((text, i) => ({
    text, startTime: 1000 + i * 8000 / chars.length, endTime: 1000 + (i + 1) * 8000 / chars.length,
  })) };
  for (const style of ['flow', 'columns', 'scatter', 'collage', 'cinema', 'mv']) {
    const source = makeMVPlan(line, 740, 280, 50, style, true, false);
    const plan = {
      line: { text, start: 1, end: 9, words: line.words.map(word) },
      style: source.mode, language: source.base.language, width: 740, height: 280, font: source.base.font,
      pages: source.base.pages.map(page => page.map(t => ({
        token: { text: t.text, letters: t.letters.map(word), widths: t.widths, units: t.units, space: t.space },
        x: t.x, y: t.y, font: t.font, width: t.width, row: t.row, index: t.index,
      }))),
    };
    for (const time of [1, 3.3, 8.8]) for (const reduced of [false, true]) {
      const scene = animateMV(source, time * 1000, reduced);
      cases.push({ label: `${style}/${source.base.language}/${time}/${reduced}`, plan, time, reduced,
        expected: scene.glyphs.map(t => ({ index: t.index, x: t.x, y: t.y, scale: t.scale,
          rotation: t.rotation, opacity: t.opacity, blur: t.blur, fill: t.fill / 100 })),
        ambient: ambientMotion(source.mode, time * 1000, reduced),
      });
    }
  }
}
const folder = new URL('../InkFlowCore/Tests/InkFlowCoreTests/Fixtures/', import.meta.url);
await mkdir(folder, { recursive: true });
await writeFile(new URL('motion.json', folder), JSON.stringify(cases));
console.log(`Exported ${cases.length} reference scenes to ${fileURLToPath(folder)}`);
