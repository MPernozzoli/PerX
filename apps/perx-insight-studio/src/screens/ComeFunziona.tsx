import { SiteHeader } from "@/components/SiteHeader";
import { StoryLayout } from "@/components/story/StoryLayout";
import { ContactSection } from "@/components/ContactSection";
import { Footer } from "@/components/Footer";

const ComeFunziona = () => {
  return (
    <div className="min-h-screen bg-dossier text-perx-ink">
      <div className="border-b border-perx-line bg-perx-paper/90 backdrop-blur-sm">
        <SiteHeader tone="paper" />
      </div>
      <StoryLayout />
      <ContactSection />
      <Footer />
    </div>
  );
};

export default ComeFunziona;
