interface Props {
  currentStep: number;
  totalSteps: number;
}

export default function ProgressIndicator({ currentStep, totalSteps }: Props) {
  return (
    <div className="flex gap-1.5 justify-center py-3 px-6">
      {Array.from({ length: totalSteps }).map((_, i) => (
        <div
          key={i}
          className={`h-1.5 rounded-full transition-all duration-300 ${
            i === currentStep
              ? 'w-6 bg-[#2E75B6]'
              : i < currentStep
              ? 'w-1.5 bg-[#2E75B6] opacity-50'
              : 'w-1.5 bg-gray-300'
          }`}
        />
      ))}
    </div>
  );
}
