/**
 * Fixed, full-viewport "dark pool" backdrop:
 *  - near-black base
 *  - a slowly drifting liquidity wash (single mint-cyan accent)
 *  - an edge vignette that deepens the corners
 *  - faint film grain so the black never looks flat
 * Pure CSS — animation is disabled under prefers-reduced-motion (globals.css).
 */
const GRAIN =
  "url(\"data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='180' height='180'%3E%3Cfilter id='n'%3E%3CfeTurbulence type='fractalNoise' baseFrequency='0.85' numOctaves='2' stitchTiles='stitch'/%3E%3C/filter%3E%3Crect width='100%25' height='100%25' filter='url(%23n)'/%3E%3C/svg%3E\")";

export function DepthBackground() {
  return (
    <div
      aria-hidden
      className="pointer-events-none fixed inset-0 -z-10 overflow-hidden bg-base"
    >
      <div className="depth-wash animate-drift absolute -inset-[20%]" />
      <div
        className="absolute inset-0"
        style={{
          background:
            "radial-gradient(125% 80% at 50% -10%, transparent 55%, rgba(0,0,0,0.55) 100%)",
        }}
      />
      <div
        className="absolute inset-0 opacity-[0.04] mix-blend-soft-light"
        style={{ backgroundImage: GRAIN, backgroundSize: "180px 180px" }}
      />
    </div>
  );
}
