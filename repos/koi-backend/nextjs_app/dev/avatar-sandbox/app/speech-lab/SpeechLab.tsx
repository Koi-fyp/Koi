'use client';
import { useEffect, useState, useSyncExternalStore } from 'react';
import { useRouter } from 'next/navigation';
import CompanionScene from '@/components/companion/CompanionScene';
import { SpeechPlayback } from '@/lib/speech/SpeechPlayback';
import { parseSpeechSample, type SpeechSample } from '@/lib/speech/speechSample';
import type { KoiEmotion } from '@/components/avatar/VRMAvatarController';
const SAMPLES = { 'speech-sample': '6A baseline: Windows David / manual cues', 'piper-urdu': 'Piper Urdu / real Rhubarb phonetic cues', 'piper-english': 'English probe (Urdu voice) / real Rhubarb cues', 'piper-mixed': 'Mixed-language probe / real Rhubarb cues' } as const;
type SampleId = keyof typeof SAMPLES;
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
function PlaybackScene({ playback, model, setModel, sample, metadata, changeSample, error }: { playback: SpeechPlayback; model: 'male' | 'female'; setModel: (value: 'male' | 'female') => void; sample: SampleId; metadata: SpeechSample | null; changeSample: (sample: SampleId) => void; error: string | null }) {
  const snapshot = useSyncExternalStore(playback.subscribe, playback.getSnapshot, playback.getSnapshot);
  const [ready, setReady] = useState(false), [emotion, setEmotion] = useState<KoiEmotion>('neutral');
  const router = useRouter();
  const leave = () => { playback.stop(); router.push('/'); };
  return <CompanionScene companionName={model === 'male' ? 'Raza' : 'Aisha'} modelUrl={`/models/koi-${model}.vrm`} exposeController
    emotion={emotion} emotionIntensity={0.7} conversationState={snapshot.state === 'playing' ? 'speaking' : 'idle'} speechSource={playback}
    onAvatarReady={() => setReady(true)} onAvatarFailure={() => { playback.stop(); setReady(false); }}
    messages={[]} subtitle={metadata?.transcript ?? 'Loading selected local sample...'} subtitleLanguage={metadata?.language === 'ur' || metadata?.language === 'ur-en' ? 'ur' : 'en'} onBack={leave} onEnd={leave}
    notice={!metadata ? 'Development-only: selected audio is unavailable or loading. No audio is playing.' : metadata.kind === 'rhubarb' ? 'Development-only: actual Piper audio and Rhubarb cues. Pronunciation/alignment quality not human-evaluated.' : 'Development-only baseline: Windows David audio and manually authored approximate cues.'}
    composer={<><label style={{ display: 'block', textAlign: 'center', marginBottom: 6 }}>Speech sample <select aria-label="Speech sample" style={{ maxWidth: '100%' }} value={sample} onChange={(event) => changeSample(event.target.value as SampleId)}>{Object.entries(SAMPLES).map(([id, label]) => <option key={id} value={id}>{label}</option>)}</select></label>
      {error && <p role="alert" style={{ textAlign: 'center' }}>{error}</p>}
      <PlaybackControls playback={playback} ready={ready && metadata !== null} /><p style={{ textAlign: 'center', margin: '6px 0 0', fontSize: 11 }}>Use headphones if desired. No microphone, camera or chat service.</p></>}
    settings={<>{metadata?.kind === 'rhubarb' && <p>Voice: {metadata.voice} (male voice for both avatar previews). Synthesis: {metadata.synthesisSeconds?.toFixed(2)} s; cues: {metadata.cueExtractionSeconds?.toFixed(2)} s.</p>}<label>Preview model<select aria-label="Preview model" value={model} onChange={(event) => { playback.stop(); setReady(false); setModel(event.target.value as 'male' | 'female'); }}><option value="male">Male</option><option value="female">Female</option></select></label>
      <label>Emotion<select aria-label="Speech emotion" value={emotion} onChange={(event) => setEmotion(event.target.value as KoiEmotion)}>{['neutral', 'joy', 'angry', 'sorrow', 'fun'].map((value) => <option key={value}>{value}</option>)}</select></label></>} />;
}
export default function SpeechLab() {
  const [playback, setPlayback] = useState<SpeechPlayback | null>(null), [error, setError] = useState<string | null>(null);
  const [model, setModel] = useState<'male' | 'female'>('male');
  const [sample, setSample] = useState<SampleId>('speech-sample'), [metadata, setMetadata] = useState<SpeechSample | null>(null);
  useEffect(() => {
    const player = new SpeechPlayback(); window.__koiSpeechLab = player; setPlayback(player);
    return () => { player.dispose(); if (window.__koiSpeechLab === player) delete window.__koiSpeechLab; };
  }, []);
  useEffect(() => {
    if (!playback) return;
    const abort = new AbortController(); playback.stop(); setMetadata(null); setError(null);
    void fetch(`/speech-fixture/${sample}.json`, { signal: abort.signal }).then(async (response) => {
      if (!response.ok) throw new Error('fixture');
      const data = parseSpeechSample(await response.json()); abort.signal.throwIfAborted();
      playback.load({ audioUrl: `/speech-fixture/${sample}.wav${data.kind === 'rhubarb' ? `?sha256=${data.sha256}` : ''}`, mouthCues: data.mouthCues }); setMetadata(data);
    }).catch(() => { if (!abort.signal.aborted) setError(sample === 'speech-sample' ? 'Generate the baseline: powershell -File scripts/create-speech-fixture.ps1' : 'Generate real samples: python scripts/generate-piper-samples.py'); });
    return () => { abort.abort(); playback.stop(); };
  }, [playback, sample]);
  if (!playback) return <main className="sandbox"><p role="status">Loading local speech fixture...</p></main>;
  return <PlaybackScene playback={playback} model={model} setModel={setModel} sample={sample} metadata={metadata} error={error} changeSample={(value) => { if (value === sample) return; playback.stop(); setMetadata(null); setSample(value); }} />;
}
