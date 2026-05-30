import { ArrowUpRight, Play } from "lucide-react";
import { hero, site } from "@/content/site";
import { Reveal } from "./Reveal";
import { Tag } from "./Tag";

export function Hero() {
  return (
    <section
      id="top"
      className="relative flex min-h-[100svh] items-center overflow-hidden pt-16"
    >
      <div
        aria-hidden
        className="depth-grid pointer-events-none absolute inset-0 opacity-60"
      />
      <div className="shell relative w-full py-20">
        <Reveal immediate>
          <a
            href={site.links.uhi}
            target="_blank"
            rel="noreferrer"
            className="inline-flex items-center gap-2 rounded-full border border-line bg-white/[0.02] px-3.5 py-1.5 font-mono text-xs text-muted transition-colors hover:border-accent/40 hover:text-fg"
          >
            <span className="h-1.5 w-1.5 rounded-full bg-accent" />
            {hero.kicker}
            <ArrowUpRight className="h-3.5 w-3.5" />
          </a>
        </Reveal>

        <Reveal immediate delay={0.08}>
          <h1 className="mt-7 max-w-4xl text-balance text-5xl font-medium leading-[1.02] tracking-tight text-fg sm:text-6xl md:text-7xl">
            <span className="text-surface-glow text-accent">{hero.titleLead}</span>{" "}
            {hero.titleRest}
          </h1>
        </Reveal>

        <Reveal immediate delay={0.16}>
          <p className="mt-6 max-w-2xl text-pretty text-lg leading-relaxed text-muted md:text-xl">
            {hero.subtitle}
          </p>
        </Reveal>

        <Reveal immediate delay={0.24}>
          <div className="mt-8 flex flex-wrap items-center gap-3">
            <a
              href="#demo"
              className="inline-flex items-center gap-2 rounded-full bg-accent px-5 py-2.5 text-sm font-medium text-black transition-transform hover:-translate-y-0.5"
            >
              <Play className="h-4 w-4 fill-black" />
              Watch the demo
            </a>
            <a
              href={site.links.github}
              target="_blank"
              rel="noreferrer"
              className="inline-flex items-center gap-2 rounded-full border border-line px-5 py-2.5 text-sm text-fg transition-colors hover:border-accent/40"
            >
              View on GitHub
              <ArrowUpRight className="h-4 w-4" />
            </a>
          </div>
        </Reveal>

        <Reveal immediate delay={0.32}>
          <div className="mt-12 flex flex-wrap gap-2">
            {hero.chips.map((c) => (
              <Tag key={c}>{c}</Tag>
            ))}
          </div>
        </Reveal>
      </div>

      <div
        aria-hidden
        className="tracking-label absolute bottom-6 left-1/2 -translate-x-1/2 font-mono text-[0.65rem] uppercase text-faint"
      >
        scroll
      </div>
    </section>
  );
}
