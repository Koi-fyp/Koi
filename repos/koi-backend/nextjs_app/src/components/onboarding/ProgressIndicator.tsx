interface Props {
  currentStep: number;
  totalSteps: number;
}

export default function ProgressIndicator({ currentStep, totalSteps }: Props) {
  return (
    <div
      style={{
        position: 'sticky',
        top: 0,
        zIndex: 10,
        background: '#fff',
        borderBottom: '2px solid #000',
        padding: '10px 20px',
        display: 'flex',
        gap: '6px',
        alignItems: 'center',
      }}
    >
      {Array.from({ length: totalSteps }).map((_, i) => {
        const isActive = i === currentStep;
        const isDone   = i < currentStep;
        return (
          <div
            key={i}
            style={{
              height: '4px',
              flex: isActive ? 2 : 1,
              borderRadius: '2px',
              border: '1px solid #000',
              background: isDone || isActive ? 'var(--neo-blue)' : '#E5E5E5',
              opacity: isDone ? 0.55 : 1,
              transition: 'flex 0.3s ease, background 0.3s ease',
            }}
          />
        );
      })}
    </div>
  );
}
