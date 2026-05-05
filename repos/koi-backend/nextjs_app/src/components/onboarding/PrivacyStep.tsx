interface Props {
  onNext: () => void;
}

const STORED = [
  'Anonymous session ID (no name required)',
  'Your conversations (encrypted, on your device)',
  'Check-in mood responses',
  'Your avatar and language preference',
];

const NOT_STORED = [
  'Your real name or contact details',
  'Location data',
  'Conversations shared with third parties',
  'Any data sold to advertisers',
];

export default function PrivacyStep({ onNext }: Props) {
  return (
    <div className="flex flex-col flex-1 p-6">
      <div className="flex-1 overflow-y-auto">
        <h2 className="text-2xl font-bold text-gray-900 mb-1">Privacy Matters</h2>
        <p className="text-gray-500 mb-6 text-sm">Here&apos;s what you should know about your data.</p>

        <section className="mb-6">
          <h3 className="font-semibold text-gray-700 mb-3 flex items-center gap-2">
            <span className="text-green-500 text-lg">✓</span> What we store
          </h3>
          <ul className="space-y-2">
            {STORED.map((item) => (
              <li key={item} className="flex items-start gap-2 text-gray-600 text-sm">
                <span className="text-green-400 mt-0.5 shrink-0">•</span>
                {item}
              </li>
            ))}
          </ul>
        </section>

        <section>
          <h3 className="font-semibold text-gray-700 mb-3 flex items-center gap-2">
            <span className="text-red-400 text-lg">✗</span> What we never store
          </h3>
          <ul className="space-y-2">
            {NOT_STORED.map((item) => (
              <li key={item} className="flex items-start gap-2 text-gray-600 text-sm">
                <span className="text-red-300 mt-0.5 shrink-0">•</span>
                {item}
              </li>
            ))}
          </ul>
        </section>
      </div>

      <button
        onClick={onNext}
        className="w-full py-3 bg-[#2E75B6] text-white rounded-xl font-semibold text-lg mt-6"
      >
        I Understand
      </button>
    </div>
  );
}
