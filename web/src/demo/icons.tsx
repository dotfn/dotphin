// Line icons drawn in the spirit of SF Symbols (1.6 stroke, round caps),
// plus the colored file-type icons the panes use.

import type { SVGProps } from "react";
import type { Kind } from "./fs";

type IconProps = SVGProps<SVGSVGElement> & { size?: number };

function Line({ size = 16, children, ...rest }: IconProps & { children: React.ReactNode }) {
  return (
    <svg
      width={size}
      height={size}
      viewBox="0 0 20 20"
      fill="none"
      stroke="currentColor"
      strokeWidth={1.6}
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
      {...rest}
    >
      {children}
    </svg>
  );
}

export const Icon = {
  chevronLeft: (p: IconProps) => (
    <Line {...p}>
      <path d="M12.5 4.5 7 10l5.5 5.5" />
    </Line>
  ),
  chevronRight: (p: IconProps) => (
    <Line {...p}>
      <path d="M7.5 4.5 13 10l-5.5 5.5" />
    </Line>
  ),
  chevronUp: (p: IconProps) => (
    <Line {...p}>
      <path d="M4.5 12.5 10 7l5.5 5.5" />
    </Line>
  ),
  sidebar: (p: IconProps) => (
    <Line {...p}>
      <rect x="2.5" y="4" width="15" height="12" rx="2.5" />
      <path d="M7.5 4v12" />
    </Line>
  ),
  grid: (p: IconProps) => (
    <Line {...p}>
      <rect x="3" y="3" width="5.5" height="5.5" rx="1.4" />
      <rect x="11.5" y="3" width="5.5" height="5.5" rx="1.4" />
      <rect x="3" y="11.5" width="5.5" height="5.5" rx="1.4" />
      <rect x="11.5" y="11.5" width="5.5" height="5.5" rx="1.4" />
    </Line>
  ),
  compact: (p: IconProps) => (
    <Line {...p}>
      <rect x="2.5" y="4" width="4" height="4" rx="1" />
      <rect x="8" y="4" width="4" height="4" rx="1" />
      <rect x="13.5" y="4" width="4" height="4" rx="1" />
      <rect x="2.5" y="12" width="4" height="4" rx="1" />
      <rect x="8" y="12" width="4" height="4" rx="1" />
      <rect x="13.5" y="12" width="4" height="4" rx="1" />
    </Line>
  ),
  list: (p: IconProps) => (
    <Line {...p}>
      <path d="M7 5.5h10M7 10h10M7 14.5h10" />
      <circle cx="3.6" cy="5.5" r=".6" fill="currentColor" />
      <circle cx="3.6" cy="10" r=".6" fill="currentColor" />
      <circle cx="3.6" cy="14.5" r=".6" fill="currentColor" />
    </Line>
  ),
  table: (p: IconProps) => (
    <Line {...p}>
      <rect x="2.5" y="3.5" width="15" height="13" rx="2" />
      <path d="M2.5 8h15M2.5 12.3h15M8 8v8.5" />
    </Line>
  ),
  split: (p: IconProps) => (
    <Line {...p}>
      <rect x="2.5" y="3.5" width="15" height="13" rx="2.5" />
      <path d="M10 3.5v13" />
    </Line>
  ),
  terminal: (p: IconProps) => (
    <Line {...p}>
      <rect x="2.5" y="3.5" width="15" height="13" rx="2.5" />
      <path d="m6 8 2.5 2L6 12M10.5 12.5H14" />
    </Line>
  ),
  info: (p: IconProps) => (
    <Line {...p}>
      <rect x="2.5" y="3.5" width="15" height="13" rx="2.5" />
      <path d="M12.5 3.5v13" />
    </Line>
  ),
  search: (p: IconProps) => (
    <Line {...p}>
      <circle cx="8.8" cy="8.8" r="5" />
      <path d="m12.6 12.6 4 4" />
    </Line>
  ),
  newFolder: (p: IconProps) => (
    <Line {...p}>
      <path d="M2.5 6.5a2 2 0 0 1 2-2h3l1.6 1.6h6.4a2 2 0 0 1 2 2v6.4a2 2 0 0 1-2 2h-11a2 2 0 0 1-2-2Z" />
      <path d="M10 9v4.5M7.8 11.2h4.4" />
    </Line>
  ),
  trash: (p: IconProps) => (
    <Line {...p}>
      <path d="M4 5.5h12M8 5.5V4h4v1.5M5.5 5.5l.8 10.2a1.5 1.5 0 0 0 1.5 1.3h4.4a1.5 1.5 0 0 0 1.5-1.3l.8-10.2" />
    </Line>
  ),
  share: (p: IconProps) => (
    <Line {...p}>
      <path d="M10 12.5V3M6.8 6 10 2.8 13.2 6M6 8.5H5a1.5 1.5 0 0 0-1.5 1.5v6A1.5 1.5 0 0 0 5 17.5h10a1.5 1.5 0 0 0 1.5-1.5v-6A1.5 1.5 0 0 0 15 8.5h-1" />
    </Line>
  ),
  plus: (p: IconProps) => (
    <Line {...p}>
      <path d="M10 4v12M4 10h12" />
    </Line>
  ),
  close: (p: IconProps) => (
    <Line {...p}>
      <path d="m5.5 5.5 9 9M14.5 5.5l-9 9" />
    </Line>
  ),
  home: (p: IconProps) => (
    <Line {...p}>
      <path d="M3.5 9 10 3.5 16.5 9M5.5 7.5V16h3.5v-4.5h2V16h3.5V7.5" />
    </Line>
  ),
  desktop: (p: IconProps) => (
    <Line {...p}>
      <rect x="2.5" y="3.5" width="15" height="10" rx="1.8" />
      <path d="M7.5 17h5M10 13.5V17" />
    </Line>
  ),
  doc: (p: IconProps) => (
    <Line {...p}>
      <path d="M5 2.8h6.2L15 6.6V16a1.4 1.4 0 0 1-1.4 1.4H5A1.4 1.4 0 0 1 3.6 16V4.2A1.4 1.4 0 0 1 5 2.8Z" />
      <path d="M11 2.8v4h4M6.5 10.5h6M6.5 13.5h4" />
    </Line>
  ),
  download: (p: IconProps) => (
    <Line {...p}>
      <circle cx="10" cy="10" r="7" />
      <path d="M10 6.5v6.5M7.3 10.5 10 13.2l2.7-2.7" />
    </Line>
  ),
  drive: (p: IconProps) => (
    <Line {...p}>
      <rect x="2.5" y="6" width="15" height="8" rx="2" />
      <path d="M13.5 10h.01M11 10h.01" />
    </Line>
  ),
  eject: (p: IconProps) => (
    <Line {...p}>
      <path d="m10 4.5 5 5.5H5Z" />
      <path d="M5 14.5h10" />
    </Line>
  ),
  filter: (p: IconProps) => (
    <Line {...p}>
      <path d="M3.5 5.5h13M6 10h8M8.5 14.5h3" />
    </Line>
  ),
  menu: (p: IconProps) => (
    <Line {...p}>
      <path d="M4 6h12M4 10h12M4 14h12" />
    </Line>
  ),
  copy: (p: IconProps) => (
    <Line {...p}>
      <rect x="6.5" y="6.5" width="10" height="10" rx="2" />
      <path d="M13.5 6.5V5a1.5 1.5 0 0 0-1.5-1.5H5A1.5 1.5 0 0 0 3.5 5v7A1.5 1.5 0 0 0 5 13.5h1.5" />
    </Line>
  ),
  check: (p: IconProps) => (
    <Line {...p}>
      <path d="m4.5 10.5 3.5 3.5 7.5-8" />
    </Line>
  ),
  github: ({ size = 16, ...rest }: IconProps) => (
    <svg width={size} height={size} viewBox="0 0 16 16" fill="currentColor" aria-hidden="true" {...rest}>
      <path d="M8 0C3.58 0 0 3.58 0 8c0 3.54 2.29 6.53 5.47 7.59.4.07.55-.17.55-.38 0-.19-.01-.82-.01-1.49-2.01.37-2.53-.49-2.69-.94-.09-.23-.48-.94-.82-1.13-.28-.15-.68-.52-.01-.53.63-.01 1.08.58 1.23.82.72 1.21 1.87.87 2.33.66.07-.52.28-.87.51-1.07-1.78-.2-3.64-.89-3.64-3.95 0-.87.31-1.59.82-2.15-.08-.2-.36-1.02.08-2.12 0 0 .67-.21 2.2.82.64-.18 1.32-.27 2-.27.68 0 1.36.09 2 .27 1.53-1.04 2.2-.82 2.2-.82.44 1.1.16 1.92.08 2.12.51.56.82 1.27.82 2.15 0 3.07-1.87 3.75-3.65 3.95.29.25.54.73.54 1.48 0 1.07-.01 1.93-.01 2.2 0 .21.15.46.55.38A8.013 8.013 0 0016 8c0-4.42-3.58-8-8-8z" />
    </svg>
  ),
  apple: ({ size = 16, ...rest }: IconProps) => (
    <svg width={size} height={size} viewBox="0 0 17 20" fill="currentColor" aria-hidden="true" {...rest}>
      <path d="M14.1 10.6c0-2.6 2.1-3.8 2.2-3.9-1.2-1.8-3.1-2-3.7-2-1.6-.2-3.1.9-3.9.9-.8 0-2.1-.9-3.4-.9C3.5 4.8 1.9 5.8 1 7.4c-1.9 3.2-.5 8 1.3 10.6.9 1.3 1.9 2.7 3.3 2.6 1.3-.1 1.8-.9 3.4-.9s2 .9 3.4.8c1.4 0 2.3-1.3 3.2-2.6 1-1.5 1.4-2.9 1.4-3-.1 0-2.8-1-2.9-4.3ZM11.5 3c.7-.9 1.2-2 1.1-3.2-1 0-2.3.7-3 1.6-.7.8-1.2 2-1.1 3.1 1.1.1 2.3-.6 3-1.5Z" />
    </svg>
  ),
};

