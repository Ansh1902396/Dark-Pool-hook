import type { ReactNode } from "react";
import { cn } from "@/lib/cn";
import { Reveal } from "./Reveal";

type SectionProps = {
  id?: string;
  index?: string;
  label?: string;
  heading?: ReactNode;
  intro?: ReactNode;
  children?: ReactNode;
  className?: string;
  /** Render a faint engineering grid behind the section. */
  grid?: boolean;
};

/** Standard section: mono kicker (NN — Label), display heading, optional intro, content. */
export function Section({
  id,
  index,
  label,
  heading,
  intro,
  children,
  className,
  grid = false,
}: SectionProps) {
  return (
    <section id={id} className={cn("relative py-24 md:py-32", className)}>
      {grid && (
        <div aria-hidden className="depth-grid pointer-events-none absolute inset-0" />
      )}
      <div className="shell relative">
        {(label || heading || intro) && (
          <Reveal className="mb-12 max-w-3xl md:mb-16">
            {label && (
              <p className="text-label mb-5 flex items-center">
                {index && <span className="text-accent">{index}</span>}
                {index && <span className="mx-2 text-faint">—</span>}
                {label}
              </p>
            )}
            {heading && (
              <h2 className="text-balance text-3xl font-medium tracking-tight text-fg md:text-5xl">
                {heading}
              </h2>
            )}
            {intro && (
              <p className="mt-5 max-w-2xl text-pretty text-lg leading-relaxed text-muted">
                {intro}
              </p>
            )}
          </Reveal>
        )}
        {children}
      </div>
    </section>
  );
}
