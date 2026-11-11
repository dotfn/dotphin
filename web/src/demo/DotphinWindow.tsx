// The Dotphin main window, drawn in HTML. Renders DemoState and nothing else.
// `dispatch` is optional: without it the window is a picture; with it, the
// same controls become live (the future interactive playground).

import type { CSSProperties, ReactNode } from "react";
import { crumbs, displayName, type Entry } from "./fs";
import { FileGlyph, Icon } from "./icons";
import { visibleEntries, type Action, type DemoState, type PaneIndex, type PaneState } from "./state";
import { Terminal } from "./Terminal";

type Dispatch = (a: Action) => void;

export const WINDOW_SIZE = { width: 1120, height: 690 } as const;

export function DotphinWindow({
  state,
  dispatch,
  height = WINDOW_SIZE.height,
  style,
}: {
  state: DemoState;
  dispatch?: Dispatch;
  height?: number;
  style?: CSSProperties;
}) {
  return (
    <div
      className="relative flex flex-col overflow-hidden font-mac text-[13px] leading-[1.35] text-[var(--mac-ink)]"
      style={{
        width: WINDOW_SIZE.width,
        height,
        borderRadius: 22,
        background: "rgb(248 250 251 / 0.86)",
        backdropFilter: "blur(30px) saturate(180%)",
        WebkitBackdropFilter: "blur(30px) saturate(180%)",
        boxShadow: "inset 0 0 0 1px rgb(255 255 255 / .7), 0 0 0 1px rgb(10 30 45 / .12), var(--shadow-window)",
        ...style,
      }}
      role={dispatch ? "application" : "img"}
      aria-label={describe(state)}
    >
      <div className="flex min-h-0 flex-1">
        <Sidebar state={state} dispatch={dispatch} />
        <div className="flex min-w-0 flex-1 flex-col">
          <Toolbar state={state} />
          <TabBar state={state} />
          <div className="flex min-h-0 flex-1 flex-col">
            <div className="flex min-h-0 flex-1">
              <Pane state={state} index={0} dispatch={dispatch} />
              {state.split && (
                <>
                  <div className="w-px bg-[rgb(16_24_32/0.1)]" />
                  <Pane state={state} index={1} dispatch={dispatch} />
                </>
              )}
            </div>
            {state.terminal.open && <Terminal state={state} />}
          </div>
          <StatusBar state={state} />
        </div>
      </div>
    </div>
  );
}

/** One sentence for screen readers, since the window itself is decorative. */
function describe(state: DemoState): string {
  const [a, b] = state.panes;
  const panes = state.split ? `two panes showing ${displayName(a.path)} and ${displayName(b.path)}` : `one pane showing ${displayName(a.path)}`;
  return `Dotphin window with ${panes}${state.terminal.open ? " and the embedded terminal open" : ""}.`;
}

function Sidebar({ state, dispatch }: { state: DemoState; dispatch?: Dispatch }) {
  const current = state.panes[state.focused].path;
  const places: { label: string; path: string; icon: ReactNode }[] = [
    { label: "Home", path: "~", icon: <Icon.home size={15} /> },
    { label: "Desktop", path: "~/Desktop", icon: <Icon.desktop size={15} /> },
    { label: "Documents", path: "~/Documents", icon: <Icon.doc size={15} /> },
    { label: "Downloads", path: "~/Downloads", icon: <Icon.download size={15} /> },
    { label: "Pictures", path: "~/Pictures", icon: <Icon.grid size={15} /> },
    { label: "Developer", path: "~/Developer", icon: <Icon.terminal size={15} /> },
  ];
  return (
    <aside
      className="flex w-[196px] shrink-0 flex-col gap-0.5 px-2.5 pb-3 pt-[52px]"
      style={{ background: "rgb(236 241 244 / 0.7)", boxShadow: "inset -1px 0 0 rgb(16 24 32 / .08)" }}
    >
      <TrafficLights />
      <SideHeading>Places</SideHeading>
      {places.map((p) => (
        <SideRow
          key={p.path}
          active={current === p.path}
          icon={p.icon}
          onClick={dispatch ? () => dispatch({ type: "navigate", pane: state.focused, path: p.path }) : undefined}
        >
          {p.label}
        </SideRow>
      ))}
      <SideRow icon={<Icon.trash size={15} />}>Trash</SideRow>
      <SideHeading>Devices</SideHeading>
      <SideRow icon={<Icon.drive size={15} />}>Macintosh HD</SideRow>
      <SideRow icon={<Icon.drive size={15} />} trailing={<Icon.eject size={13} className="text-[var(--mac-ink-2)]" />}>
        Photos SSD
      </SideRow>
      <SideHeading>Folders</SideHeading>
      <div className="flex items-center gap-1.5 rounded-md px-2 py-[3px] text-[var(--mac-ink)]">
        <Icon.chevronRight size={10} className="text-[var(--mac-ink-3)]" />
        <FileGlyph kind="folder" size={15} />
        <span className="font-medium">you</span>
      </div>
    </aside>
  );
}

