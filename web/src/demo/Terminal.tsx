// The ⌃` terminal panel, docked under the panes like in the app.

import type { CSSProperties } from "react";
import { displayName } from "./fs";
import { Icon } from "./icons";
import type { DemoState, TermLine, TermSpan } from "./state";

const tone: Record<NonNullable<TermSpan["tone"]>, CSSProperties> = {
  dim: { color: "var(--term-dim)" },
  green: { color: "var(--term-green)" },
  blue: { color: "var(--term-blue)" },
  yellow: { color: "var(--term-yellow)" },
  red: { color: "var(--term-red)" },
  bold: { fontWeight: 700 },
};

export function TermText({ line }: { line: TermLine }) {
  return (
    <div className="whitespace-pre">
      {line.map((s, i) => (
        <span key={i} style={s.tone ? tone[s.tone] : undefined}>
          {s.text}
        </span>
      ))}
    </div>
  );
}

export function Terminal({ state, height = 210 }: { state: DemoState; height?: number }) {
  const cwd = state.panes[state.focused].path;
  return (
    <div className="flex shrink-0 flex-col" style={{ height, background: "var(--term-bg)", color: "var(--term-ink)" }}>
      <div className="flex h-[30px] shrink-0 items-center gap-2 border-b border-white/10 px-3 font-mac text-[12px]">
        <Icon.terminal size={14} className="text-[var(--term-blue)]" />
        <span className="font-semibold">Terminal — {displayName(cwd)}</span>
        <span className="text-[var(--term-dim)]">{cwd}</span>
        <span className="ml-auto flex items-center gap-1 rounded-[5px] bg-[rgb(115_183_255/0.14)] px-1.5 py-[1px] text-[12px] text-[var(--term-blue)]">
          Sync
        </span>
      </div>
      <div className="flex min-h-0 flex-1 flex-col justify-end overflow-hidden px-3 py-2 font-mono text-[12px] leading-[1.55]">
        {state.terminal.lines.slice(-9).map((l, i) => (
          <TermText key={i} line={l} />
        ))}
        <div className="whitespace-pre">
          <span style={tone.blue}>{cwd.replace("~/Developer/", "")}</span>
          <span style={tone.dim}> % </span>
          <span>{state.terminal.input}</span>
          <span className="ml-px inline-block h-[13px] w-[7px] translate-y-[2px] bg-[var(--term-ink)] [animation:caret_1.1s_steps(1)_infinite]" />
        </div>
      </div>
    </div>
  );
}
