import { ArrowUpRight, BadgeCheck } from "lucide-react";
import Image from "next/image";
import { Section } from "./Section";
import { Reveal } from "./Reveal";
import { about, certificate, site } from "@/content/site";

const cards = [
  {
    title: "Uniswap Hook Incubator",
    note: "Atrium Academy · hook directory",
    href: site.links.uhi,
  },
  {
    title: "Source code",
    note: "github · Dark-Pool-hook",
    href: site.links.github,
  },
];

export function About() {
  return (
    <Section
      id="about"
      index={about.index}
      label={about.label}
      heading={about.heading}
    >
      <div className="grid gap-10 md:grid-cols-[1.4fr_1fr] md:gap-16">
        <Reveal className="space-y-5">
          {about.body.map((p, i) => (
            <p key={i} className="text-pretty text-lg leading-relaxed text-muted">
              {p}
            </p>
          ))}
        </Reveal>

        <Reveal delay={0.1} className="space-y-3">
          {/* Onchain certificate of completion */}
          <a
            href={certificate.explorerUrl}
            target="_blank"
            rel="noreferrer"
            className="group block overflow-hidden rounded-xl border border-line bg-surface transition-colors hover:border-accent/40"
          >
            <div className="relative aspect-[4/3] w-full bg-white/[0.015]">
              <Image
                src={certificate.image}
                alt={`${certificate.title} — ${certificate.issuer}, awarded to ${certificate.holder}`}
                fill
                sizes="(max-width: 768px) 100vw, 480px"
                className="object-contain p-2"
              />
              <span className="absolute left-3 top-3 inline-flex items-center gap-1.5 rounded-full border border-accent/30 bg-base/70 px-2.5 py-1 font-mono text-[11px] text-accent backdrop-blur">
                <BadgeCheck className="h-3.5 w-3.5" />
                onchain
              </span>
            </div>
            <div className="flex items-center justify-between gap-3 border-t border-line px-5 py-4">
              <div>
                <div className="text-sm text-fg">{certificate.title}</div>
                <div className="font-mono text-xs text-faint">
                  {certificate.tokenName} · {certificate.chain} · {certificate.standard}
                </div>
              </div>
              <ArrowUpRight className="h-4 w-4 shrink-0 text-faint transition-colors group-hover:text-accent" />
            </div>
          </a>

          {cards.map((c) => (
            <a
              key={c.title}
              href={c.href}
              target="_blank"
              rel="noreferrer"
              className="group flex items-center justify-between rounded-xl border border-line bg-white/[0.015] px-5 py-4 transition-colors hover:border-accent/40"
            >
              <div>
                <div className="text-sm text-fg">{c.title}</div>
                <div className="font-mono text-xs text-faint">{c.note}</div>
              </div>
              <ArrowUpRight className="h-4 w-4 text-faint transition-colors group-hover:text-accent" />
            </a>
          ))}
        </Reveal>
      </div>
    </Section>
  );
}
