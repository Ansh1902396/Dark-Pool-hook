import { cn } from "@/lib/cn";

const LANG_COLOR: Record<string, string> = {
  solidity: "#a78bfa",
  rust: "#fb923c",
  typescript: "#38bdf8",
  bash: "#5eead4",
};

function isComment(line: string) {
  const t = line.trimStart();
  return t.startsWith("//") || t.startsWith("#");
}

/** Lightweight code plate. Comments dim; no heavy syntax-highlighting dependency. */
export function CodePeek({
  label,
  lang,
  source,
  className,
}: {
  label: string;
  lang: string;
  source: string;
  className?: string;
}) {
  const lines = source.replace(/\n+$/, "").split("\n");

  return (
    <div className={cn("overflow-hidden rounded-xl border border-line bg-[#0c0e12]", className)}>
      <div className="flex items-center justify-between border-b border-line px-4 py-2.5">
        <span className="font-mono text-xs text-faint">{label}</span>
        <span className="flex items-center gap-1.5 font-mono text-[0.7rem] uppercase tracking-wider text-faint">
          <span
            className="h-2 w-2 rounded-full"
            style={{ background: LANG_COLOR[lang] ?? "#5eead4" }}
          />
          {lang}
        </span>
      </div>
      <pre className="overflow-x-auto px-4 py-4 text-[0.8rem] leading-relaxed">
        <code className="font-mono">
          {lines.map((line, i) => (
            <span
              key={i}
              className={cn(
                "block whitespace-pre",
                isComment(line) ? "italic text-faint" : "text-muted",
              )}
            >
              {line || " "}
            </span>
          ))}
        </code>
      </pre>
    </div>
  );
}
