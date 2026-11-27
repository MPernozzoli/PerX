import { ExternalLink } from "lucide-react";
import { Link } from "react-router-dom";

export const Footer = () => {
  return (
    <footer className="border-t border-white/10 bg-[var(--ink)] py-10 text-white">
      <div className="mx-auto flex max-w-6xl flex-col gap-6 px-6 md:px-10">
        <div className="flex flex-col items-start justify-between gap-4 md:flex-row md:items-center">
          <p className="text-sm text-white/50">
            © {new Date().getFullYear()} PerX.it — Piattaforma operativa per
            studi peritali.
          </p>

          <div className="flex flex-wrap gap-6 text-sm">
            <Link
              to="/come-funziona"
              className="text-white/50 hover:text-white"
            >
              Come funziona
            </Link>
            <a href="#" className="text-white/50 hover:text-white">
              Privacy Policy
            </a>
            <a href="#" className="text-white/50 hover:text-white">
              Cookie Policy
            </a>
          </div>
        </div>

        <div className="border-t border-white/10 pt-6">
          <p className="text-xs text-white/40">
            Progettato e sviluppato da{" "}
            <a
              href="https://pynkstudio.it"
              target="_blank"
              rel="noopener noreferrer"
              className="inline-flex items-center gap-1 font-medium text-white/70 hover:text-white"
            >
              PynkStudio
              <ExternalLink className="h-3 w-3" />
            </a>
          </p>
        </div>
      </div>
    </footer>
  );
};
