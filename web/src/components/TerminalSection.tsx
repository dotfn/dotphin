"use client";

import { useRef } from "react";
import { Breadcrumb } from "@/demo/DotphinWindow";
import { typeSteps, useScriptedDemo, type Step } from "@/demo/player";
import { initialState, pane } from "@/demo/state";
import { Terminal } from "@/demo/Terminal";
import { Kbd } from "./Kbd";

const start = initialState({
  split: false,
  panes: [pane("~/Developer"), pane("~/Downloads")],
  terminal: { open: true, lines: [], input: "" },
});

// List a folder, open a project in the pane, and watch the shell follow.
const script: Step[] = [
  ...typeSteps("ls", 90, 900),
  { wait: 350, action: { type: "termRun" } },
  { wait: 1600, action: { type: "navigate", pane: 0, path: "~/Developer/dotphin" } },
  ...typeSteps("git log --oneline -3", 55, 900),
  { wait: 400, action: { type: "termRun" } },
];

export function TerminalSection() {
  const ref = useRef<HTMLDivElement>(null);
  const { state } = useScriptedDemo(ref, start, script, { hold: 4000 });

  return (
    <section id="terminal" className="scroll-mt-8 px-4 pt-28 sm:pt-36">
      <div className="mx-auto grid max-w-[1180px] items-center gap-10 overflow-hidden rounded-[36px] bg-[var(--term-bg)] p-6 text-white sm:p-12 lg:grid-cols-[0.9fr_1.1fr] lg:p-16">
        <div>
          <h2 className="text-[clamp(34px,5vw,52px)] font-bold leading-[1.06] tracking-[-0.03em]">A real terminal, one key away.</h2>
          <p className="mt-5 max-w-[480px] text-[18px] leading-[1.55] text-white/75">
            Press <Kbd tone="dark">⌃`</Kbd> and a full terminal docks under your files, already in the folder you&rsquo;re looking at.
            Open another folder and it follows.
          </p>
          <ul className="mt-8 space-y-3 text-[16px] text-white/75">
            <li>xterm-compatible, with 256 colors and truecolor</li>
            <li>
              <code className="font-mono text-[15px] text-white">vim</code>, <code className="font-mono text-[15px] text-white">less</code> and{" "}
              <code className="font-mono text-[15px] text-white">htop</code> work, mouse included
            </li>
            <li>
              <Kbd tone="dark">⌃⇧`</Kbd> opens Terminal.app in the same folder instead
            </li>
          </ul>
        </div>

        <div ref={ref} className="overflow-hidden rounded-[20px] bg-white/[.04] shadow-[0_0_0_1px_rgb(255_255_255/.08)]">
          <div className="bg-[rgb(248_250_251)] font-mac text-[13px] text-[var(--mac-ink)]">
            <Breadcrumb path={state.panes[0].path} focused />
          </div>
          <Terminal state={state} height={340} />
        </div>
      </div>
    </section>
  );
}
