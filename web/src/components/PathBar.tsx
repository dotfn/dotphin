"use client";

// The floating path bar: Dotphin's breadcrumb turned into page navigation.
// It names the section you're in and walks to the previous/next one.

import { AnimatePresence, motion } from "motion/react";
import { useEffect, useRef, useState } from "react";
import { Icon } from "@/demo/icons";
import { sections, site } from "@/lib/site";

function useActiveSection() {
  const [active, setActive] = useState(0);
  useEffect(() => {
    const els = sections.map((s) => document.getElementById(s.id)).filter(Boolean) as HTMLElement[];
    const io = new IntersectionObserver(
      (entries) => {
        for (const e of entries) {
          if (e.isIntersecting) setActive(sections.findIndex((s) => s.id === e.target.id));
        }
      },
      { rootMargin: "-45% 0px -50% 0px" },
    );
    els.forEach((el) => io.observe(el));
    return () => io.disconnect();
  }, []);
  return active;
}

function go(id: string) {
  document.getElementById(id)?.scrollIntoView({ behavior: "smooth", block: "start" });
}

export function PathBar() {
  const active = useActiveSection();
  const [menuOpen, setMenuOpen] = useState(false);
  const menuRef = useRef<HTMLDivElement>(null);
  const current = sections[active];
  const prev = sections[active - 1];
  const next = sections[active + 1];

  useEffect(() => {
    if (!menuOpen) return;
    const close = (e: MouseEvent | KeyboardEvent) => {
      if (e instanceof KeyboardEvent ? e.key === "Escape" : !menuRef.current?.contains(e.target as Node)) setMenuOpen(false);
    };
    document.addEventListener("mousedown", close);
    document.addEventListener("keydown", close);
    return () => {
      document.removeEventListener("mousedown", close);
      document.removeEventListener("keydown", close);
    };
  }, [menuOpen]);

  const btn =
    "flex size-11 shrink-0 items-center justify-center rounded-full text-ink transition-colors duration-[var(--dur-quick)] hover:bg-black/5 disabled:opacity-30 disabled:hover:bg-transparent";

  return (
    <>
      <nav aria-label="Sections" className="fixed inset-x-0 bottom-5 z-40 flex justify-center px-4">
        <div ref={menuRef} className="relative">
          <AnimatePresence>
            {menuOpen && (
              <motion.ul
                initial={{ opacity: 0, y: 8, scale: 0.97 }}
                animate={{ opacity: 1, y: 0, scale: 1 }}
                exit={{ opacity: 0, y: 4, scale: 0.98, transition: { duration: 0.12 } }}
                transition={{ duration: 0.22, ease: [0, 0, 0.2, 1] }}
                style={{ transformOrigin: "24px 100%" }}
                className="glass-strong absolute bottom-[calc(100%+10px)] left-0 w-[260px] rounded-[20px] p-1.5"
              >
                {sections.map((s, i) => (
                  <li key={s.id}>
                    <button
                      type="button"
                      onClick={() => {
                        setMenuOpen(false);
                        go(s.id);
                      }}
                      className="flex min-h-11 w-full items-center gap-3 rounded-[14px] px-3 text-left transition-colors duration-[var(--dur-quick)] hover:bg-black/5"
                      aria-current={i === active ? "location" : undefined}
                    >
                      <span className={`size-1.5 rounded-full ${i === active ? "bg-accent" : "bg-transparent"}`} aria-hidden="true" />
                      <span className="flex-1 text-[15px] font-semibold">{s.title}</span>
                      <span className="text-[13px] text-ink-2">{s.subtitle}</span>
                    </button>
                  </li>
                ))}
              </motion.ul>
            )}
          </AnimatePresence>

          <div className="glass-strong flex h-[var(--bar-height)] w-[min(420px,calc(100vw-32px))] items-center gap-1 rounded-[22px] px-2">
            <button type="button" className={btn} onClick={() => setMenuOpen((o) => !o)} aria-expanded={menuOpen} aria-label="All sections">
              <Icon.menu size={18} />
            </button>
            <button type="button" className={btn} disabled={!prev} onClick={() => prev && go(prev.id)} aria-label={prev ? `Previous: ${prev.title}` : "Previous"}>
              <Icon.chevronLeft size={18} />
            </button>

            <div className="relative flex h-full min-w-0 flex-1 flex-col items-center justify-center overflow-hidden" aria-live="polite">
              <AnimatePresence mode="popLayout" initial={false}>
                <motion.div
                  key={current.id}
                  initial={{ opacity: 0, y: 10 }}
                  animate={{ opacity: 1, y: 0 }}
                  exit={{ opacity: 0, y: -10 }}
                  transition={{ duration: 0.28, ease: [0, 0, 0.2, 1] }}
                  className="flex flex-col items-center"
                >
                  <span className="flex items-center gap-1 text-[15px] font-semibold leading-tight">
                    {active > 0 && (
                      <>
                        <span className="hidden text-ink-2 min-[380px]:inline">Dotphin</span>
                        <Icon.chevronRight size={11} className="hidden text-ink-3 min-[380px]:block" />
                      </>
                    )}
                    <span className="truncate">{current.title}</span>
                  </span>
                  <span className="text-[13px] leading-tight text-ink-2">{current.subtitle}</span>
                </motion.div>
              </AnimatePresence>
            </div>

            <button type="button" className={btn} disabled={!next} onClick={() => next && go(next.id)} aria-label={next ? `Next: ${next.title}` : "Next"}>
              <Icon.chevronRight size={18} />
            </button>
            <a
              href={site.releases}
              className="flex size-11 shrink-0 items-center justify-center rounded-full bg-accent text-white transition-colors duration-[var(--dur-quick)] hover:bg-accent-hover"
              aria-label="Download Dotphin"
            >
              <Icon.download size={19} />
            </a>
          </div>
        </div>
      </nav>

      <a
        href={site.studio.url}
        className="glass fixed bottom-5 left-5 z-30 hidden h-11 items-center gap-1.5 rounded-full px-4 text-[14px] font-semibold text-ink lg:flex"
      >
        <span className="size-2 rounded-full bg-ink" aria-hidden="true" />
        fn
        <span className="sr-only"> — dotfn studio</span>
      </a>
      <a
        href={site.repo}
        className="glass fixed bottom-5 right-5 z-30 hidden h-11 items-center gap-2 rounded-full px-4 text-[14px] font-semibold text-ink lg:flex"
      >
        <Icon.github size={16} />
        GitHub
      </a>
    </>
  );
}
