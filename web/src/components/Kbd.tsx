import type { ReactNode } from "react";

/** An inline key cap. Sits on the text baseline so it can live inside a sentence. */
export function Kbd({ children, tone = "light" }: { children: ReactNode; tone?: "light" | "dark" }) {
  return (
    <kbd
      className={`inline-flex h-[22px] min-w-[22px] items-center justify-center rounded-[6px] px-1.5 align-[1px] font-sans text-[13px] font-semibold leading-none ${
        tone === "dark"
          ? "bg-white/12 text-white shadow-[inset_0_-1px_0_rgb(255_255_255/.12)]"
          : "bg-surface text-ink shadow-[0_0_0_1px_var(--separator),inset_0_-1px_0_var(--separator)]"
      }`}
    >
      {children}
    </kbd>
  );
}
