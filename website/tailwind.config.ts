import type { Config } from "tailwindcss";

const config: Config = {
  content: [
    "./app/**/*.{ts,tsx,mdx}",
    "./components/**/*.{ts,tsx,mdx}",
    "./content/**/*.{ts,tsx}",
  ],
  theme: {
    extend: {
      colors: {
        // Solid semantic tokens (driven by CSS vars in globals.css).
        base: "var(--bg)",
        surface: "var(--surface)",
        raised: "var(--raised)",
        fg: "var(--fg)",
        muted: "var(--muted)",
        faint: "var(--faint)",
        line: "var(--line)",
        accent: "var(--accent)",
        "accent-soft": "var(--accent-soft)",
      },
      fontFamily: {
        sans: ["var(--font-sans)", "ui-sans-serif", "system-ui", "sans-serif"],
        mono: ["var(--font-mono)", "ui-monospace", "SFMono-Regular", "monospace"],
      },
      maxWidth: {
        shell: "72rem", // ~1152px content shell
      },
      letterSpacing: {
        label: "0.18em",
      },
      keyframes: {
        "fade-up": {
          "0%": { opacity: "0", transform: "translateY(16px)" },
          "100%": { opacity: "1", transform: "translateY(0)" },
        },
        "pulse-dot": {
          "0%, 100%": { opacity: "1", transform: "scale(1)" },
          "50%": { opacity: "0.4", transform: "scale(0.7)" },
        },
        "caret": {
          "0%, 49%": { opacity: "1" },
          "50%, 100%": { opacity: "0" },
        },
        "drift": {
          "0%": { transform: "translate3d(0,0,0)" },
          "50%": { transform: "translate3d(-2%, -1.5%, 0)" },
          "100%": { transform: "translate3d(0,0,0)" },
        },
      },
      animation: {
        "fade-up": "fade-up 0.7s cubic-bezier(0.16,1,0.3,1) both",
        "pulse-dot": "pulse-dot 1.8s ease-in-out infinite",
        caret: "caret 1.1s steps(1) infinite",
        drift: "drift 24s ease-in-out infinite",
      },
    },
  },
  plugins: [],
};

export default config;
