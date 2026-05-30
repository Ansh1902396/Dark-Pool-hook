import { Section } from "./Section";
import { Reveal } from "./Reveal";
import { problem } from "@/content/site";

export function Problem() {
  return (
    <Section
      id="problem"
      index={problem.index}
      label={problem.label}
      heading={problem.heading}
    >
      <div className="grid gap-12 md:grid-cols-[1.3fr_1fr] md:gap-16">
        <Reveal className="space-y-5">
          {problem.body.map((p, i) => (
            <p key={i} className="text-pretty text-lg leading-relaxed text-muted">
              {p}
            </p>
          ))}
        </Reveal>

        <Reveal delay={0.1}>
          <ul className="overflow-hidden rounded-xl border border-line bg-line">
            {problem.points.map((pt, i) => (
              <li
                key={i}
                className="flex items-start gap-3 bg-base px-5 py-4 [&:not(:last-child)]:mb-px"
              >
                <span className="mt-0.5 font-mono text-xs text-accent">
                  {String(i + 1).padStart(2, "0")}
                </span>
                <span className="text-sm leading-relaxed text-fg">{pt}</span>
              </li>
            ))}
          </ul>
        </Reveal>
      </div>
    </Section>
  );
}
