import type { ReactNode } from "react";
import { cn } from "@/lib/cn";

export function Tag({
  children,
  className,
}: {
  children: ReactNode;
  className?: string;
}) {
  return (
    <span
      className={cn(
        "inline-flex items-center rounded-full border border-line bg-white/[0.02] px-3 py-1 font-mono text-xs text-muted",
        className,
      )}
    >
      {children}
    </span>
  );
}
