import { HeroSection } from "@/components/HeroSection";
import { ProblemSection } from "@/components/ProblemSection";
import { SolutionSection } from "@/components/SolutionSection";
import { FeaturesSection } from "@/components/FeaturesSection";
import { PortalSection } from "@/components/PortalSection";
import { CommunicationsSection } from "@/components/CommunicationsSection";
import { DocumentationSection } from "@/components/DocumentationSection";
import { BenefitsSection } from "@/components/BenefitsSection";
import { ContactSection } from "@/components/ContactSection";
import { Footer } from "@/components/Footer";

const Index = () => {
  return (
    <div className="min-h-screen bg-background font-['Inter']">
      <HeroSection />
      <ProblemSection />
      <SolutionSection />
      <FeaturesSection />
      <PortalSection />
      <CommunicationsSection />
      <DocumentationSection />
      <BenefitsSection />
      <ContactSection />
      <Footer />
    </div>
  );
};

export default Index;
