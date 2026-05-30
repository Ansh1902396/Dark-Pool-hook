import { ArrowUpRight, Github, Mail } from "lucide-react";
import { site } from "@/content/site";

export function Footer() {
  const year = new Date().getFullYear();
  const socials = (
    [
      site.links.linkedin && { label: "LinkedIn", href: site.links.linkedin },
      site.links.x && { label: "X", href: site.links.x },
      site.links.resume && { label: "Résumé", href: site.links.resume },
    ].filter(Boolean) as { label: string; href: string }[]
  );

  return (
    <footer id="contact" className="relative border-t border-line py-20 md:py-28">
      <div className="shell">
        <p className="text-label mb-6">Get in touch</p>
        <h2 className="max-w-3xl text-balance text-3xl font-medium tracking-tight text-fg md:text-5xl">
          Building across contracts, ZK, and infrastructure.
        </h2>
        <p className="mt-5 max-w-xl text-pretty text-lg text-muted">
          I&apos;m {site.author} — open to roles and collaborations in DeFi, applied
          cryptography, and protocol engineering.
        </p>

        <div className="mt-8 flex flex-wrap items-center gap-3">
          <a
            href={`mailto:${site.email}`}
            className="inline-flex items-center gap-2 rounded-full bg-accent px-5 py-2.5 text-sm font-medium text-black transition-transform hover:-translate-y-0.5"
          >
            <Mail className="h-4 w-4" />
            {site.email}
          </a>
          <a
            href={site.links.github}
            target="_blank"
            rel="noreferrer"
            className="inline-flex items-center gap-2 rounded-full border border-line px-5 py-2.5 text-sm text-fg transition-colors hover:border-accent/40"
          >
            <Github className="h-4 w-4" />
            GitHub
          </a>
          {socials.map((s) => (
            <a
              key={s.label}
              href={s.href}
              target="_blank"
              rel="noreferrer"
              className="inline-flex items-center gap-1.5 rounded-full border border-line px-5 py-2.5 text-sm text-fg transition-colors hover:border-accent/40"
            >
              {s.label}
              <ArrowUpRight className="h-3.5 w-3.5" />
            </a>
          ))}
        </div>

        <div className="mt-16 flex flex-col items-start justify-between gap-4 border-t border-line pt-8 font-mono text-xs text-faint sm:flex-row sm:items-center">
          <span>
            © {year} {site.author}
          </span>
          <span>DarkCoW · built in the Uniswap Hook Incubator</span>
          <a href="#top" className="transition-colors hover:text-accent">
            back to top ↑
          </a>
        </div>
      </div>
    </footer>
  );
}
