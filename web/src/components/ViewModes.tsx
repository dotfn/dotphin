"use client";

// The first hands-on piece: a real control driving the demo window through
// the same reducer the scripted demos use.

import { useReducer } from "react";
import { DotphinWindow } from "@/demo/DotphinWindow";
import { Icon } from "@/demo/icons";
import { ScaledWindow } from "@/demo/ScaledWindow";
import { initialState, pane, reduce, type ViewMode } from "@/demo/state";
import { Kbd } from "./Kbd";

const start = initialState({
  split: false,
  tabs: ["Pictures"],
  panes: [pane("~/Pictures", "icons"), pane("~/Developer/dotphin")],
});

const modes: { mode: ViewMode; label: string; icon: (p: { size?: number }) => React.ReactNode }[] = [
  { mode: "icons", label: "Icons", icon: Icon.grid },
  { mode: "compact", label: "Compact", icon: Icon.compact },
  { mode: "details", label: "Details", icon: Icon.table },
];

export function ViewModes() {
  const [state, dispatch] = useReducer(reduce, start);
  const current = state.panes[0].viewMode;

  return (
    <section id="views" className="scroll-mt-8 px-4 pt-28 sm:pt-36">
      <div className="mx-auto max-w-[1080px]">
        <div className="grid items-end gap-8 lg:grid-cols-[1fr_auto]">
          <div>
            <h2 className="max-w-[620px] text-[clamp(34px,5vw,52px)] font-bold leading-[1.06] tracking-[-0.03em]">
              Icons for photos. Details for code.
            </h2>
            <p className="mt-5 max-w-[560px] text-[18px] leading-[1.55] text-ink-2">
              Each folder remembers its own view, sort, grouping and zoom, so Pictures can stay a grid while your projects stay a
              list. Try it.
            </p>
          </div>

          <div role="radiogroup" aria-label="View mode" className="flex rounded-[16px] bg-surface p-1 shadow-[0_0_0_1px_var(--separator-soft)]">
            {modes.map((m) => {
              const on = current === m.mode;
              return (
                <button
                  key={m.mode}
                  type="button"
                  role="radio"
                  aria-checked={on}
                  onClick={() => dispatch({ type: "setViewMode", pane: 0, mode: m.mode })}
                  className={`flex h-11 items-center gap-2 rounded-[12px] px-4 text-[15px] font-semibold transition-colors duration-[var(--dur-quick)] ${
                    on ? "bg-ink text-white" : "text-ink-2 hover:bg-bg hover:text-ink"
                  }`}
                >
                  <m.icon size={16} />
                  {m.label}
                </button>
              );
            })}
          </div>
        </div>

        <div className="relative mt-10 overflow-hidden rounded-[28px] bg-bg-sunk py-8 sm:py-12">
          <ScaledWindow minScale={0.42} maxScale={0.9} inset={24} height={500}>
            <DotphinWindow state={state} height={500} />
          </ScaledWindow>
        </div>
        <p className="mt-4 flex flex-wrap items-center gap-1.5 text-[15px] text-ink-2">
          In the app: <Kbd>⌘1</Kbd> to <Kbd>⌘4</Kbd> switch modes, <Kbd>⌘+</Kbd> and <Kbd>⌘−</Kbd> zoom.
        </p>
      </div>
    </section>
  );
}
