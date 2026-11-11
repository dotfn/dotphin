"use client";

import { useState } from "react";
import { Icon } from "@/demo/icons";

/** The Homebrew one-liner, copyable. The prompt sign isn't part of the copy. */
export function CopyCommand({ command, tone = "light" }: { command: string; tone?: "light" | "dark" }) {
  const [copied, setCopied] = useState(false);

  async function copy() {
    try {
      await navigator.clipboard.writeText(command);
      setCopied(true);
      setTimeout(() => setCopied(false), 1600);
    } catch {
      // Clipboard blocked: the text is still selectable.
    }
  }

  const dark = tone === "dark";
  return (
    <div
      className={`flex h-12 max-w-full items-center gap-3 rounded-[14px] pl-4 pr-0.5 sm:pr-1.5 font-mono text-[14px] ${
        dark ? "bg-white/10 text-white" : "bg-surface text-ink shadow-[0_0_0_1px_var(--separator-soft),var(--shadow-lift)]"
      }`}
    >
      <span className={dark ? "text-white/60" : "text-ink-2"} aria-hidden="true">
        $
      </span>
      <code className="min-w-0 truncate select-all">{command}</code>
      <button
        type="button"
        onClick={copy}
        className={`ml-auto flex h-11 shrink-0 sm:h-9 items-center gap-1.5 rounded-[10px] px-3 font-sans text-[14px] font-semibold transition-colors duration-[var(--dur-quick)] ${
          dark ? "bg-white/12 hover:bg-white/20" : "bg-bg hover:bg-bg-sunk"
        }`}
        aria-label={copied ? "Copied to clipboard" : "Copy install command"}
      >
        {copied ? <Icon.check size={15} /> : <Icon.copy size={15} />}
        <span aria-live="polite">{copied ? "Copied" : "Copy"}</span>
      </button>
    </div>
  );
}
