"use client";

import Image from "next/image";
import { motion, useReducedMotion, useScroll, useTransform } from "motion/react";
import { useRef } from "react";
import { DotphinWindow } from "@/demo/DotphinWindow";
import { Icon } from "@/demo/icons";
import { typeSteps, useScriptedDemo, type Step } from "@/demo/player";
import { ScaledWindow } from "@/demo/ScaledWindow";
import { initialState } from "@/demo/state";
import { site } from "@/lib/site";
import { CopyCommand } from "./CopyCommand";
import { WaterCanvas } from "./WaterCanvas";

const heroInitial = initialState();

// Copy a download into the project from the other pane, then ask git about it.
const heroScript: Step[] = [
  { wait: 1400, action: { type: "select", pane: 1, names: [site.download] } },
  { wait: 1100, action: { type: "transferToOther", mode: "copy" } },
  { wait: 1500, action: { type: "select", pane: 0, names: ["README.md"] } },
  { wait: 900, action: { type: "toggleTerminal" } },
  ...typeSteps("git status --short", 60, 500),
  { wait: 450, action: { type: "termRun" } },
];

export function Hero() {
  const stage = useRef<HTMLDivElement>(null);
  const reduced = useReducedMotion();
  const { scrollYProgress } = useScroll({ target: stage, offset: ["start end", "start 0.2"] });
  // The one crafted moment: the window lies back on the water, then stands up as you arrive.
  const rotateX = useTransform(scrollYProgress, [0, 1], reduced ? [0, 0] : [26, 0]);
  const scale = useTransform(scrollYProgress, [0, 1], reduced ? [1, 1] : [0.9, 1]);
  const y = useTransform(scrollYProgress, [0, 1], reduced ? [0, 0] : [40, 0]);

  const { state } = useScriptedDemo(stage, heroInitial, heroScript, { hold: 3400 });

  return (
    <section id="top" className="scroll-mt-8 px-4 pt-10 sm:pt-14">
      <div className="mx-auto flex max-w-[720px] flex-col items-center text-center">
        <Image src="/brand/icon-256.png" alt="" width={104} height={104} priority className="drop-shadow-[0_12px_24px_rgb(29_104_224/0.22)]" />

        <a
          href="#features"
          className="mt-6 flex h-11 items-center gap-2 rounded-full sm:h-9 bg-surface py-1 pl-1 pr-3 text-[14px] font-medium text-ink shadow-[0_0_0_1px_var(--separator-soft),var(--shadow-lift)] transition-colors duration-[var(--dur-quick)] hover:bg-surface-soft"
        >
          <span className="rounded-full bg-accent px-2.5 py-0.5 text-[13px] font-semibold text-white">New in 0.1.2</span>
          Finder-style sidebar
          <Icon.chevronRight size={13} className="text-ink-2" />
        </a>

        <h1 className="mt-6 text-[clamp(44px,8vw,84px)] font-bold leading-[1.02] tracking-[-0.035em]">
          Every folder,
          <br />
          <span className="text-ink-3">side by side.</span>
        </h1>

        <p className="mt-6 max-w-[560px] text-[18px] leading-[1.55] text-ink-2 sm:text-[19px]">
          Dotphin is a native file manager for the Mac with tabs, split panes, an embedded terminal and Git status on every file,
          built in SwiftUI.
        </p>

        <div className="mt-8 flex w-full flex-col items-center gap-3 sm:w-auto sm:flex-row">
          <a
            href={site.releases}
            className="flex h-12 w-full items-center justify-center gap-2 rounded-[14px] bg-accent px-6 text-[16px] font-semibold text-white transition-colors duration-[var(--dur-quick)] hover:bg-accent-hover sm:w-auto"
          >
            <Icon.apple size={15} />
            Download for Mac
          </a>
          <div className="w-full sm:w-auto">
            <CopyCommand command={site.brew} />
          </div>
        </div>
        <p className="mt-4 text-[14px] text-ink-2">Free · {site.requirement} · Beta</p>
      </div>

      <div className="mx-auto mt-10 max-w-[1280px] [perspective:1800px] sm:mt-12">
        <motion.div
          ref={stage}
          style={{ rotateX, scale, y, transformOrigin: "50% 100%" }}
          className="relative overflow-hidden rounded-[28px] py-10 sm:rounded-[36px] sm:py-16"
        >
          <WaterCanvas className="absolute inset-0" />
          <ScaledWindow minScale={0.42} inset={28}>
            <DotphinWindow state={state} />
          </ScaledWindow>
        </motion.div>
      </div>
    </section>
  );
}
