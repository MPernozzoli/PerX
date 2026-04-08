const CLAIM_PROGRESS_STEPS = [
  "Apertura",
  "Documentazione",
  "Analisi",
  "Atto",
  "Liquidazione"
];

function progressIndexFromState(stateCode?: string | null) {
  switch (stateCode) {
    case "SV001":
    case "SV002":
    case "SV004":
    case "SV005":
      return 0;
    case "SV006":
    case "SV007":
    case "SV008":
    case "SV009":
    case "SV022":
    case "SV023":
    case "SV052":
    case "SV053":
    case "SV050":
      return 1;
    case "SV010":
    case "SV015":
    case "SV016":
    case "SV018":
    case "SV019":
    case "SV026":
      return 2;
    case "SV020":
    case "SV030":
    case "SV031":
    case "SV032":
      return 3;
    default:
      return 4;
  }
}

export function ClaimProgress({ stateCode }: { stateCode?: string | null }) {
  const currentIndex = progressIndexFromState(stateCode);

  return (
    <div className="claim-progress">
      <div className="claim-progress__desktop">
        <div className="claim-progress__line" />
        <div
          className="claim-progress__line claim-progress__line--active"
          style={{
            width: `${(currentIndex / (CLAIM_PROGRESS_STEPS.length - 1)) * 100}%`
          }}
        />
        <div className="claim-progress__steps">
          {CLAIM_PROGRESS_STEPS.map((step, index) => {
            const isDone = index < currentIndex;
            const isCurrent = index === currentIndex;
            return (
              <div key={step} className="claim-progress__step">
                <div
                  className={`claim-progress__dot${
                    isDone ? " claim-progress__dot--done" : ""
                  }${isCurrent ? " claim-progress__dot--current" : ""}`}
                >
                  {isDone ? "✓" : index + 1}
                </div>
                <span>{step}</span>
              </div>
            );
          })}
        </div>
      </div>

      <div className="claim-progress__mobile">
        <div className="claim-progress__mobile-badge">
          <strong>
            {currentIndex + 1}/{CLAIM_PROGRESS_STEPS.length}
          </strong>
        </div>
        <div className="claim-progress__mobile-copy">
          <span>Fase attuale</span>
          <strong>{CLAIM_PROGRESS_STEPS[currentIndex]}</strong>
        </div>
      </div>
    </div>
  );
}
