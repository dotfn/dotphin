// Features: each card leads with a working fragment of the app, not an icon.

import type { ReactNode } from "react";
import { GitBadge } from "@/demo/DotphinWindow";
import { FileGlyph, Icon } from "@/demo/icons";
import type { Entry } from "@/demo/fs";
import { Kbd } from "./Kbd";

function Card({ title, children, ui, className = "" }: { title: string; children: ReactNode; ui: ReactNode; className?: string }) {
  return (
    <article className={`flex min-w-0 flex-col rounded-[28px] bg-surface p-3 ${className}`}>
      <div className="flex min-h-[200px] items-center justify-center overflow-hidden rounded-[20px] bg-bg-sunk/70 p-4 font-mac text-[13px] text-[var(--mac-ink)] sm:p-5">
        {ui}
      </div>
      <div className="px-3 pb-3 pt-5">
        <h3 className="text-[22px] font-bold leading-tight tracking-[-0.01em]">{title}</h3>
        <p className="mt-2 text-[16px] leading-[1.55] text-ink-2">{children}</p>
      </div>
    </article>
  );
}

function Row({ e, selected, trailing }: { e: Pick<Entry, "name" | "kind" | "git">; selected?: boolean; trailing?: ReactNode }) {
  return (
    <div className={`flex h-[30px] items-center gap-2 rounded-[8px] px-2.5 ${selected ? "bg-[var(--selection)]" : ""}`}>
      <FileGlyph kind={e.kind} size={18} />
      <span className="min-w-0 flex-1 truncate">{e.name}</span>
      {e.git && <GitBadge status={e.git} />}
      {trailing}
    </div>
  );
}

function MiniPane({ title, children, focused }: { title: string; children: ReactNode; focused?: boolean }) {
  return (
    <div className="min-w-0 flex-1 rounded-[14px] bg-white p-1.5 shadow-[0_0_0_1px_rgb(16_24_32/.06)]">
      <div className="flex items-center gap-1.5 px-2 pb-1.5 pt-1 text-[12px] font-semibold">
        <span className={`size-1.5 rounded-full ${focused ? "bg-accent" : "bg-black/20"}`} aria-hidden="true" />
        {title}
      </div>
      {children}
    </div>
  );
}

const SplitUI = (
  <div className="flex w-full max-w-[420px] items-center gap-2">
    <MiniPane title="Downloads" focused>
      <Row e={{ name: "Q3-report.pdf", kind: "pdf" }} selected />
      <Row e={{ name: "notes.md", kind: "md" }} />
    </MiniPane>
    <span className="flex shrink-0 flex-col items-center gap-1 text-[var(--mac-ink-2)]">
      <Icon.chevronRight size={16} className="text-accent" />
    </span>
    <MiniPane title="Invoices">
      <Row e={{ name: "invoice-1042.pdf", kind: "pdf" }} />
      <Row e={{ name: "Q3-report.pdf", kind: "pdf" }} />
    </MiniPane>
  </div>
);

const TabsUI = (
  <div className="w-full max-w-[400px]">
    <div className="flex items-center gap-1.5 rounded-full bg-white/70 p-1 shadow-[0_0_0_1px_rgb(16_24_32/.06)]">
      {["dotphin", "Downloads", "Invoices"].map((t, i) => (
        <span
          key={t}
          className={`flex h-[30px] min-w-0 flex-1 items-center justify-center gap-1.5 truncate rounded-full px-2 text-[12.5px] ${
            i === 2 ? "bg-white font-semibold shadow-[0_0_0_.5px_rgb(16_24_32/.14),0_1px_2px_rgb(16_24_32/.08)]" : "text-[var(--mac-ink-2)]"
          }`}
        >
          <FileGlyph kind="folder" size={14} />
          {t}
        </span>
      ))}
      <span className="flex size-[30px] shrink-0 items-center justify-center rounded-full text-[var(--mac-ink-2)]">
        <Icon.plus size={14} />
      </span>
    </div>
    <div className="mt-3 flex justify-center gap-2 text-[12px] text-[var(--mac-ink-2)]">
      <Kbd>⌘</Kbd>
      <Kbd>⇧</Kbd>
      <Kbd>T</Kbd>
      <span className="self-center">Reopen closed tab</span>
    </div>
  </div>
);

const GitUI = (
  <div className="w-full max-w-[340px] rounded-[14px] bg-white p-1.5 shadow-[0_0_0_1px_rgb(16_24_32/.06)]">
    <Row e={{ name: "Sources", kind: "folder", git: "modified" }} />
    <Row e={{ name: "Package.swift", kind: "swift", git: "modified" }} />
    <Row e={{ name: "CHANGELOG.md", kind: "md", git: "added" }} />
    <Row e={{ name: "web", kind: "folder", git: "untracked" }} />
  </div>
);

const InfoUI = (
  <div className="flex w-full max-w-[380px] items-center gap-4 rounded-[14px] bg-white p-3 shadow-[0_0_0_1px_rgb(16_24_32/.06)]">
    <div
      className="size-[96px] shrink-0 rounded-[10px]"
      style={{ background: "radial-gradient(40% 40% at 70% 80%, #ff8a1f, transparent 70%), linear-gradient(160deg, #9ee0ee, #2aa8cc 55%, #0b6f93)" }}
      aria-hidden="true"
    />
    <dl className="grid min-w-0 flex-1 grid-cols-[auto_1fr] gap-x-3 gap-y-1 text-[12px]">
      <dt className="col-span-2 mb-1 truncate text-[13px] font-semibold">harbor-dawn.heic</dt>
      <dt className="text-[var(--mac-ink-2)]">Kind</dt>
      <dd>HEIC image</dd>
      <dt className="text-[var(--mac-ink-2)]">Size</dt>
      <dd className="tabular">3.4 MB</dd>
      <dt className="text-[var(--mac-ink-2)]">Dimensions</dt>
      <dd className="tabular">4032 × 3024</dd>
      <dt className="text-[var(--mac-ink-2)]">Created</dt>
      <dd>Nov 9, 7:12 AM</dd>
    </dl>
  </div>
);

