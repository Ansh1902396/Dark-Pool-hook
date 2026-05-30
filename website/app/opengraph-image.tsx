import { ImageResponse } from "next/og";

export const runtime = "edge";
export const alt = "DarkCoW — a private dark-pool CoW hook for Uniswap v4";
export const size = { width: 1200, height: 630 };
export const contentType = "image/png";

export default function OpengraphImage() {
  return new ImageResponse(
    (
      <div
        style={{
          height: "100%",
          width: "100%",
          display: "flex",
          flexDirection: "column",
          justifyContent: "space-between",
          background: "#0a0b0d",
          backgroundImage:
            "radial-gradient(900px 500px at 60% -10%, rgba(94,234,212,0.16), transparent 60%)",
          padding: "72px",
          color: "#e7e9ec",
          fontFamily: "sans-serif",
        }}
      >
        <div style={{ display: "flex", alignItems: "center", gap: 16 }}>
          <div style={{ width: 16, height: 16, borderRadius: 999, background: "#5eead4", display: "flex" }} />
          <div style={{ fontSize: 26, color: "#9ba1ac", letterSpacing: 2, display: "flex" }}>
            UNISWAP HOOK INCUBATOR · UHI
          </div>
        </div>

        <div style={{ display: "flex", flexDirection: "column" }}>
          <div style={{ display: "flex", flexWrap: "wrap", fontSize: 82, fontWeight: 700, lineHeight: 1.05, letterSpacing: -2 }}>
            <span style={{ color: "#5eead4" }}>Private order flow&nbsp;</span>
            <span>for Uniswap v4.</span>
          </div>
          <div style={{ display: "flex", marginTop: 26, fontSize: 30, color: "#9ba1ac", maxWidth: 960 }}>
            A dark-pool CoW hook, secured by an EigenLayer AVS and SP1 zero-knowledge proofs.
          </div>
        </div>

        <div style={{ display: "flex", gap: 14, fontSize: 22, color: "#9ba1ac" }}>
          {["Uniswap v4 Hook", "EigenLayer AVS", "SP1 ZK", "CoW matching"].map((t) => (
            <div
              key={t}
              style={{
                display: "flex",
                border: "1px solid rgba(255,255,255,0.14)",
                borderRadius: 999,
                padding: "8px 18px",
              }}
            >
              {t}
            </div>
          ))}
        </div>
      </div>
    ),
    { ...size },
  );
}
