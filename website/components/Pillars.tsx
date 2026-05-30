import { Section } from "./Section";
import { PillarCard } from "./PillarCard";
import { pillars } from "@/content/site";

export function Pillars() {
  return (
    <Section
      id="pillars"
      index={pillars.index}
      label={pillars.label}
      heading={pillars.heading}
    >
      <div className="space-y-6 md:space-y-8">
        {pillars.items.map((p, i) => (
          <PillarCard key={p.id} pillar={p} delay={i * 0.04} />
        ))}
      </div>
    </Section>
  );
}