/** macOS-style folder, two-tone blue. */
export function FolderGlyph({ size = 18 }: { size?: number }) {
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" aria-hidden="true">
      <path d="M2 6.2C2 5 3 4 4.2 4h4.6c.6 0 1.1.2 1.5.6L11.8 6H19.8C21 6 22 7 22 8.2V9H2Z" fill="#4aa3ef" />
      <path d="M2 8.6c0-.9.7-1.6 1.6-1.6h16.8c.9 0 1.6.7 1.6 1.6v9.2c0 1.2-1 2.2-2.2 2.2H4.2C3 20 2 19 2 17.8Z" fill="#6cbcf7" />
      <path d="M2 9.4h20" stroke="#ffffff" strokeOpacity=".35" strokeWidth=".8" />
    </svg>
  );
}

const fileTone: Record<Exclude<Kind, "folder">, { label: string; color: string }> = {
  swift: { label: "SWIFT", color: "#f05138" },
  md: { label: "MD", color: "#3d4a57" },
  image: { label: "", color: "" },
  zip: { label: "ZIP", color: "#8a6d3b" },
  pdf: { label: "PDF", color: "#d93a2f" },
  json: { label: "{ }", color: "#7a5cc2" },
  text: { label: "TXT", color: "#6e7781" },
  movie: { label: "", color: "" },
};

