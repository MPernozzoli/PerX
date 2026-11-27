import type { FrameKind } from "@/content/pratica-demo";

type StoryFrameProps = {
  kind: FrameKind;
  label: string;
  src?: string | null;
  alt: string;
  captureHint: string;
  vista: string;
};

const Placeholder = ({
  kind,
  vista,
  captureHint,
}: {
  kind: FrameKind;
  vista: string;
  captureHint: string;
}) => {
  const tall = kind === "phone";

  return (
    <div
      className={`relative overflow-hidden bg-[var(--chalk)] ${
        tall ? "min-h-[420px]" : "min-h-[260px] sm:min-h-[320px]"
      }`}
    >
      <div
        className="absolute inset-0 opacity-60"
        style={{
          backgroundImage:
            "linear-gradient(90deg, transparent 39px, rgba(18,21,26,0.05) 39px), linear-gradient(180deg, transparent 39px, rgba(18,21,26,0.05) 39px)",
          backgroundSize: "40px 40px",
        }}
        aria-hidden
      />

      {/* Silhouette UI — suggerisce la schermata senza fingere di essere l'app */}
      <div className="relative flex h-full flex-col gap-3 p-5 sm:p-7">
        <div className="flex items-center gap-2">
          <div className="h-2.5 w-16 rounded-sm bg-[var(--mist)]" />
          <div className="h-2.5 w-24 rounded-sm bg-[var(--mist)]" />
          <div className="ml-auto h-2.5 w-10 rounded-sm bg-[var(--coral)]/35" />
        </div>
        <div className="mt-2 space-y-2.5">
          {[92, 78, 86, 64, 80].map((width, i) => (
            <div
              key={i}
              className="flex items-center gap-3 border-b border-[var(--mist)]/80 pb-2.5"
            >
              <div className="h-8 w-8 shrink-0 rounded bg-[var(--mist)]" />
              <div className="min-w-0 flex-1 space-y-1.5">
                <div
                  className="h-2 rounded-sm bg-[var(--ink)]/12"
                  style={{ width: `${width}%` }}
                />
                <div
                  className="h-1.5 rounded-sm bg-[var(--ink)]/8"
                  style={{ width: `${Math.max(width - 18, 40)}%` }}
                />
              </div>
            </div>
          ))}
        </div>

        <div className="mt-auto border-t border-[var(--mist)] pt-4">
          <p className="font-display text-[11px] font-semibold tracking-[0.14em] text-perx-steel uppercase">
            {vista}
          </p>
          <p className="mt-1.5 max-w-md text-xs leading-relaxed text-perx-steel/90">
            {captureHint}
          </p>
        </div>
      </div>
    </div>
  );
};

export const StoryFrame = ({
  kind,
  label,
  src,
  alt,
  captureHint,
  vista,
}: StoryFrameProps) => {
  const content = src ? (
    // eslint-disable-next-line @next/next/no-img-element
    <img src={src} alt={alt} className="block h-auto w-full" />
  ) : (
    <Placeholder kind={kind} vista={vista} captureHint={captureHint} />
  );

  if (kind === "phone") {
    return (
      <figure className="mx-auto w-full max-w-[280px]">
        <div className="overflow-hidden rounded-[1.6rem] border border-[var(--mist)] bg-[var(--ink)] shadow-[0_18px_40px_-24px_rgba(18,21,26,0.45)]">
          <div className="flex items-center justify-center px-4 py-2.5">
            <div className="h-4 w-16 rounded-full bg-white/15" aria-hidden />
          </div>
          <div className="bg-white">{content}</div>
        </div>
        <figcaption className="mt-3 text-center font-display text-xs text-perx-steel">
          {label}
        </figcaption>
      </figure>
    );
  }

  if (kind === "browser") {
    return (
      <figure className="w-full">
        <div className="overflow-hidden rounded-md border border-[var(--mist)] bg-white shadow-[0_18px_40px_-28px_rgba(18,21,26,0.4)]">
          <div className="flex items-center gap-2 border-b border-[var(--mist)] bg-[var(--chalk)] px-3 py-2">
            <span className="h-2.5 w-2.5 rounded-full bg-[var(--mist)]" aria-hidden />
            <span className="h-2.5 w-2.5 rounded-full bg-[var(--mist)]" aria-hidden />
            <span className="h-2.5 w-2.5 rounded-full bg-[var(--mist)]" aria-hidden />
            <div className="ml-2 h-5 flex-1 rounded bg-white px-2 font-mono text-[10px] leading-5 text-perx-steel">
              {label}
            </div>
          </div>
          {content}
        </div>
      </figure>
    );
  }

  return (
    <figure className="w-full">
      <div className="overflow-hidden rounded-md border border-[var(--mist)] bg-white shadow-[0_18px_40px_-28px_rgba(18,21,26,0.4)]">
        <div className="flex items-center gap-2 border-b border-[var(--mist)] bg-[var(--chalk)] px-3 py-2">
          <span className="h-2.5 w-2.5 rounded-full bg-[var(--mist)]" aria-hidden />
          <span className="h-2.5 w-2.5 rounded-full bg-[var(--mist)]" aria-hidden />
          <span className="h-2.5 w-2.5 rounded-full bg-[var(--mist)]" aria-hidden />
          <span className="ml-2 font-display text-[11px] text-perx-steel">{label}</span>
        </div>
        {content}
      </div>
    </figure>
  );
};
