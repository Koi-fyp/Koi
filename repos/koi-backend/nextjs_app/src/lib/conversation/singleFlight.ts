/** Share only an active lookup; retain no resolved value or secret after settlement. */
export function singleFlight<T>(resolve: (key: string) => Promise<T>) {
  const pending = new Map<string, Promise<T>>();
  return (key: string): Promise<T> => {
    const existing = pending.get(key); if (existing) return existing;
    const flight = resolve(key); pending.set(key, flight);
    const clear = () => { if (pending.get(key) === flight) pending.delete(key); };
    void flight.then(clear, clear);
    return flight;
  };
}
