import Link from 'next/link';
import { notFound } from 'next/navigation';
import VRMAvatarRenderer from '@/components/avatar/VRMAvatarRenderer';

export default function AvatarSandbox() {
  if (process.env.NODE_ENV !== 'development') notFound();
  return (
    <main className="sandbox">
      <header><span className="brand">KOI</span><span className="badge">Development only</span></header>
      <h1>Your companion, in 3D.</h1>
      <p className="intro">Male VRM viewer &middot; Local assets &middot; No account required</p>
      <section className="stage" aria-label="KOI male avatar viewer">
        <VRMAvatarRenderer />
      </section>
      <p className="note"><Link href="/">Back to sandbox</Link></p>
    </main>
  );
}
