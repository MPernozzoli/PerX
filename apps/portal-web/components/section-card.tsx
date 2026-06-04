import { PropsWithChildren } from "react";

type SectionCardProps = PropsWithChildren<{
  title: string;
  eyebrow?: string;
  accent?: "gold" | "green" | "ink";
}>;

export function SectionCard({
  title,
  eyebrow,
  accent = "ink",
  children
}: SectionCardProps) {
  return (
    <section className={`section-card section-card--${accent}`}>
      <div className="section-card__header">
        {eyebrow ? <p className="section-card__eyebrow">{eyebrow}</p> : null}
        <h2>{title}</h2>
      </div>
      <div className="section-card__content">{children}</div>
    </section>
  );
}
