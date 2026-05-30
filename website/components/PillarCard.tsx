import type { Pillar } from "@/content/site";
import { Tag } from "./Tag";
import { CodePeek } from "./CodePeek";
import { Reveal } from "./Reveal";

export function PillarCard({ pillar, delay = 0 }: { pillar: Pillar; delay?: number }) {
  return (
    <Reveal delay={delay}>
      <article className="grid gap-8 rounded-2xl border border-line bg-white/[0.015] p-6 md:grid-cols-2 md:gap-10 md:p-9">
        <div>
          <div className="flex items-center gap-3">
            <span className="flex h-8 w-8 items-center justify-center rounded-md border border-line font-mono text-sm text-accent">
              {pillar.marker}
            </span>
            <h3 className="text-xl font-medium tracking-tight text-fg md:text-2xl">
              {pillar.title}
            </h3>
          </div>

          <p className="mt-4 text-pretty leading-relaxed text-muted">{pillar.summary}</p>

          <ul className="mt-5 space-y-2.5">
            {pillar.bullets.map((b) => (
              <li key={b} className="flex gap-3 text-sm leading-relaxed text-muted">
                <span className="mt-2 h-1 w-1 shrink-0 rounded-full bg-accent" />
                {b}
              </li>
            ))}
          </ul>

          <div className="mt-6 flex flex-wrap gap-2">
            {pillar.tags.map((t) => (
              <Tag key={t}>{t}</Tag>
            ))}
          </div>
        </div>

        <div className="md:self-center">
          <CodePeek
            label={pillar.code.label}
            lang={pillar.code.lang}
            source={pillar.code.source}
          />
        </div>
      </article>
    </Reveal>
  );
}
