import Image from "next/image";
import { Icon } from "@/demo/icons";
import { site } from "@/lib/site";
import { CopyCommand } from "./CopyCommand";

export function GetDotphin() {
  return (
    <>
      <section id="get" className="scroll-mt-8 px-4 pt-28 sm:pt-36">
        <div className="mx-auto flex max-w-[1180px] flex-col items-center rounded-[36px] bg-surface px-6 py-16 text-center sm:py-24">
          <Image src="/brand/icon-256.png" alt="" width={88} height={88} />
          <h2 className="mt-8 text-[clamp(40px,7vw,72px)] font-bold leading-[1.02] tracking-[-0.035em]">
            Two panes are better
            <br />
            <span className="text-ink-3">than one.</span>
          </h2>
          <div className="mt-10 flex w-full max-w-[560px] flex-col items-stretch gap-3">
            <CopyCommand command={site.brew} />
            <a
              href={site.releases}
              className="flex h-12 items-center justify-center gap-2 rounded-[14px] bg-accent px-6 text-[16px] font-semibold text-white transition-colors duration-[var(--dur-quick)] hover:bg-accent-hover"
            >
              <Icon.apple size={15} />
              Download {site.version}
            </a>
          </div>
          <p className="mt-4 text-[14px] text-ink-2">Free · {site.requirement}</p>
        </div>
      </section>

      <footer className="px-4 pb-10 pt-20">
        <div className="mx-auto flex max-w-[1080px] flex-col items-center gap-5 text-center">
          <nav aria-label="Footer" className="flex flex-wrap justify-center gap-x-2 text-[15px] text-ink-2">
            {[
              ["GitHub", site.repo],
              ["Releases", site.releases],
              ["Report an issue", site.issues],
            ].map(([label, href]) => (
              <a key={label} href={href} className="flex min-h-11 items-center px-2 transition-colors duration-[var(--dur-quick)] hover:text-ink">
                {label}
              </a>
            ))}
          </nav>
          <p className="max-w-[520px] text-[14px] text-ink-2">
            Mac and macOS are trademarks of Apple Inc.
          </p>
          <a href={site.studio.url} className="flex min-h-11 items-center gap-1.5 text-[15px] text-ink-2 transition-colors hover:text-ink">
            Built by
            <span className="flex items-center gap-1 font-semibold text-ink">
              <span className="size-2 rounded-full bg-ink" aria-hidden="true" />
              fn
            </span>
          </a>
        </div>
      </footer>
    </>
  );
}
