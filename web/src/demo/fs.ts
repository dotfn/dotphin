// A small, believable home folder for the demo window.
// Paths use "~" so nothing pretends to be a real user's disk.

export type GitStatus = "modified" | "added" | "untracked" | "deleted";

export type Kind =
  | "folder"
  | "swift"
  | "md"
  | "image"
  | "zip"
  | "pdf"
  | "json"
  | "text"
  | "movie";

export interface Entry {
  name: string;
  kind: Kind;
  /** Display size for files ("12.4 MB"); folders show an item count instead. */
  size?: string;
  items?: number;
  modified: string;
  git?: GitStatus;
}

const folder = (name: string, items: number, modified: string, git?: GitStatus): Entry => ({
  name,
  kind: "folder",
  items,
  modified,
  git,
});

const unsortedFs: Record<string, Entry[]> = {
  "~": [
    folder("Applications", 2, "Oct 25"),
    folder("Desktop", 58, "Today"),
    folder("Developer", 13, "Today"),
    folder("Documents", 21, "Yesterday"),
    folder("Downloads", 34, "Today"),
    folder("Library", 93, "Nov 2"),
    folder("Movies", 8, "Sep 30"),
    folder("Music", 1, "Aug 14"),
    folder("Pictures", 2, "Nov 8"),
  ],
  "~/Developer": [
    folder("dotphin", 11, "Today"),
    folder("homebrew-tap", 3, "Yesterday"),
    folder("playground", 7, "Oct 29"),
    folder("sketches", 24, "Oct 12"),
  ],
  "~/Developer/dotphin": [
    folder(".github", 2, "Nov 10"),
    folder("Sources", 6, "Today", "modified"),
    folder("Tests", 41, "Today", "modified"),
    folder("docs", 3, "Yesterday"),
    folder("scripts", 2, "Nov 10"),
    folder("web", 9, "Today", "untracked"),
    { name: "Package.swift", kind: "swift", size: "1 KB", modified: "Today", git: "modified" },
    { name: "Package.resolved", kind: "json", size: "2 KB", modified: "Nov 11" },
    { name: "README.md", kind: "md", size: "3 KB", modified: "Today", git: "modified" },
    { name: "screenshot.png", kind: "image", size: "161 KB", modified: "Nov 10" },
    { name: ".gitignore", kind: "text", size: "88 bytes", modified: "Oct 26" },
  ],
  "~/Downloads": [
    folder("Screenshots", 46, "Today"),
    { name: "Dotphin-0.1.1-beta.zip", kind: "zip", size: "4.8 MB", modified: "Today" },
    { name: "Q3-report.pdf", kind: "pdf", size: "2.1 MB", modified: "Yesterday" },
    { name: "harbor-dawn.heic", kind: "image", size: "3.4 MB", modified: "Nov 9" },
    { name: "invoice-1042.pdf", kind: "pdf", size: "188 KB", modified: "Nov 7" },
    { name: "keynote-rehearsal.mov", kind: "movie", size: "212 MB", modified: "Nov 3" },
    { name: "notes.md", kind: "md", size: "6 KB", modified: "Oct 30" },
  ],
  "~/Documents": [
    folder("Invoices", 18, "Nov 7"),
    folder("Taxes 2026", 9, "Oct 2"),
    { name: "lease.pdf", kind: "pdf", size: "940 KB", modified: "Sep 1" },
    { name: "packing-list.md", kind: "md", size: "2 KB", modified: "Aug 20" },
  ],
  "~/Pictures": [
    folder("Lisbon 2026", 214, "Oct 18"),
    folder("Screenshots", 46, "Today"),
    { name: "alfama-rooftops.heic", kind: "image", size: "3.1 MB", modified: "Oct 14" },
    { name: "belem-sunset.heic", kind: "image", size: "2.8 MB", modified: "Oct 14" },
    { name: "cais-do-sodre.heic", kind: "image", size: "3.6 MB", modified: "Oct 15" },
    { name: "ferry-wake.mov", kind: "movie", size: "88 MB", modified: "Oct 15" },
    { name: "harbor-dawn.heic", kind: "image", size: "3.4 MB", modified: "Nov 9" },
    { name: "lx-factory.heic", kind: "image", size: "2.2 MB", modified: "Oct 16" },
    { name: "miradouro.heic", kind: "image", size: "4.0 MB", modified: "Oct 16" },
    { name: "pasteis.heic", kind: "image", size: "1.9 MB", modified: "Oct 17" },
    { name: "tram-28.heic", kind: "image", size: "2.6 MB", modified: "Oct 17" },
    { name: "trip-notes.md", kind: "md", size: "4 KB", modified: "Oct 18" },
  ],
  "~/Desktop": [
    { name: "moodboard.png", kind: "image", size: "5.2 MB", modified: "Today" },
    { name: "todo.md", kind: "md", size: "1 KB", modified: "Today" },
  ],
};

/** Folders first, then names the way Finder orders them (case-insensitive). */
export function sortEntries(entries: Entry[]): Entry[] {
  return [...entries].sort((a, b) => {
    if ((a.kind === "folder") !== (b.kind === "folder")) return a.kind === "folder" ? -1 : 1;
    return a.name.localeCompare(b.name, "en", { sensitivity: "base" });
  });
}

export const seedFs: Record<string, Entry[]> = Object.fromEntries(
  Object.entries(unsortedFs).map(([path, entries]) => [path, sortEntries(entries)]),
);

export function displayName(path: string): string {
  if (path === "~") return "Home";
  return path.split("/").pop() ?? path;
}

export function parentOf(path: string): string | null {
  if (path === "~") return null;
  const parts = path.split("/");
  parts.pop();
  return parts.join("/") || "~";
}

/** "~/Developer/dotphin" → ["~", "~/Developer", "~/Developer/dotphin"] */
export function crumbs(path: string): string[] {
  const parts = path.split("/");
  return parts.map((_, i) => parts.slice(0, i + 1).join("/"));
}
