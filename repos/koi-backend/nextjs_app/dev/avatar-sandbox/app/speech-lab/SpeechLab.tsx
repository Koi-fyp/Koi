'use client';
import { useEffect, useState, useSyncExternalStore } from 'react';
import { useRouter } from 'next/navigation';
import CompanionScene from '@/components/companion/CompanionScene';
import { SpeechPlayback } from '@/lib/speech/SpeechPlayback';
import { parseMouthCues } from '@/lib/speech/mouthCues';
import type { KoiEmotion } from '@/components/avatar/VRMAvatarController';
declare global { interface Window { __koiSpeechLab?: SpeechPlayback; } }
function PlaybackControls({ playback, ready }: { playback: SpeechPlayback; ready: boolean }) {
  const snapshot = useSyncExternalStore(playback.subscribe, playback.getSnapshot, playback.getSnapshot);
  return <div style={{ display: 'flex', flexWrap: 'wrap', gap: 8, alignItems: 'center', justifyContent: 'center' }}>
    <button disabled={!ready || snapshot.state === 'playing' || snapshot.state === 'loading'} onClick={() => void playback.play()}>{snapshot.state === 'paused' ? 'Resume' : 'Play sample'}</button>
    <button disabled={!['playing', 'loading'].includes(snapshot.state)} onClick={() => playback.pause()}>Pause</button>
    <button onClick={() => playback.stop()}>Stop</button>
    <output aria-label="Playback state" data-playback-state={snapshot.state}>{snapshot.state} | {snapshot.time.toFixed(2)} / {snapshot.duration.toFixed(2)} s</output>
    {snapshot.error && <span role="alert">{snapshot.error}</span>}
  </div>;
}
function PlaybackScene({ playback, model, setModel }: { playback: SpeechPlayback; model: 'male' | 'female'; setModel: (value: 'male' | 'female') => void }) {
  const snapshot = useSyncExternalStore(playback.subscribe, playback.getSnapshot, playback.getSnapshot);
  const [ready, setReady] = useState(false), [emotion, setEmotion] = useState<KoiEmotion>('neutral');
  const router = useRouter();
  const leave = () => { playback.stop(); router.push('/'); };
  return <CompanionScene companionName={model === 'male' ? 'Raza' : 'Aisha'} modelUrl={`/models/koi-${model}.vrm`} exposeController
    emotion={emotion} emotionIntensity={0.7} conversationState={snapshot.state === 'playing' ? 'speaking' : 'idle'} speechSource={playback}
    onAvatarReady={() => setReady(true)} onAvatarFailure={() => { playback.stop(); setReady(false); }}
    messages={[]} subtitle="Ah. Ee. Oh. Ooh. Hello. I am Koi." onBack={leave} onEnd={leave}
    notice="Development-only local audio. Approximate authored mouth cues; not Rhubarb or deployed TTS."
    composer={<><PlaybackControls playback={playback} ready={ready} /><p style={{ textAlign: 'center', margin: '6px 0 0', fontSize: 11 }}>Use headphones if desired. No microphone, camera or chat service.</p></>}
    settings={<><label>Preview model<select aria-label="Preview model" value={model} onChange={(event) => { playback.stop(); setReady(false); setModel(event.target.value as 'male' | 'female'); }}><option value="male">Male</option><option value="female">Female</option></select></label>
      <label>Emotion<select aria-label="Speech emotion" value={emotion} onChange={(event) => setEmotion(event.target.value as KoiEmotion)}>{['neutral', 'joy', 'angry', 'sorrow', 'fun'].map((value) => <option key={value}>{value}</option>)}</select></label></>} />;
}
export default function SpeechLab() {
  const [playback, setPlayback] = useState<SpeechPlayback | null>(null), [error, setError] = useState<string | null>(null);
  const [model, setModel] = useState<'male' | 'female'>('male');
  useEffect(() => {
    const player = new SpeechPlayback(), abort = new AbortController();
    void fetch('/speech-fixture/speech-sample.json', { signal: abort.signal }).then(async (response) => {
      if (!response.ok) throw new Error('fixture');
      const data = await response.json(); abort.signal.throwIfAborted();
      player.load({ audioUrl: '/speech-fixture/speech-sample.wav', mouthCues: parseMouthCues(data.mouthCues) }); window.__koiSpeechLab = player; setPlayback(player);
    }).catch(() => { if (!abort.signal.aborted) setError('Generate the local fixture: powershell -File scripts/create-speech-fixture.ps1'); });
    return () => { abort.abort(); player.dispose(); if (window.__koiSpeechLab === player) delete window.__koiSpeechLab; };
  }, []);
  if (error) return <main className="sandbox"><h1>Local speech fixture unavailable</h1><p role="alert">{error}</p><a href="/">Back to sandbox</a></main>;
  if (!playback) return <main className="sandbox"><p role="status">Loading local speech fixture...</p></main>;
  return <PlaybackScene playback={playback} model={model} setModel={setModel} />;
}