/** A page with a folded corner and a colored type label, like Finder's generic icons. */
// Photo thumbnails: a few skies so a grid of pictures doesn't look cloned.
const photoTones = [
  { sky: "#a9e4f2", sky2: "#5cc3dd", land: "#1f8fb3", sun: "#ffb347" },
  { sky: "#ffd9b0", sky2: "#ff9f6e", land: "#7a4a6e", sun: "#fff1c9" },
  { sky: "#c9d6ff", sky2: "#8aa4f0", land: "#3f5a8c", sun: "#ffe08a" },
  { sky: "#d4f0d0", sky2: "#8fd19e", land: "#3d7d55", sun: "#fff6c2" },
];

function hash(s: string) {
  let h = 0;
  for (const c of s) h = (h * 31 + c.charCodeAt(0)) | 0;
  return Math.abs(h);
}

export function FileGlyph({ kind, size = 18, seed = "" }: { kind: Kind; size?: number; seed?: string }) {
  if (kind === "folder") return <FolderGlyph size={size} />;
  if (kind === "image") {
    const t = photoTones[hash(seed) % photoTones.length];
    return (
      <svg width={size} height={size} viewBox="0 0 24 24" aria-hidden="true">
        <rect x="3" y="4" width="18" height="16" rx="2.5" fill="#ffffff" stroke="#c9d1d8" strokeWidth=".8" />
        <rect x="4.6" y="5.6" width="14.8" height="12.8" rx="1.4" fill={t.sky2} />
        <rect x="4.6" y="5.6" width="14.8" height="6" rx="1.4" fill={t.sky} />
        <path d="M4.6 15.5 9 11.6l3.2 2.8 2.6-2 4.6 3.8v.8a1.4 1.4 0 0 1-1.4 1.4H6a1.4 1.4 0 0 1-1.4-1.4Z" fill={t.land} />
        <circle cx="15.8" cy="8.8" r="1.4" fill={t.sun} />
      </svg>
    );
  }
  if (kind === "movie") {
    return (
      <svg width={size} height={size} viewBox="0 0 24 24" aria-hidden="true">
        <rect x="3" y="5" width="18" height="14" rx="2.5" fill="#2b3036" />
        <path d="M10.2 9.2v5.6l4.6-2.8Z" fill="#ffffff" />
      </svg>
    );
  }
  const t = fileTone[kind];
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" aria-hidden="true">
      <path d="M6 2.5h8.2L19 7.3v13a1.2 1.2 0 0 1-1.2 1.2H6a1.2 1.2 0 0 1-1.2-1.2V3.7A1.2 1.2 0 0 1 6 2.5Z" fill="#ffffff" stroke="#c9d1d8" strokeWidth=".8" />
      <path d="M14.2 2.5v3.6c0 .7.5 1.2 1.2 1.2H19" fill="#eef1f4" stroke="#c9d1d8" strokeWidth=".8" />
      <rect x="5.6" y="14" width="12.6" height="5" rx="1" fill={t.color} />
      <text x="11.9" y="17.6" textAnchor="middle" fontSize="3.6" fontWeight="700" fill="#ffffff" fontFamily="-apple-system, system-ui, sans-serif">
        {t.label}
      </text>
    </svg>
  );
}
