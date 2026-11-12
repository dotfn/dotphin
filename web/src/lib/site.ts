// Facts about the product the page states. Keep in sync with the app's
// README and the Homebrew cask — the page never invents a number.

export const site = {
  name: "Dotphin",
  version: "0.1.2-beta",
  download: "Dotphin-0.1.2-beta.zip",
  // Assumed production domain — used for canonical/OG URLs only.
  url: "https://dotphin.dotfn.dev",
  repo: "https://github.com/dotfn/dotphin",
  releases: "https://github.com/dotfn/dotphin/releases/latest",
  issues: "https://github.com/dotfn/dotphin/issues",
  brew: "brew install --cask dotfn/tap/dotphin",
  studio: { name: "dotfn", url: "https://dotfn.dev" },
  requirement: "macOS 27 or later",
} as const;

/** Sections, in page order. The path bar walks this list. */
export const sections = [
  { id: "top", title: "Dotphin", subtitle: "File manager" },
  { id: "features", title: "Features", subtitle: "What it does" },
  { id: "views", title: "Views", subtitle: "Icons, compact, details" },
  { id: "terminal", title: "Terminal", subtitle: "One key away" },
  { id: "shortcuts", title: "Shortcuts", subtitle: "Keyboard first" },
  { id: "compare", title: "Compare", subtitle: "Dotphin and Finder" },
  { id: "faq", title: "Questions", subtitle: "FAQ" },
  { id: "get", title: "Get Dotphin", subtitle: "Free download" },
] as const;

export type SectionId = (typeof sections)[number]["id"];