function TrafficLights() {
  return (
    <div className="absolute left-[18px] top-[18px] flex gap-2" aria-hidden="true">
      {["#ff5f57", "#febc2e", "#28c840"].map((c) => (
        <span key={c} className="size-3 rounded-full" style={{ background: c, boxShadow: "inset 0 0 0 .5px rgb(0 0 0 / .15)" }} />
      ))}
    </div>
  );
}

function SideHeading({ children }: { children: ReactNode }) {
  return <div className="mt-3 px-2 pb-1 text-[12px] font-semibold text-[var(--mac-ink-2)]">{children}</div>;
}

function SideRow({
  children,
  icon,
  active,
  trailing,
  onClick,
}: {
  children: ReactNode;
  icon: ReactNode;
  active?: boolean;
  trailing?: ReactNode;
  onClick?: () => void;
}) {
  const Tag = onClick ? "button" : "div";
  return (
    <Tag
      onClick={onClick}
      className="flex w-full items-center gap-2 rounded-[7px] px-2 py-[4px] text-left"
      style={{ background: active ? "rgb(16 24 32 / .08)" : undefined }}
    >
      <span className="text-[var(--accent)]">{icon}</span>
      <span className="flex-1 truncate">{children}</span>
      {trailing}
    </Tag>
  );
}

function ToolGroup({ children }: { children: ReactNode }) {
  return (
    <div
      className="flex h-[30px] items-center gap-0.5 rounded-full px-1.5 text-[var(--mac-ink)]"
      style={{ background: "rgb(255 255 255 / .75)", boxShadow: "0 0 0 .5px rgb(16 24 32 / .12), 0 1px 2px rgb(16 24 32 / .06)" }}
    >
      {children}
    </div>
  );
}

function ToolButton({ children, on }: { children: ReactNode; on?: boolean }) {
  return (
    <span
      className="flex h-[24px] min-w-[26px] items-center justify-center rounded-full px-1"
      style={{ background: on ? "rgb(16 24 32 / .09)" : undefined }}
    >
      {children}
    </span>
  );
}

function Toolbar({ state }: { state: DemoState }) {
  const mode = state.panes[state.focused].viewMode;
  return (
    <div className="flex h-[52px] shrink-0 items-center gap-2 px-3" aria-hidden="true">
      <ToolGroup>
        <ToolButton>
          <Icon.chevronLeft size={15} />
        </ToolButton>
        <ToolButton>
          <Icon.chevronRight size={15} className="opacity-40" />
        </ToolButton>
        <ToolButton>
          <Icon.chevronUp size={15} />
        </ToolButton>
      </ToolGroup>
      <ToolGroup>
        <ToolButton on={mode === "icons"}>
          <Icon.grid size={15} />
        </ToolButton>
        <ToolButton on={mode === "compact"}>
          <Icon.compact size={15} />
        </ToolButton>
        <ToolButton on={mode === "details"}>
          <Icon.table size={15} />
        </ToolButton>
      </ToolGroup>
      <ToolGroup>
        <ToolButton>
          <Icon.newFolder size={15} />
        </ToolButton>
        <ToolButton>
          <Icon.trash size={15} />
        </ToolButton>
        <ToolButton>
          <Icon.share size={15} />
        </ToolButton>
      </ToolGroup>
      <ToolGroup>
        <ToolButton on={state.split}>
          <Icon.split size={15} />
        </ToolButton>
        <ToolButton on={state.terminal.open}>
          <Icon.terminal size={15} />
        </ToolButton>
        <ToolButton on={state.infoPanel}>
          <Icon.info size={15} />
        </ToolButton>
      </ToolGroup>
      <div
        className="ml-auto flex h-[30px] w-[210px] items-center gap-2 rounded-full px-3 text-[var(--mac-ink-2)]"
        style={{ background: "rgb(255 255 255 / .75)", boxShadow: "0 0 0 .5px rgb(16 24 32 / .12)" }}
      >
        <Icon.search size={14} />
        <span>{state.panes[state.focused].filter || "Search or filter…"}</span>
      </div>
    </div>
  );
}

