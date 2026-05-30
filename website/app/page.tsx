import { Hero } from "@/components/Hero";
import { Problem } from "@/components/Problem";
import { Overview } from "@/components/Overview";
import { FlowWalkthrough } from "@/components/FlowWalkthrough";
import { Pillars } from "@/components/Pillars";
import { Demo } from "@/components/Demo";
import { Skills } from "@/components/Skills";
import { About } from "@/components/About";
import { Footer } from "@/components/Footer";

export default function Home() {
  return (
    <>
      <main>
        <Hero />
        <Problem />
        <Overview />
        <FlowWalkthrough />
        <Pillars />
        <Demo />
        <Skills />
        <About />
      </main>
      <Footer />
    </>
  );
}
