// The demo window is a pure function of DemoState. Today a scripted player
// dispatches these actions; the interactive version will dispatch the same
// actions from real clicks and keys — the views don't change.

import { seedFs, parentOf, sortEntries, type Entry } from "./fs";

export type ViewMode = "icons" | "compact" | "details";

export interface PaneState {
  path: string;
  selection: string[];
  viewMode: ViewMode;
  filter: string;
  /** Names that just landed here, for the arrival highlight. */
  arrived: string[];
}

export type TermSpan = { text: string; tone?: "dim" | "green" | "blue" | "yellow" | "red" | "bold" };
export type TermLine = TermSpan[];

export interface TerminalState {
  open: boolean;
  lines: TermLine[];
  input: string;
}

export interface DemoState {
  fs: Record<string, Entry[]>;
  tabs: string[];
  activeTab: number;
  panes: [PaneState, PaneState];
  split: boolean;
  focused: 0 | 1;
  terminal: TerminalState;
  infoPanel: boolean;
}

export type PaneIndex = 0 | 1;

export type Action =
  | { type: "navigate"; pane: PaneIndex; path: string }
  | { type: "up"; pane: PaneIndex }
  | { type: "select"; pane: PaneIndex; names: string[] }
  | { type: "focus"; pane: PaneIndex }
  | { type: "toggleSplit" }
  | { type: "setViewMode"; pane: PaneIndex; mode: ViewMode }
  | { type: "setFilter"; pane: PaneIndex; text: string }
  | { type: "transferToOther"; mode: "copy" | "move" }
  | { type: "toggleTerminal" }
  | { type: "toggleInfo" }
  | { type: "termInput"; text: string }
  | { type: "termRun" }
  | { type: "reset"; state: DemoState };

export function pane(path: string, viewMode: ViewMode = "details"): PaneState {
  return { path, selection: [], viewMode, filter: "", arrived: [] };
}

export function initialState(overrides: Partial<DemoState> = {}): DemoState {
  return {
    fs: seedFs,
    tabs: ["dotphin", "Downloads"],
    activeTab: 0,
    panes: [pane("~/Developer/dotphin"), pane("~/Downloads")],
    split: true,
    focused: 0,
    terminal: { open: false, lines: [], input: "" },
    infoPanel: false,
    ...overrides,
  };
}

/** Entries a pane shows: the folder's contents, narrowed by the filter bar. */
export function visibleEntries(state: DemoState, p: PaneState): Entry[] {
  const all = state.fs[p.path] ?? [];
  const q = p.filter.trim().toLowerCase();
  return q ? all.filter((e) => e.name.toLowerCase().includes(q)) : all;
}

function withPane(state: DemoState, i: PaneIndex, patch: Partial<PaneState>): DemoState {
  const panes = [...state.panes] as DemoState["panes"];
  panes[i] = { ...panes[i], ...patch };
  return { ...state, panes };
}

export function reduce(state: DemoState, action: Action): DemoState {
  switch (action.type) {
    case "navigate":
      if (!state.fs[action.path]) return state;
      return withPane(state, action.pane, { path: action.path, selection: [], filter: "", arrived: [] });

    case "up": {
      const parent = parentOf(state.panes[action.pane].path);
      return parent ? reduce(state, { type: "navigate", pane: action.pane, path: parent }) : state;
    }

    case "select":
      return { ...withPane(state, action.pane, { selection: action.names }), focused: action.pane };

    case "focus":
      return { ...state, focused: action.pane };

    case "toggleSplit":
      return { ...state, split: !state.split, focused: state.split ? 0 : state.focused };

    case "setViewMode":
      return withPane(state, action.pane, { viewMode: action.mode });

    case "setFilter":
      return withPane(state, action.pane, { filter: action.text });

    case "transferToOther": {
      // ⌃⌘C copies, ⌃⌘M moves the selection to the other split pane.
      if (!state.split) return state;
      const from = state.focused;
      const to: PaneIndex = from === 0 ? 1 : 0;
      const src = state.panes[from];
      const dst = state.panes[to];
      if (src.path === dst.path || src.selection.length === 0) return state;

      const srcEntries = state.fs[src.path] ?? [];
      const dstEntries = state.fs[dst.path] ?? [];
      const picked = srcEntries.filter((e) => src.selection.includes(e.name));
      const dstNames = new Set(dstEntries.map((e) => e.name));
      const landed = picked
        .filter((e) => !dstNames.has(e.name))
        .map((e) => ({ ...e, modified: "Now", git: dst.path.startsWith("~/Developer/dotphin") ? ("untracked" as const) : undefined }));

      const fs = { ...state.fs, [dst.path]: sortEntries([...dstEntries, ...landed]) };
      if (action.mode === "move") {
        fs[src.path] = srcEntries.filter((e) => !src.selection.includes(e.name));
      }
      let next: DemoState = { ...state, fs };
      next = withPane(next, to, { arrived: landed.map((e) => e.name), selection: landed.map((e) => e.name) });
      if (action.mode === "move") next = withPane(next, from, { selection: [] });
      return next;
    }

    case "toggleTerminal":
      return { ...state, terminal: { ...state.terminal, open: !state.terminal.open } };

    case "toggleInfo":
      return { ...state, infoPanel: !state.infoPanel };

    case "termInput":
      return { ...state, terminal: { ...state.terminal, input: action.text } };

    case "termRun": {
      const cwd = state.panes[state.focused].path;
      const cmd = state.terminal.input.trim();
      const prompt: TermLine = [
        { text: cwd.replace("~/Developer/", ""), tone: "blue" },
        { text: " % ", tone: "dim" },
        { text: cmd },
      ];
      const out = runCommand(state, cmd, cwd);
      return { ...state, terminal: { ...state.terminal, input: "", lines: [...state.terminal.lines, prompt, ...out] } };
    }

    case "reset":
      return action.state;
  }
}

// A deliberately tiny shell: enough for the commands the demo script types.
function runCommand(state: DemoState, cmd: string, cwd: string): TermLine[] {
  const entries = state.fs[cwd] ?? [];
  if (cmd === "ls") {
    return [entries.map((e) => ({ text: e.name + "  ", tone: e.kind === "folder" ? ("blue" as const) : undefined }))];
  }
  if (cmd === "pwd") return [[{ text: cwd.replace("~", "/Users/you") }]];
  if (cmd.startsWith("git status")) {
    const changed = entries.filter((e) => e.git);
    if (changed.length === 0) return [[{ text: "nothing to commit, working tree clean", tone: "dim" }]];
    return changed.map((e) => {
      const code = e.git === "modified" ? " M" : e.git === "added" ? "A " : e.git === "deleted" ? " D" : "??";
      const tone = e.git === "untracked" ? ("red" as const) : e.git === "added" ? ("green" as const) : ("yellow" as const);
      return [{ text: code + " ", tone }, { text: e.name + (e.kind === "folder" ? "/" : "") }];
    });
  }
  if (cmd.startsWith("git log")) {
    return [
      [{ text: "9471a4a ", tone: "yellow" }, { text: "fix: show the info panel as a native inspector" }],
      [{ text: "32b4cd7 ", tone: "yellow" }, { text: "docs: log the conflict and column order fixes" }],
      [{ text: "64269ae ", tone: "yellow" }, { text: "fix: stop a transfer waiting on a conflict" }],
    ];
  }
  if (cmd === "") return [];
  return [[{ text: `zsh: command not found: ${cmd.split(" ")[0]}`, tone: "red" }]];
}