function TabBar({ state }: { state: DemoState }) {
  return (
    <div className="flex h-[34px] shrink-0 items-center gap-1.5 px-3 pb-1" aria-hidden="true">
      {state.tabs.map((t, i) => (
        <div
          key={t}
          className="flex h-[26px] flex-1 items-center justify-center gap-1.5 rounded-full text-[12px]"
          style={
            i === state.activeTab
              ? { background: "rgb(255 255 255 / .9)", boxShadow: "0 0 0 .5px rgb(16 24 32 / .12), 0 1px 2px rgb(16 24 32 / .06)", fontWeight: 600 }
              : { background: "rgb(16 24 32 / .04)", color: "var(--mac-ink-2)" }
          }
        >
          <FileGlyph kind="folder" size={13} />
          {t}
        </div>
      ))}
      <span className="flex size-[26px] items-center justify-center rounded-full text-[var(--mac-ink-2)]" style={{ background: "rgb(16 24 32 / .04)" }}>
        <Icon.plus size={13} />
      </span>
    </div>
  );
}

function Pane({ state, index, dispatch }: { state: DemoState; index: PaneIndex; dispatch?: Dispatch }) {
  const p = state.panes[index];
  const focused = state.focused === index;
  const entries = visibleEntries(state, p);
  return (
    <section
      className="flex min-w-0 flex-1 flex-col"
      style={{ background: "rgb(255 255 255 / .55)" }}
      onClick={dispatch ? () => dispatch({ type: "focus", pane: index }) : undefined}
      aria-label={`${displayName(p.path)} pane`}
    >
      <Breadcrumb path={p.path} focused={focused && state.split} />
      {p.viewMode === "details" && <DetailsView pane={p} entries={entries} />}
      {p.viewMode === "compact" && <CompactView pane={p} entries={entries} />}
      {p.viewMode === "icons" && <IconsView pane={p} entries={entries} />}
    </section>
  );
}

export function Breadcrumb({ path, focused }: { path: string; focused?: boolean }) {
  return (
    <div className="flex h-[32px] shrink-0 items-center gap-1 border-b border-[rgb(16_24_32/0.07)] px-3 text-[12.5px]">
      <span
        className="mr-1 size-[7px] rounded-full transition-colors"
        style={{ background: focused ? "var(--accent)" : "rgb(16 24 32 / .2)" }}
        aria-hidden="true"
      />
      <span className="flex items-center gap-1 text-[var(--mac-ink-2)]">
        <Icon.drive size={13} /> Macintosh HD
      </span>
      {crumbs(path).map((c, i, all) => (
        <span key={c} className="flex items-center gap-1">
          <Icon.chevronRight size={10} className="text-[var(--mac-ink-3)]" />
          <span className={i === all.length - 1 ? "font-semibold text-[var(--mac-ink)]" : "text-[var(--mac-ink-2)]"}>
            {c === "~" ? "you" : displayName(c)}
          </span>
        </span>
      ))}
    </div>
  );
}

function rowStyle(pane: PaneState, e: Entry): CSSProperties {
  const selected = pane.selection.includes(e.name);
  const arrived = pane.arrived.includes(e.name);
  return {
    background: selected ? "var(--selection)" : undefined,
    animation: arrived ? "row-arrive 900ms var(--ease-out)" : undefined,
  };
}

export function GitBadge({ status }: { status?: Entry["git"] }) {
  if (!status) return null;
  const map = {
    modified: { letter: "M", color: "var(--git-modified)", label: "Modified" },
    added: { letter: "A", color: "var(--git-added)", label: "Added" },
    untracked: { letter: "?", color: "var(--git-untracked)", label: "Untracked" },
    deleted: { letter: "D", color: "var(--git-deleted)", label: "Deleted" },
  } as const;
  const s = map[status];
  return (
    <span
      title={s.label}
      className="inline-flex h-[17px] min-w-[17px] items-center justify-center rounded-[5px] px-[3px] text-[12px] font-bold leading-none text-white"
      style={{ background: s.color }}
    >
      <span className="sr-only">{s.label}: </span>
      {s.letter}
    </span>
  );
}

