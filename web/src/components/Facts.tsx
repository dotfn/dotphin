// Three facts under the hero. The figures are keys, because that's the point.

const facts = [
  { figure: "⌘\\", title: "Split any folder", body: "Two panes in one window, each with its own path and view." },
  { figure: "⌃`", title: "Terminal, docked", body: "A full shell under your files that follows the folder you open." },
  { figure: "0", title: "Accounts", body: "Nothing to sign in to, and nothing sent anywhere." },
];

export function Facts() {
  return (
    <div className="mx-auto mt-16 grid max-w-[960px] gap-10 px-4 text-center sm:mt-20 sm:grid-cols-3 sm:gap-6">
      {facts.map((f) => (
        <div key={f.title} className="flex flex-col items-center">
          <span className="text-[56px] font-bold leading-none tracking-[-0.03em]">{f.figure}</span>
          <span className="mt-3 text-[18px] font-semibold">{f.title}</span>
          <p className="mt-1.5 max-w-[260px] text-[16px] leading-[1.5] text-ink-2">{f.body}</p>
        </div>
      ))}
    </div>
  );
}
