import { Section } from "./Section";
import { Reveal } from "./Reveal";
import { skills } from "@/content/site";

export function Skills() {
  return (
    <Section
      id="skills"
      index={skills.index}
      label={skills.label}
      heading={skills.heading}
      grid
    >
      <div className="grid gap-px overflow-hidden rounded-2xl border border-line bg-line sm:grid-cols-2">
        {skills.groups.map((group, gi) => (
          <Reveal key={group.title} delay={gi * 0.05} className="bg-base p-6 md:p-8">
            <h3 className="tracking-label font-mono text-xs uppercase text-accent">
              {group.title}
            </h3>
            <ul className="mt-5 space-y-4">
              {group.items.map((item) => (
                <li key={item.label}>
                  <div className="text-fg">{item.label}</div>
                  <div className="text-sm text-faint">{item.note}</div>
                </li>
              ))}
            </ul>
          </Reveal>
        ))}
      </div>
    </Section>
  );
}
