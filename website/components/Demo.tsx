import { ArrowUpRight } from "lucide-react";
import { Section } from "./Section";
import { Reveal } from "./Reveal";
import { demo, site } from "@/content/site";

export function Demo() {
  return (
    <Section
      id="demo"
      index={demo.index}
      label={demo.label}
      heading={demo.heading}
      intro={demo.body}
      grid
    >
      <div className="grid gap-8 lg:grid-cols-[1.6fr_1fr] lg:gap-10">
        <Reveal>
          <div className="overflow-hidden rounded-xl border border-line bg-surface">
            <div className="relative aspect-video w-full">
              <iframe
                src={site.links.loomEmbed}
                title="DarkCoW — architecture & deployment walkthrough"
                allowFullScreen
                className="absolute inset-0 h-full w-full"
              />
            </div>
          </div>
          <a
            href={site.links.loomShare}
            target="_blank"
            rel="noreferrer"
            className="mt-3 inline-flex items-center gap-1.5 font-mono text-xs text-faint transition-colors hover:text-accent"
          >
            watch on loom
            <ArrowUpRight className="h-3.5 w-3.5" />
          </a>
        </Reveal>

        <Reveal delay={0.1}>
          <div className="overflow-hidden rounded-xl border border-line bg-[#0c0e12]">
            <div className="flex items-center gap-1.5 border-b border-line px-4 py-3">
              <span className="h-2.5 w-2.5 rounded-full bg-[#2a2e36]" />
              <span className="h-2.5 w-2.5 rounded-full bg-[#2a2e36]" />
              <span className="h-2.5 w-2.5 rounded-full bg-[#2a2e36]" />
              <span className="ml-2 font-mono text-xs text-faint">run it locally</span>
            </div>
            <div className="space-y-3 px-4 py-5 font-mono text-xs leading-relaxed">
              {demo.runSteps.map((s, i) => (
                <div key={i}>
                  <div className="flex gap-2">
                    <span className="text-accent">$</span>
                    <span className="text-fg">{s.cmd}</span>
                  </div>
                  <div className="pl-4 text-faint"># {s.note}</div>
                </div>
              ))}
            </div>
          </div>
          <p className="mt-3 font-mono text-xs text-faint">
            Full setup in the repo README.
          </p>
        </Reveal>
      </div>
    </Section>
  );
}
