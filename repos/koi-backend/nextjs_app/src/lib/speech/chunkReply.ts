export type ChunkClass = 'ur-script' | 'latin' | 'mixed' | 'empty';
/** What the chat layer knows about the reply. Roman Urdu is Latin script and cannot be told apart from English here. */
export type ReplyLanguageHint = 'ur-script' | 'en' | 'roman-ur' | 'unknown';
export const MIN_CHUNK_CHARS = 20, MAX_CHUNK_CHARS = 450;
// Letters only: Arabic-script punctuation (، ؟ ۔) and digits are neutral, like ASCII digits and punctuation.
const ARABIC_LETTER = /[ؠ-يٮ-ۓەۮۯۺ-ۿݐ-ݿࢠ-ࣿﭐ-﷿ﹰ-ﻼ]/;
const LATIN_LETTER = /[A-Za-zÀ-ÖØ-öø-ɏḀ-ỿ]/;
const LATIN_STOP = '.?!', URDU_STOP = '۔؟', CLOSERS = '"\')]»”’';
export function classifyChunk(text: string): ChunkClass {
  let urdu = false, latin = false;
  for (const char of text) { if (ARABIC_LETTER.test(char)) urdu = true; else if (LATIN_LETTER.test(char)) latin = true; if (urdu && latin) return 'mixed'; }
  return urdu ? 'ur-script' : latin ? 'latin' : 'empty';
}
/** Only single-script chunks are sent; a Roman Urdu reply is never read out by an English voice. */
export function speakable(text: string, replyLanguageHint?: ReplyLanguageHint): boolean {
  if (replyLanguageHint === 'roman-ur') return false;
  const kind = classifyChunk(text);
  return kind === 'ur-script' || kind === 'latin';
}
function sentences(text: string): string[] {
  const out: string[] = []; let start = 0;
  for (let i = 0; i < text.length; i++) {
    const char = text[i], urdu = URDU_STOP.includes(char);
    if (!urdu && !LATIN_STOP.includes(char)) continue;
    let end = i + 1;
    while (end < text.length && (LATIN_STOP.includes(text[end]) || URDU_STOP.includes(text[end]) || CLOSERS.includes(text[end]))) end++;
    // Latin stops need following space/end ("3.5", "e.g.x" stay whole); Urdu stops always end a sentence.
    if (!urdu && end < text.length && text[end] !== ' ') { i = end - 1; continue; }
    out.push(text.slice(start, end).trim()); start = end; i = end - 1;
  }
  out.push(text.slice(start).trim());
  return out.filter(Boolean);
}
function splitLong(text: string, max: number): string[] {
  const out: string[] = [];
  while (text.length > max) {
    const head = text.slice(0, max + 1);
    const clause = Math.max(head.lastIndexOf(', '), head.lastIndexOf('، '), head.lastIndexOf('; '));
    const space = head.lastIndexOf(' ');
    const cut = clause >= max / 2 ? clause + 1 : space > 0 ? space : max;
    out.push(text.slice(0, cut).trim()); text = text.slice(cut).trim();
  }
  if (text) out.push(text);
  return out;
}
const compatible = (a: string, b: string) => { const x = classifyChunk(a), y = classifyChunk(b); return x === y || x === 'empty' || y === 'empty'; };
/**
 * Splits a finished reply into sentence chunks. Fragments under 20 chars merge into a same-script neighbour
 * (never across scripts, which would make both unspeakable); nothing exceeds maxChars (<= 450), split at a space.
 */
export function chunkReply(text: string, { maxChars = MAX_CHUNK_CHARS }: { maxChars?: number } = {}): string[] {
  const max = Math.max(MIN_CHUNK_CHARS * 2, Math.min(MAX_CHUNK_CHARS, Math.floor(maxChars) || MAX_CHUNK_CHARS));
  const normalized = typeof text === 'string' ? text.replace(/\s+/g, ' ').trim() : '';
  if (!normalized) return [];
  const pieces = sentences(normalized).flatMap(sentence => splitLong(sentence, max));
  const out: string[] = [];
  for (const piece of pieces) {
    const previous = out[out.length - 1];
    if (previous !== undefined && (previous.length < MIN_CHUNK_CHARS || piece.length < MIN_CHUNK_CHARS)
      && previous.length + 1 + piece.length <= max && compatible(previous, piece)) out[out.length - 1] = `${previous} ${piece}`;
    else out.push(piece);
  }
  return out;
}