function sizeLabel(e: Entry) {
  return e.kind === "folder" ? `${e.items} ${e.items === 1 ? "item" : "items"}` : e.size;
}

function DetailsView({ pane, entries }: { pane: PaneState; entries: Entry[] }) {
  return (
    <div className="min-h-0 flex-1 overflow-hidden px-1.5 pt-1">
      <div className="grid grid-cols-[1fr_84px_82px] px-2.5 py-1 text-[12px] font-medium text-[var(--mac-ink-2)]">
        <span>Name</span>
        <span className="text-right">Size</span>
        <span className="pl-4">Modified</span>
      </div>
      {entries.map((e, i) => (
        <div
          key={e.name}
          className="grid h-[25px] grid-cols-[1fr_84px_82px] items-center rounded-[6px] px-2.5"
          style={{ ...(i % 2 === 1 ? { background: "rgb(16 24 32 / .025)" } : {}), ...rowStyle(pane, e) }}
        >
          <span className="flex min-w-0 items-center gap-2">
            <FileGlyph seed={e.name} kind={e.kind} size={17} />
            <span className="truncate">{e.name}</span>
            <GitBadge status={e.git} />
          </span>
          <span className="tabular text-right text-[12px] text-[var(--mac-ink-2)]">{sizeLabel(e)}</span>
          <span className="pl-4 text-[12px] text-[var(--mac-ink-2)]">{e.modified}</span>
        </div>
      ))}
    </div>
  );
}

function CompactView({ pane, entries }: { pane: PaneState; entries: Entry[] }) {
  return (
    <div className="grid min-h-0 flex-1 auto-rows-[28px] grid-cols-2 content-start gap-x-2 overflow-hidden p-2">
      {entries.map((e) => (
        <div key={e.name} className="flex min-w-0 items-center gap-2 rounded-[6px] px-2" style={rowStyle(pane, e)}>
          <FileGlyph seed={e.name} kind={e.kind} size={18} />
          <span className="truncate">{e.name}</span>
          <GitBadge status={e.git} />
        </div>
      ))}
    </div>
  );
}

function IconsView({ pane, entries }: { pane: PaneState; entries: Entry[] }) {
  return (
    <div className="grid min-h-0 flex-1 grid-cols-[repeat(auto-fill,minmax(92px,1fr))] content-start gap-1 overflow-hidden p-3">
      {entries.map((e) => (
        <div key={e.name} className="flex flex-col items-center gap-1 rounded-[10px] px-1 py-2 text-center" style={rowStyle(pane, e)}>
          <span className="relative">
            <FileGlyph seed={e.name} kind={e.kind} size={46} />
            {e.git && (
              <span className="absolute -bottom-0.5 -right-1">
                <GitBadge status={e.git} />
              </span>
            )}
          </span>
          <span className="line-clamp-2 w-full break-all text-[12px] leading-tight">{e.name}</span>
        </div>
      ))}
    </div>
  );
}

function StatusBar({ state }: { state: DemoState }) {
  const p = state.panes[state.focused];
  const entries = visibleEntries(state, p);
  const sel = entries.filter((e) => p.selection.includes(e.name));
  const summary =
    sel.length === 1
      ? `“${sel[0].name}” (${sel[0].kind === "folder" ? "Folder" : sel[0].size})`
      : sel.length > 1
        ? `${sel.length} selected`
        : `${entries.length} items`;
  return (
    <div
      className="flex h-[30px] shrink-0 items-center gap-3 border-t border-[rgb(16_24_32/0.08)] px-3 text-[12px] text-[var(--mac-ink-2)]"
      aria-hidden="true"
    >
      <span>{summary}</span>
      <span className="ml-auto flex items-center gap-2">
        <span className="relative h-[3px] w-[70px] rounded-full bg-[rgb(16_24_32/0.14)]">
          <span className="absolute left-[44%] top-1/2 size-[11px] -translate-y-1/2 rounded-full bg-white shadow-[0_0_0_.5px_rgb(16_24_32/.2),0_1px_2px_rgb(16_24_32/.2)]" />
        </span>
        <span className="tabular">100%</span>
      </span>
      <span className="tabular">182.4 GB available</span>
    </div>
  );
}