const FilterUI = (
  <div className="w-full max-w-[340px]">
    <div className="mb-2 flex h-[32px] items-center gap-2 rounded-[10px] bg-white px-2.5 shadow-[0_0_0_1px_rgb(16_24_32/.08)]">
      <Icon.filter size={14} className="text-[var(--mac-ink-2)]" />
      <span>
        pdf<span className="ml-px inline-block h-[13px] w-px translate-y-[2px] bg-accent" />
      </span>
      <span className="ml-auto text-[12px] text-[var(--mac-ink-2)]">2 of 7</span>
    </div>
    <div className="rounded-[14px] bg-white p-1.5 shadow-[0_0_0_1px_rgb(16_24_32/.06)]">
      <Row e={{ name: "Q3-report.pdf", kind: "pdf" }} />
      <Row e={{ name: "invoice-1042.pdf", kind: "pdf" }} />
    </div>
  </div>
);

const PlacesUI = (
  <div className="w-full max-w-[300px] rounded-[14px] bg-[rgb(236_241_244)] p-2 shadow-[0_0_0_1px_rgb(16_24_32/.06)]">
    <div className="px-2 pb-1 pt-1 text-[12px] font-semibold text-[var(--mac-ink-2)]">Devices</div>
    {[
      { name: "Macintosh HD", eject: false },
      { name: "Photos SSD", eject: true },
    ].map((d) => (
      <div key={d.name} className="flex h-[30px] items-center gap-2 rounded-[8px] px-2">
        <Icon.drive size={16} className="text-accent" />
        <span className="flex-1">{d.name}</span>
        {d.eject && <Icon.eject size={14} className="text-[var(--mac-ink-2)]" />}
      </div>
    ))}
    <div className="px-2 pb-1 pt-2 text-[12px] font-semibold text-[var(--mac-ink-2)]">Places</div>
    <div className="flex h-[30px] items-center gap-2 rounded-[8px] bg-black/[.07] px-2">
      <Icon.trash size={16} className="text-accent" />
      <span className="flex-1">Trash</span>
      <span className="tabular text-[12px] text-[var(--mac-ink)]">12 items</span>
    </div>
  </div>
);

const details = [
  ["Batch rename", "Rename a whole selection with one pattern."],
  ["Undo", "File operations go into the window's history, so ⌘Z takes them back."],
  ["Compare files", "Two selected files, diffed side by side."],
  ["Disk usage", "See what's filling a folder with ⌘U."],
  ["Per-folder views", "Sort, grouping and zoom are remembered per folder."],
  ["Permissions", "Owner, group and others as switches, applied recursively if you want."],
  ["Templates", "New files from anything you keep in ~/Templates."],
  ["Disk images", "Mount an image straight from the menu."],
  ["Spring-loaded folders", "Hover while dragging and the folder opens under you."],
] as const;

export function Features() {
  return (
    <section id="features" className="scroll-mt-8 px-4 pt-28 sm:pt-36">
      <div className="mx-auto max-w-[1080px]">
        <h2 className="max-w-[640px] text-[clamp(34px,5vw,52px)] font-bold leading-[1.06] tracking-[-0.03em]">
          Built around how you actually move files.
        </h2>
        <p className="mt-5 max-w-[560px] text-[18px] leading-[1.55] text-ink-2">
          Two places at once, a terminal when you need one, and the state of every file in plain sight.
        </p>

        <div className="mt-12 grid gap-4 md:grid-cols-2">
          <Card title="Split view" ui={SplitUI}>
            <Kbd>⌘\</Kbd> opens a second pane. <Kbd>⌃⌘C</Kbd> copies the selection across, <Kbd>⌃⌘M</Kbd> moves it. Dragging works
            too — between panes and with Finder.
          </Card>
          <Card title="Tabs" ui={TabsUI}>
            Every tab keeps its own panes, history and view. Close one by mistake and it comes right back.
          </Card>
          <Card title="Git status" ui={GitUI}>
            Inside a repository, files show whether they&rsquo;re modified, added or untracked. Stage and commit without leaving the
            folder.
          </Card>
          <Card title="Info panel" ui={InfoUI}>
            <Kbd>⌥⌘I</Kbd> shows a Quick Look preview and the metadata that matters for whatever is selected.
          </Card>
          <Card title="Filter as you type" ui={FilterUI}>
            <Kbd>⌘/</Kbd> narrows the folder you&rsquo;re in. Search goes deeper — by name, content, size or type.
          </Card>
          <Card title="Drives and Trash" ui={PlacesUI}>
            External drives show up and eject from the sidebar. Trash is a folder you can browse, not a black hole.
          </Card>
        </div>

        <div className="mt-20 border-t border-separator pt-10">
          <h3 className="text-[22px] font-bold">And the parts you notice later</h3>
          <dl className="mt-8 grid gap-x-10 gap-y-7 sm:grid-cols-2 lg:grid-cols-3">
            {details.map(([t, d]) => (
              <div key={t}>
                <dt className="text-[17px] font-semibold">{t}</dt>
                <dd className="mt-1 text-[16px] leading-[1.5] text-ink-2">{d}</dd>
              </div>
            ))}
          </dl>
        </div>
      </div>
    </section>
  );
}
