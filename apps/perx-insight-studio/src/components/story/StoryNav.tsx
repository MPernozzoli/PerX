import { storyChapters } from "@/content/pratica-demo";

type StoryNavProps = {
  activeId?: string;
};

export const StoryNav = ({ activeId }: StoryNavProps) => {
  return (
    <nav aria-label="Fasi della pratica">
      <p className="mb-4 font-display text-[11px] font-semibold tracking-[0.18em] text-perx-steel uppercase">
        Fasi
      </p>
      <ol className="relative space-y-0 border-l border-perx-line pl-4">
        {storyChapters.map((chapter) => {
          const isActive = activeId === chapter.id;
          return (
            <li key={chapter.id} className="relative py-1.5">
              <span
                className={`absolute -left-[1.28rem] top-1/2 h-2 w-2 -translate-y-1/2 rounded-full ${
                  isActive
                    ? "bg-[var(--coral)] ring-4 ring-[var(--coral)]/15"
                    : "bg-[var(--mist)]"
                }`}
                aria-hidden
              />
              <a
                href={`#${chapter.id}`}
                className={`block font-display text-sm transition-colors ${
                  isActive
                    ? "font-semibold text-perx-ink"
                    : "text-perx-steel hover:text-perx-ink"
                }`}
              >
                {chapter.navLabel}
              </a>
            </li>
          );
        })}
      </ol>
    </nav>
  );
};
