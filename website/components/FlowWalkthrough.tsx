"use client";

import { useEffect, useRef, useState } from "react";
import { AnimatePresence, motion, useReducedMotion } from "framer-motion";
import { flow } from "@/content/site";
import { Figure } from "./Figure";
import { Reveal } from "./Reveal";
import { cn } from "@/lib/cn";

export function FlowWalkthrough() {
  const [active, setActive] = useState(0);
  const stepRefs = useRef<Array<HTMLDivElement | null>>([]);
  const reduced = useReducedMotion();

  useEffect(() => {
    const observer = new IntersectionObserver(
      (entries) => {
        entries.forEach((e) => {
          if (e.isIntersecting) {
            setActive(Number((e.target as HTMLElement).dataset.index));
          }
        });
      },
      { rootMargin: "-50% 0px -50% 0px", threshold: 0 },
    );
    stepRefs.current.forEach((el) => el && observer.observe(el));
    return () => observer.disconnect();
  }, []);

  const total = flow.steps.length;
  const activeStep = flow.steps[active];

  return (
    <section id="flow" className="relative py-24 md:py-32">
      <div className="shell">
        <Reveal className="mb-12 max-w-3xl md:mb-16">
          <p className="text-label mb-5 flex items-center">
            <span className="text-accent">{flow.index}</span>
            <span className="mx-2 text-faint">—</span>
            {flow.label}
          </p>
          <h2 className="text-balance text-3xl font-medium tracking-tight text-fg md:text-5xl">
            {flow.heading}
          </h2>
          <p className="mt-5 max-w-2xl text-pretty text-lg leading-relaxed text-muted">
            {flow.intro}
          </p>
        </Reveal>

        <div className="lg:grid lg:grid-cols-[260px_1fr] lg:gap-16">
          {/* Sticky companion — desktop only */}
          <div className="hidden lg:block">
            <div className="sticky top-28">
              <div className="font-mono text-xs text-faint">
                step <span className="text-accent">{activeStep.n}</span> /{" "}
                {String(total).padStart(2, "0")}
              </div>

              <div className="relative mt-5 h-6 w-full">
                <AnimatePresence mode="wait" initial={false}>
                  <motion.span
                    key={activeStep.n}
                    initial={reduced ? false : { opacity: 0, y: 8 }}
                    animate={{ opacity: 1, y: 0 }}
                    exit={reduced ? undefined : { opacity: 0, y: -8 }}
                    transition={{ duration: 0.25 }}
                    className="absolute inset-0 font-mono text-xs uppercase tracking-wider text-muted"
                  >
                    {activeStep.actor}
                  </motion.span>
                </AnimatePresence>
              </div>

              <ul className="mt-6 space-y-2.5">
                {flow.steps.map((s, i) => (
                  <li key={s.n}>
                    <button
                      onClick={() =>
                        stepRefs.current[i]?.scrollIntoView({
                          behavior: "smooth",
                          block: "center",
                        })
                      }
                      className="group flex w-full items-center gap-3 text-left"
                    >
                      <span
                        className={cn(
                          "h-px shrink-0 transition-all duration-300",
                          i === active
                            ? "w-10 bg-accent"
                            : "w-5 bg-line group-hover:w-7",
                        )}
                      />
                      <span
                        className={cn(
                          "font-mono text-xs transition-colors",
                          i === active
                            ? "text-fg"
                            : "text-faint group-hover:text-muted",
                        )}
                      >
                        {s.title}
                      </span>
                    </button>
                  </li>
                ))}
              </ul>
            </div>
          </div>

          {/* Step blocks drive the scroll */}
          <div>
            {flow.steps.map((s, i) => (
              <div
                key={s.n}
                data-index={i}
                ref={(el) => {
                  stepRefs.current[i] = el;
                }}
                className="flex min-h-[44vh] flex-col justify-center border-t border-line py-10 first:border-t-0 lg:min-h-[66vh]"
              >
                <Reveal>
                  <div
                    className={cn(
                      "transition-opacity duration-500",
                      i === active ? "opacity-100" : "lg:opacity-40",
                    )}
                  >
                    <div className="flex items-baseline gap-4">
                      <span className="font-mono text-5xl font-medium tabular-nums text-accent md:text-6xl">
                        {s.n}
                      </span>
                      <span className="font-mono text-xs uppercase tracking-wider text-faint">
                        {s.actor}
                      </span>
                    </div>
                    <h3 className="mt-5 text-2xl font-medium tracking-tight text-fg md:text-3xl">
                      {s.title}
                    </h3>
                    <p className="mt-4 max-w-xl text-pretty text-base leading-relaxed text-muted md:text-lg">
                      {s.body}
                    </p>
                  </div>
                </Reveal>
              </div>
            ))}
          </div>
        </div>

        {/* Source diagrams */}
        <Reveal className="mt-20 md:mt-28">
          <p className="text-label mb-8">Reference diagrams</p>
          <div className="grid gap-6 lg:grid-cols-3">
            {flow.figures.map((f) => (
              <Figure key={f.src} src={f.src} alt={f.alt} caption={f.caption} />
            ))}
          </div>
        </Reveal>
      </div>
    </section>
  );
}
