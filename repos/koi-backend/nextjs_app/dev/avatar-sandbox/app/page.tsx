import Link from 'next/link';
export default function SandboxHome() {
  return <main className="sandbox"><h1>KOI development sandbox</h1><p className="intro">Development-only previews. No Firebase or backend required.</p>
    <p><Link href="/companion-scene">Open mock conversation</Link></p><p><Link href="/mock-chat">Open mock JSON chat</Link></p><p><Link href="/avatar-viewer">Open avatar viewer</Link></p></main>;
}
