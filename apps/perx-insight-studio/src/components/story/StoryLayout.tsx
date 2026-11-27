import { useEffect, useState } from "react";
import { storyChapters } from "@/content/pratica-demo";
import { StoryChapter } from "./StoryChapter";
import { StoryHero } from "./StoryHero";
import { StoryNav } from "./StoryNav";

export const StoryLayout = () => {
  const [activeId, setActiveId] = useState(storyChapters[0]?.id);

  useEffect(() => {
    const sections = storyChapters
      .map((chapter) => document.getElementById(chapter.id))
      .filter((el): el is HTMLElement => Boolean(el));

    if (sections.length === 0) return;

    const observer = new IntersectionObserver(
      (entries) => {
        const visible = entries
          .filter((entry) => entry.isIntersecting)
          .sort((a, b) => b.intersectionRatio - a.intersectionRatio);
        const top = visible[0];
        if (top?.target.id) {
          setActiveId(top.target.id);
        }
      },
      { rootMargin: "-20% 0px -55% 0px", threshold: [0.1, 0.25, 0.5] },
    );

    sections.forEach((section) => observer.observe(section));
    return () => observer.disconnect();
  }, []);

  return (
    <div className="mx-auto max-w-6xl px-6 md:px-10">
      <StoryHero />

      <div className="lg:grid lg:grid-cols-[200px_minmax(0,1fr)] lg:gap-14">
        <aside className="hidden lg:block">
          <div className="sticky top-8 py-8">
            <StoryNav activeId={activeId} />
          </div>
        </aside>

        <div>
          <div className="overflow-x-auto border-b border-perx-line py-4 lg:hidden">
            <div className="flex min-w-max gap-1">
              {storyChapters.map((chapter) => (
                <a
                  key={chapter.id}
                  href={`#${chapter.id}`}
                  className={`rounded-md px-3 py-1.5 font-display text-sm whitespace-nowrap ${
                    activeId === chapter.id
                      ? "bg-[var(--ink)] text-white"
                      : "text-perx-steel hover:bg-[var(--chalk)]"
                  }`}
                >
                  {chapter.navLabel}
                </a>
              ))}
            </div>
          </div>

          {storyChapters.map((chapter, index) => (
            <StoryChapter key={chapter.id} chapter={chapter} index={index} />
          ))}
        </div>
      </div>
    </div>
  );
};
