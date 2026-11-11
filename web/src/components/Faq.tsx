import { site } from "@/lib/site";

const faq: { q: string; a: React.ReactNode }[] = [
  {
    q: "What is Dotphin?",
    a: "A file manager for macOS, written from scratch in SwiftUI and AppKit. Split panes, tabs, a docked terminal and Git status, with shortcuts that follow macOS — built the way a Mac app should behave.",
  },
  {
    q: "Is it free?",
    a: (
      <>
        Yes. Download it from{" "}
        <a className="font-semibold text-accent underline-offset-2 hover:underline" href={site.releases}>
          GitHub releases
        </a>{" "}
        or install it with Homebrew.
      </>
    ),
  },
  {
    q: "Why does macOS say it can't check the app?",
    a: "Dotphin is signed ad hoc and not notarized yet. The Homebrew cask clears the download quarantine for you. If you download the zip yourself, open it once, then allow it under System Settings → Privacy & Security → Open Anyway.",
  },
  {
    q: "Which Macs does it run on?",
    a: `Any Mac on ${site.requirement}.`,
  },
  {
    q: "Where did the idea come from?",
    a: "From KDE's Dolphin, which showed what a file manager can be. Thanks to the Dolphin team for leading the way. Dotphin shares no code with it and isn't affiliated with KDE.",
  },
  {
    q: "Does it collect anything?",
    a: "No account, no analytics. Dotphin doesn't talk to the network at all; it only reads the disks you point it at.",
  },
  {
    q: "Can it open my iPhone or an Android phone?",
    a: "Not today. macOS doesn't expose either one as a regular file system without private APIs, so Dotphin sticks to local disks and external volumes.",
  },
  {
    q: "What about SMB, SFTP or FTP?",
    a: "Network locations aren't supported yet. Local and external drives come first.",
  },
];

export function Faq() {
  return (
    <section id="faq" className="scroll-mt-8 px-4 pt-28 sm:pt-36">
      <div className="mx-auto max-w-[720px]">
        <h2 className="text-[clamp(34px,5vw,48px)] font-bold leading-[1.08] tracking-[-0.03em]">Questions</h2>
        <div className="mt-8">
          {faq.map((f) => (
            <details key={f.q} className="group border-b border-separator">
              <summary className="flex min-h-16 cursor-pointer list-none items-center justify-between gap-6 py-4 text-[18px] font-semibold [&::-webkit-details-marker]:hidden">
                {f.q}
                <span
                  className="relative size-4 shrink-0 text-ink-2 transition-transform duration-[var(--dur-standard)] ease-[var(--ease-out)] group-open:rotate-45"
                  aria-hidden="true"
                >
                  <span className="absolute left-0 top-1/2 h-[1.6px] w-4 -translate-y-1/2 rounded bg-current" />
                  <span className="absolute left-1/2 top-0 h-4 w-[1.6px] -translate-x-1/2 rounded bg-current" />
                </span>
              </summary>
              <p className="pb-6 pr-10 text-[17px] leading-[1.6] text-ink-2">{f.a}</p>
            </details>
          ))}
        </div>
      </div>
    </section>
  );
}
