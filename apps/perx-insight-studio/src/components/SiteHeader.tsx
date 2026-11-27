import { Link, useLocation } from "react-router-dom";
import perxLogo from "@/assets/perx-logo.png";

type SiteHeaderProps = {
  tone?: "ink" | "paper";
};

export const SiteHeader = ({ tone = "paper" }: SiteHeaderProps) => {
  const location = useLocation();
  const onInk = tone === "ink";

  const linkClass = (path: string) => {
    const active = location.pathname === path;
    if (onInk) {
      return active
        ? "text-white"
        : "text-white/65 hover:text-white";
    }
    return active
      ? "text-[var(--ink)]"
      : "text-[var(--steel)] hover:text-[var(--ink)]";
  };

  return (
    <header
      className={`relative z-20 flex items-center justify-between px-6 py-5 md:px-10 ${
        onInk ? "text-white" : "text-[var(--ink)]"
      }`}
    >
      <Link to="/" className="flex items-center gap-3">
        {/* eslint-disable-next-line @next/next/no-img-element */}
        <img
          src={perxLogo.src}
          alt=""
          className="h-9 w-9 rounded-[0.65rem] object-contain"
        />
        <span className="font-display text-lg font-semibold tracking-tight">PerX</span>
      </Link>

      <nav className="flex items-center gap-6 text-sm font-medium md:gap-8">
        <Link to="/come-funziona" className={linkClass("/come-funziona")}>
          Come funziona
        </Link>
        <a
          href={location.pathname === "/" ? "#contatto" : "/#contatto"}
          className={
            onInk
              ? "rounded-md bg-white px-3.5 py-2 text-[var(--ink)] hover:bg-white/90"
              : "rounded-md bg-[var(--ink)] px-3.5 py-2 text-white hover:bg-[var(--ink)]/90"
          }
        >
          Contatto
        </a>
      </nav>
    </header>
  );
};
