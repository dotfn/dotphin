// Dotphin next to Finder, feature by feature. Honest in both directions.

import { Icon } from "@/demo/icons";

type Cell = { yes: boolean; note?: string };
const rows: { feature: string; dotphin: Cell; finder: Cell }[] = [
  { feature: "Two folders side by side in one window", dotphin: { yes: true, note: "⌘\\" }, finder: { yes: false } },
  { feature: "Copy or move to the other pane with one shortcut", dotphin: { yes: true, note: "⌃⌘C / ⌃⌘M" }, finder: { yes: false } },
  { feature: "Terminal docked under the files", dotphin: { yes: true, note: "⌃`, follows the folder" }, finder: { yes: false } },
  { feature: "Git status on files and folders", dotphin: { yes: true }, finder: { yes: false } },
  { feature: "Side-by-side file compare", dotphin: { yes: true }, finder: { yes: false } },
  { feature: "Tabs", dotphin: { yes: true }, finder: { yes: true } },
  { feature: "Per-folder view settings", dotphin: { yes: true }, finder: { yes: true } },
  { feature: "Quick Look", dotphin: { yes: true }, finder: { yes: true } },
  { feature: "Notarized by Apple", dotphin: { yes: false, note: "Not yet — signed ad hoc" }, finder: { yes: true } },
  { feature: "Price", dotphin: { yes: true, note: "Free" }, finder: { yes: true, note: "Built into macOS" } },
];

function Mark({ cell }: { cell: Cell }) {
  return (
    <span className="flex items-start gap-2">
      {cell.yes ? (
        <Icon.check size={18} className="mt-[3px] shrink-0 text-[var(--git-added)]" aria-label="Yes" />
      ) : (
        <span className="mt-[11px] h-[2px] w-3 shrink-0 rounded bg-ink-3" role="img" aria-label="No" />
      )}
      {cell.note && <span className="text-ink-2">{cell.note}</span>}
    </span>
  );
}

export function Compare() {
  return (
    <section id="compare" className="scroll-mt-8 px-4 pt-28 sm:pt-36">
      <div className="mx-auto max-w-[920px]">
        <h2 className="text-center text-[clamp(34px,5vw,48px)] font-bold leading-[1.08] tracking-[-0.03em]">Dotphin and Finder</h2>
        <p className="mx-auto mt-5 max-w-[560px] text-center text-[18px] leading-[1.55] text-ink-2">
          Finder is great at being Finder. Dotphin is for the days you&rsquo;re moving a lot of files around, or working in a
          repository.
        </p>

        <div className="mt-12 overflow-x-auto rounded-[24px] bg-surface">
          <table className="w-full text-left text-[15px] sm:text-[16px]">
            <thead>
              <tr className="border-b border-separator text-[14px] text-ink-2">
                <th scope="col" className="px-3 py-4 sm:px-5 font-semibold">
                  Feature
                </th>
                <th scope="col" className="bg-accent-soft/60 px-3 py-4 sm:px-5 font-semibold text-ink">
                  Dotphin
                </th>
                <th scope="col" className="px-3 py-4 sm:px-5 font-semibold">
                  Finder
                </th>
              </tr>
            </thead>
            <tbody>
              {rows.map((r) => (
                <tr key={r.feature} className="border-b border-[var(--separator-soft)] last:border-0">
                  <th scope="row" className="px-3 py-4 sm:px-5 font-semibold">
                    {r.feature}
                  </th>
                  <td className="bg-accent-soft/60 px-3 py-4 sm:px-5">
                    <Mark cell={r.dotphin} />
                  </td>
                  <td className="px-3 py-4 sm:px-5">
                    <Mark cell={r.finder} />
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
        <p className="mt-4 text-center text-[14px] text-ink-2">Finder as it ships in macOS 27.</p>
      </div>
    </section>
  );
}
