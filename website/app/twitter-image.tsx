// Reuse the Open Graph image for the Twitter/X card. Runtime is intentionally
// not re-exported (Next can't follow re-exported route config); the default
// runtime renders the same image just fine.
export { default, alt, size, contentType } from "./opengraph-image";
