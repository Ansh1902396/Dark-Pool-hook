import { Section } from "./Section";
import { Reveal } from "./Reveal";
import { Figure } from "./Figure";
import { overview } from "@/content/site";

export function Overview() {
  return (
    <Section
      id="overview"
      index={overview.index}
      label={overview.label}
      heading={overview.heading}
      grid
    >
      <div className="grid items-start gap-10 md:gap-14 lg:grid-cols-[1fr_1.25fr]">
        <Reveal className="space-y-5">
          {overview.body.map((p, i) => (
            <p key={i} className="text-pretty text-lg leading-relaxed text-muted">
              {p}
            </p>
          ))}
        </Reveal>

        <Reveal delay={0.1}>
          <Figure
            src={overview.figure.src}
            alt={overview.figure.alt}
            caption={overview.figure.caption}
          />
        </Reveal>
      </div>
    </Section>
  );
}
