"use client";

// Fits the fixed-size window into whatever width it's given, so the inside
// keeps its real desktop proportions. Below `minScale` it crops instead of
// shrinking further — the sidebar and first pane stay readable on a phone.

import { useEffect, useRef, useState, type ReactNode } from "react";
import { WINDOW_SIZE } from "./DotphinWindow";

export function ScaledWindow({
  children,
  minScale = 0.5,
  maxScale = 1,
  inset = 48,
  height = WINDOW_SIZE.height,
}: {
  children: ReactNode;
  minScale?: number;
  maxScale?: number;
  inset?: number;
  height?: number;
}) {
  const box = useRef<HTMLDivElement>(null);
  const [scale, setScale] = useState(maxScale);

  useEffect(() => {
    const el = box.current;
    if (!el) return;
    const ro = new ResizeObserver(([entry]) => {
      const w = entry.contentRect.width - inset * 2;
      setScale(Math.max(minScale, Math.min(maxScale, w / WINDOW_SIZE.width)));
    });
    ro.observe(el);
    return () => ro.disconnect();
  }, [minScale, maxScale, inset]);

  return (
    <div ref={box} className="relative w-full" style={{ height: height * scale }}>
      <div
        className="absolute top-0 origin-top-left"
        style={{
          transform: `scale(${scale})`,
          // centered while it fits, pinned left once it has to crop
          left: `max(${inset * Math.min(1, scale * 2)}px, calc(50% - ${(WINDOW_SIZE.width * scale) / 2}px))`,
        }}
      >
        {children}
      </div>
    </div>
  );
}
