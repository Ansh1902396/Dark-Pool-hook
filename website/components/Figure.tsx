"use client";

import Image from "next/image";
import { useEffect, useState } from "react";
import { Maximize2, X } from "lucide-react";
import { cn } from "@/lib/cn";

type FigureProps = {
  src: string;
  alt: string;
  caption?: string;
  priority?: boolean;
  className?: string;
};

/** Framed diagram "plate" with a click-to-zoom lightbox. */
export function Figure({ src, alt, caption, priority, className }: FigureProps) {
  const [open, setOpen] = useState(false);

  useEffect(() => {
    if (!open) return;
    const onKey = (e: KeyboardEvent) => {
      if (e.key === "Escape") setOpen(false);
    };
    const prev = document.body.style.overflow;
    document.body.style.overflow = "hidden";
    document.addEventListener("keydown", onKey);
    return () => {
      document.body.style.overflow = prev;
      document.removeEventListener("keydown", onKey);
    };
  }, [open]);

  return (
    <figure className={cn("group", className)}>
      <button
        type="button"
        onClick={() => setOpen(true)}
        aria-label={`Zoom diagram: ${alt}`}
        className="relative block w-full overflow-hidden rounded-xl border border-line bg-surface transition-colors hover:border-accent/30"
      >
        <div className="relative aspect-[16/10] w-full">
          <Image
            src={src}
            alt={alt}
            fill
            sizes="(max-width: 768px) 100vw, 960px"
            className="object-contain p-3 md:p-6"
            priority={priority}
          />
        </div>
        <span className="absolute right-3 top-3 inline-flex h-8 w-8 items-center justify-center rounded-md border border-line bg-base/70 text-muted opacity-0 backdrop-blur transition-opacity group-hover:opacity-100">
          <Maximize2 className="h-4 w-4" />
        </span>
      </button>

      {caption && (
        <figcaption className="mt-3 font-mono text-xs text-faint">{caption}</figcaption>
      )}

      {open && (
        <div
          role="dialog"
          aria-modal="true"
          aria-label={alt}
          onClick={() => setOpen(false)}
          className="fixed inset-0 z-[100] flex items-center justify-center bg-black/85 p-4 backdrop-blur-sm md:p-12"
        >
          <button
            onClick={() => setOpen(false)}
            aria-label="Close"
            className="absolute right-4 top-4 inline-flex h-10 w-10 items-center justify-center rounded-full border border-line bg-base/70 text-muted transition-colors hover:text-fg"
          >
            <X className="h-5 w-5" />
          </button>
          <div
            className="relative h-full w-full max-w-6xl"
            onClick={(e) => e.stopPropagation()}
          >
            <Image src={src} alt={alt} fill sizes="100vw" className="object-contain" />
          </div>
        </div>
      )}
    </figure>
  );
}
