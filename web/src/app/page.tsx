import { Compare } from "@/components/Compare";
import { Facts } from "@/components/Facts";
import { Faq } from "@/components/Faq";
import { Features } from "@/components/Features";
import { GetDotphin } from "@/components/GetDotphin";
import { Hero } from "@/components/Hero";
import { PathBar } from "@/components/PathBar";
import { Shortcuts } from "@/components/Shortcuts";
import { TerminalSection } from "@/components/TerminalSection";
import { ViewModes } from "@/components/ViewModes";

export default function Home() {
  return (
    <>
      <main>
        <Hero />
        <Facts />
        <Features />
        <ViewModes />
        <TerminalSection />
        <Shortcuts />
        <Compare />
        <Faq />
        <GetDotphin />
      </main>
      <PathBar />
    </>
  );
}
