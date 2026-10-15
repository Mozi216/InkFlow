// 用播放时间驱动镜头，不依赖当前句的填充进度。暂停时输入时间不变。
export function ambientMotion(mode: string, time: number, reduced = false) {
  if (reduced) return { transform: 'none', depth: 0 };
  const phase = time / 1000;
  const drift = Math.sin(phase * 0.48);
  const lift = Math.sin(phase * 0.61 + 0.8);
  let x = 0,
    y = 0,
    rotation = 0,
    scale = 1;
  if (mode === 'cinema') {
    x = drift * 6;
    y = lift * 2;
    scale += Math.sin(phase * 0.37) * 0.009;
  } else if (mode === 'columns') {
    x = drift;
    y = lift * 3;
    rotation = drift * 0.15;
  } else if (mode === 'collage') {
    x = drift * 2;
    y = lift * 1.5;
    rotation = drift * 0.25;
  } else if (mode === 'flow') {
    y = lift * 1.6;
  } else {
    x = drift * 3;
    y = lift * 2;
    rotation = drift * 0.18;
  }
  return {
    transform: `translate3d(${x}px,${y}px,0) rotate(${rotation}deg) scale(${scale})`,
    depth: Math.sin(phase * 0.42),
  };
}
