import { PropsWithChildren } from "react";

type SectionCardProps = PropsWithChildren<{
  title: string;
  subtitle?: string;
  eyebrow?: string;
  accent?: "gold" | "green" | "ink";
}>;

export function SectionCard({
  title,
  subtitle,
  eyebrow,
  accent = "ink",
  children
}: SectionCardProps) {
  return (
    <section className={`section-card section-card--${accent}`}>
      <div className="section-card__header">
        {eyebrow ? <p className="section-card__eyebrow">{eyebrow}</p> : null}
        <h2>{title}</h2>
        {subtitle ? <p>{subtitle}</p> : null}
      </div>
      <div className="section-card__content">{children}</div>
    </section>
  );
}
