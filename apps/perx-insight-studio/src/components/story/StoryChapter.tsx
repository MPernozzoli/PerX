import type { StoryChapter as StoryChapterData } from "@/content/pratica-demo";
import { StoryFrame } from "./StoryFrame";
import { resolveStoryAsset } from "./story-assets";

type StoryChapterProps = {
  chapter: StoryChapterData;
  index: number;
};

export const StoryChapter = ({ chapter, index }: StoryChapterProps) => {
  const sideBySide = chapter.captures.length > 1;

  return (
    <section
      id={chapter.id}
      className="scroll-mt-28 border-t border-perx-line py-14 md:py-16"
    >
      <div className="mb-8 max-w-2xl">
        <p className="mb-2 font-display text-xs font-semibold tracking-[0.16em] text-perx-coral uppercase">
          {String(index + 1).padStart(2, "0")} · {chapter.actor}
        </p>
        <h2 className="font-display text-2xl font-semibold tracking-tight text-perx-ink md:text-3xl">
          {chapter.title}
        </h2>
        <p className="mt-3 text-base leading-relaxed text-perx-steel">
          {chapter.context}
        </p>
      </div>

      <div
        className={
          sideBySide
            ? "grid gap-6 lg:grid-cols-2"
            : chapter.captures[0]?.frame === "phone"
              ? "flex justify-center md:justify-start"
              : "w-full"
        }
      >
        {chapter.captures.map((capture) => (
          <StoryFrame
            key={capture.id}
            kind={capture.frame}
            label={capture.app}
            src={resolveStoryAsset(capture.filename)}
            alt={`${capture.vista} — ${capture.app}`}
            captureHint={capture.inquadratura}
            vista={capture.vista}
          />
        ))}
      </div>
    </section>
  );
};
