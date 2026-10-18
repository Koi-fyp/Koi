/** @jest-environment jsdom */
import React from 'react';
import { fireEvent, render, renderHook, screen } from '@testing-library/react';
import VoiceToggle from '@/components/companion/VoiceToggle';
import { planReplyVoice, readVoiceEnabled, speechBaseUrl, useVoiceEnabled, voiceCompanion, voiceStorageKey } from '@/lib/speech/replyVoicePolicy';

function Harness({ uid, configured = true, companionHasVoice = true }: { uid: string | null; configured?: boolean; companionHasVoice?: boolean }) {
  const [enabled, setEnabled] = useVoiceEnabled(uid);
  return <VoiceToggle checked={enabled} onChange={setEnabled} configured={configured} companionHasVoice={companionHasVoice} signedIn={!!uid} />;
}
const toggle = () => screen.getByRole('switch', { name: 'Spoken replies' });

describe('VoiceToggle', () => {
  beforeEach(() => localStorage.clear());

  it('is off by default and persists a boolean per uid', () => {
    const view = render(<Harness uid="user-a" />);
    expect(toggle()).toHaveAttribute('aria-checked', 'false');
    fireEvent.click(toggle());
    expect(toggle()).toHaveAttribute('aria-checked', 'true');
    expect(localStorage.getItem(voiceStorageKey('user-a'))).toBe('true');
    view.rerender(<Harness uid="user-b" />);
    expect(toggle()).toHaveAttribute('aria-checked', 'false');
    expect(localStorage.getItem('koi_voice_enabled_user-b')).toBeNull();
    view.rerender(<Harness uid="user-a" />);
    expect(toggle()).toHaveAttribute('aria-checked', 'true');
    fireEvent.click(toggle());
    expect(localStorage.getItem('koi_voice_enabled_user-a')).toBe('false');
    expect(Object.keys(localStorage)).toEqual(['koi_voice_enabled_user-a']);
  });

  it('never reports the previous uid as enabled on the render where the uid changes', () => {
    localStorage.setItem(voiceStorageKey('user-a'), 'true');
    const { result, rerender } = renderHook(({ uid }) => useVoiceEnabled(uid), { initialProps: { uid: 'user-a' as string | null } });
    expect(result.current[0]).toBe(true);
    const seen: boolean[] = [];
    rerender({ uid: 'user-b' }); seen.push(result.current[0]);
    rerender({ uid: null }); seen.push(result.current[0]);
    expect(seen).toEqual([false, false]);
  });

  it('reads storage failures as off without throwing', () => {
    const get = jest.spyOn(Storage.prototype, 'getItem').mockImplementation(() => { throw new Error('blocked'); });
    const set = jest.spyOn(Storage.prototype, 'setItem').mockImplementation(() => { throw new Error('blocked'); });
    try {
      expect(readVoiceEnabled('user-a')).toBe(false);
      render(<Harness uid="user-a" />);
      expect(() => fireEvent.click(toggle())).not.toThrow();
    } finally { get.mockRestore(); set.mockRestore(); }
  });

  it('is disabled with "Voice is not configured" when no speech base is set', () => {
    render(<Harness uid="user-a" configured={false} />);
    expect(toggle()).toBeDisabled();
    expect(screen.getByText('Voice is not configured')).toBeInTheDocument();
  });

  it('is disabled with "No voice for this companion" for the fox, even if previously on', () => {
    localStorage.setItem(voiceStorageKey('user-a'), 'true');
    render(<Harness uid="user-a" companionHasVoice={false} />);
    expect(toggle()).toBeDisabled();
    expect(toggle()).toHaveAttribute('aria-checked', 'false');
    expect(screen.getByText('No voice for this companion')).toBeInTheDocument();
    expect(voiceCompanion('koi')).toBe('fox');
  });

  it('shows the service note and the status lines only while on', () => {
    const view = render(<VoiceToggle checked onChange={() => undefined} configured companionHasVoice line="speaking" />);
    expect(screen.getByText("Spoken replies are sent to KOI's speech service. Replies in Roman Urdu or mixed script stay text-only.")).toBeInTheDocument();
    expect(screen.getByRole('status')).toHaveTextContent('Speaking...');
    view.rerender(<VoiceToggle checked onChange={() => undefined} configured companionHasVoice line="skipped" />);
    expect(screen.getByRole('status')).toHaveTextContent('Voice skipped for this reply');
    view.rerender(<VoiceToggle checked onChange={() => undefined} configured companionHasVoice line="unavailable" />);
    expect(screen.getByRole('status')).toHaveTextContent('Voice unavailable right now');
    view.rerender(<VoiceToggle checked={false} onChange={() => undefined} configured companionHasVoice line="speaking" />);
    expect(screen.getByRole('status')).toHaveTextContent('');
  });

  it('reads the base URL from NEXT_PUBLIC_KOI_SPEECH_BASE', () => {
    const original = process.env.NEXT_PUBLIC_KOI_SPEECH_BASE;
    try {
      delete process.env.NEXT_PUBLIC_KOI_SPEECH_BASE; expect(speechBaseUrl()).toBe('');
      process.env.NEXT_PUBLIC_KOI_SPEECH_BASE = '  '; expect(speechBaseUrl()).toBe('');
      process.env.NEXT_PUBLIC_KOI_SPEECH_BASE = 'https://speech.test'; expect(speechBaseUrl()).toBe('https://speech.test');
    } finally { if (original === undefined) delete process.env.NEXT_PUBLIC_KOI_SPEECH_BASE; else process.env.NEXT_PUBLIC_KOI_SPEECH_BASE = original; }
  });
});

describe('planReplyVoice language heuristic', () => {
  it.each([
    ['Main theek hoon, aap kaise ho?', 'roman-ur'],
    ['Kya baat hai yaar', 'roman-ur'],
    ['Hello دوست, how are you?', 'mixed'],
    ['', 'empty'],
  ])('keeps %p silent (%s)', (text, reason) => { expect(planReplyVoice(text)).toEqual({ speak: false, reason }); });
  it('speaks English with at most one Roman Urdu word and Urdu script as ur-script', () => {
    expect(planReplyVoice('The main thing is to rest tonight.')).toEqual({ speak: true, languageHint: 'en' });
    expect(planReplyVoice('آپ کیسے ہیں؟')).toEqual({ speak: true, languageHint: 'ur-script' });
  });
});
