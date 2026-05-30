"use client";

import { motion, useReducedMotion } from "framer-motion";
import type { ReactNode } from "react";

type RevealProps = {
  children: ReactNode;
  className?: string;
  /** Stagger offset in seconds. */
  delay?: number;
  /** Animate on mount instead of when scrolled into view (for above-the-fold). */
  immediate?: boolean;
};

const EASE: [number, number, number, number] = [0.16, 1, 0.3, 1];

/** Content that surfaces out of the dark: fade + rise, once. Honors reduced-motion. */
export function Reveal({ children, className, delay = 0, immediate = false }: RevealProps) {
  const reduced = useReducedMotion();

  if (reduced) return <div className={className}>{children}</div>;

  const animateProps = immediate
    ? { animate: { opacity: 1, y: 0 } }
    : {
        whileInView: { opacity: 1, y: 0 },
        viewport: { once: true, margin: "-80px" },
      };

  return (
    <motion.div
      className={className}
      initial={{ opacity: 0, y: 18 }}
      transition={{ duration: 0.75, ease: EASE, delay }}
      {...animateProps}
    >
      {children}
    </motion.div>
  );
}
