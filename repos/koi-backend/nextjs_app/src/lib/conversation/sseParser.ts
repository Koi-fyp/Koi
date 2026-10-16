export interface SseFrame { event: string; data: string; }

/** Incremental SSE decoder: transport chunks may split UTF-8 code points or any frame boundary. */
export class SseParser {
  private readonly decoder = new TextDecoder();
  private buffer = '';
  private eventName = '';
  private dataLines: string[] = [];
  private firstLine = true;
  private ended = false;

  push(chunk: Uint8Array): SseFrame[] {
    if (this.ended) return [];
    this.buffer += this.decoder.decode(chunk, { stream: true });
    return this.readLines(false);
  }

  finish(): SseFrame[] {
    if (this.ended) return [];
    this.ended = true;
    this.buffer += this.decoder.decode();
    const frames = this.readLines(true);
    const trailing = this.dispatch();
    return trailing ? [...frames, trailing] : frames;
  }

  private readLines(final: boolean): SseFrame[] {
    const frames: SseFrame[] = [];
    while (this.buffer.length) {
      const match = /\r\n|\r|\n/.exec(this.buffer);
      if (!match) {
        if (final) {
          const line = this.buffer;
          this.buffer = '';
          const frame = this.consumeLine(line);
          if (frame) frames.push(frame);
        }
        break;
      }
      // A trailing CR can be the first half of a CRLF split between chunks.
      if (!final && match[0] === '\r' && match.index === this.buffer.length - 1) break;
      const line = this.buffer.slice(0, match.index);
      this.buffer = this.buffer.slice(match.index + match[0].length);
      const frame = this.consumeLine(line);
      if (frame) frames.push(frame);
    }
    return frames;
  }

  private consumeLine(line: string): SseFrame | null {
    if (this.firstLine) {
      this.firstLine = false;
      line = line.replace(/^\uFEFF/, '');
    }
    if (line === '') return this.dispatch();
    if (line.startsWith(':')) return null;
    const colon = line.indexOf(':');
    const field = colon === -1 ? line : line.slice(0, colon);
    let value = colon === -1 ? '' : line.slice(colon + 1);
    if (value.startsWith(' ')) value = value.slice(1);
    if (field === 'event') this.eventName = value;
    else if (field === 'data') this.dataLines.push(value);
    return null;
  }

  private dispatch(): SseFrame | null {
    if (this.dataLines.length === 0) {
      this.eventName = '';
      return null;
    }
    const frame = { event: this.eventName || 'message', data: this.dataLines.join('\n') };
    this.eventName = '';
    this.dataLines = [];
    return frame;
  }
}
