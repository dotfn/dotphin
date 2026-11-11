"use client";

// A Mac keyboard that lights up the keys of whichever shortcut you point at.
// Every shortcut here is read from the app's menu commands.

import { useState } from "react";

type Shortcut = { keys: string[]; label: string; group: string };

const shortcuts: Shortcut[] = [
  { keys: ["cmd", "\\"], label: "Split view", group: "Panes" },
  { keys: ["opt", "cmd", "\\"], label: "Focus the other pane", group: "Panes" },
  { keys: ["ctrl", "cmd", "C"], label: "Copy to the other pane", group: "Panes" },
  { keys: ["ctrl", "cmd", "M"], label: "Move to the other pane", group: "Panes" },
  { keys: ["ctrl", "`"], label: "Terminal panel", group: "Panels" },
  { keys: ["opt", "cmd", "I"], label: "Info panel", group: "Panels" },
  { keys: ["cmd", "/"], label: "Filter bar", group: "Panels" },
  { keys: ["cmd", "U"], label: "Disk usage", group: "Panels" },
  { keys: ["return"], label: "Rename", group: "Files" },
  { keys: ["cmd", "Y"], label: "Quick Look", group: "Files" },
  { keys: ["cmd", "T"], label: "New tab", group: "Files" },
  { keys: ["shift", "cmd", "."], label: "Show hidden files", group: "Files" },
];

const glyph: Record<string, string> = { cmd: "⌘", shift: "⇧", ctrl: "⌃", opt: "⌥", return: "↩" };

// Rows of [id, label, width in key units]
const rows: [string, string, number][][] = [
  [["esc", "esc", 1.5], ...Array.from({ length: 12 }, (_, i): [string, string, number] => [`F${i + 1}`, `F${i + 1}`, 1]), ["power", "", 1]],
  [["`", "`", 1], ..."1234567890".split("").map((k): [string, string, number] => [k, k, 1]), ["-", "-", 1], ["=", "=", 1], ["delete", "⌫", 1.5]],
  [["tab", "⇥", 1.5], ..."QWERTYUIOP".split("").map((k): [string, string, number] => [k, k, 1]), ["[", "[", 1], ["]", "]", 1], ["\\", "\\", 1]],
  [["caps", "⇪", 1.8], ..."ASDFGHJKL".split("").map((k): [string, string, number] => [k, k, 1]), [";", ";", 1], ["'", "'", 1], ["return", "↩", 1.7]],
  [["shift", "⇧", 2.3], ..."ZXCVBNM".split("").map((k): [string, string, number] => [k, k, 1]), [",", ",", 1], [".", ".", 1], ["/", "/", 1], ["shift", "⇧", 2.2]],
  [["fn", "fn", 1], ["ctrl", "⌃", 1], ["opt", "⌥", 1], ["cmd", "⌘", 1.3], ["space", "", 5.2], ["cmd", "⌘", 1.3], ["opt", "⌥", 1], ["arrows", "", 3]],
];

function keyLabel(k: string) {
  return glyph[k] ?? k;
}

export function Shortcuts() {
  const [active, setActive] = useState(0);
  const lit = new Set(shortcuts[active].keys);
  const groups = [...new Set(shortcuts.map((s) => s.group))];

  return (
    <section id="shortcuts" className="scroll-mt-8 px-4 pt-28 sm:pt-36">
      <div className="mx-auto max-w-[1080px]">
        <h2 className="max-w-[620px] text-[clamp(34px,5vw,52px)] font-bold leading-[1.06] tracking-[-0.03em]">
          Your hands can stay on the keys.
        </h2>
        <p className="mt-5 max-w-[560px] text-[18px] leading-[1.55] text-ink-2">
          The shortcuts follow macOS and Finder, so none of them collides with the system. Function keys (F3, F4, F5) work too, if you prefer them. Point at a shortcut to find it.
        </p>

        <div className="mt-12 grid items-start gap-10 lg:grid-cols-[1.25fr_1fr]">
          <div className="@container overflow-hidden rounded-[28px] bg-bg-sunk p-4 sm:p-6 lg:sticky lg:top-24" aria-hidden="true">
            <div className="flex flex-col gap-[0.8cqw] rounded-[2.6cqw] bg-[#d9dde1] p-[1.8cqw] shadow-[inset_0_1px_0_rgb(255_255_255/.6),0_1px_0_rgb(16_24_32/.08)]">
              {rows.map((row, r) => (
                <div key={r} className="flex gap-[0.8cqw]" style={{ height: r === 0 ? "4.6cqw" : "6.6cqw" }}>
                  {row.map(([id, label, w], i) => {
                    const on = lit.has(id);
                    return (
                      <div
                        key={`${id}-${i}`}
                        style={{ flexGrow: w, flexBasis: 0 }}
                        className={`flex min-w-0 items-center justify-center rounded-[1.1cqw] text-[1.7cqw] font-semibold leading-none transition-[background-color,color,transform] duration-[var(--dur-quick)] ${
                          on ? "translate-y-[0.2cqw] bg-accent text-white" : "bg-[#f7f8f9] text-[var(--mac-ink-2)] shadow-[0_0.2cqw_0_rgb(16_24_32/.18)]"
                        }`}
                      >
                        {label}
                      </div>
                    );
                  })}
                </div>
              ))}
            </div>
          </div>

          <div className="grid gap-8 sm:grid-cols-3 lg:grid-cols-1">
            {groups.map((g) => (
              <div key={g}>
                <h3 className="text-[15px] font-semibold text-ink-2">{g}</h3>
                <ul className="mt-2">
                  {shortcuts.map((s, i) =>
                    s.group !== g ? null : (
                      <li key={s.label}>
                        <button
                          type="button"
                          onMouseEnter={() => setActive(i)}
                          onFocus={() => setActive(i)}
                          onClick={() => setActive(i)}
                          aria-pressed={active === i}
                          className={`flex min-h-11 w-full items-center justify-between gap-4 rounded-[12px] px-3 text-left text-[16px] transition-colors duration-[var(--dur-quick)] ${
                            active === i ? "bg-surface" : "hover:bg-surface/60"
                          }`}
                        >
                          <span>{s.label}</span>
                          <span className="flex shrink-0 gap-1 font-semibold text-ink-2">
                            {s.keys.map((k) => (
                              <span key={k} className="min-w-[1ch] text-center">
                                {keyLabel(k)}
                              </span>
                            ))}
                          </span>
                        </button>
                      </li>
                    ),
                  )}
                </ul>
              </div>
            ))}
          </div>
        </div>
      </div>
    </section>
  );
}
