import type { Metadata } from 'next';
import AvatarWebViewHost, { type AvatarHostModel } from '@/components/avatar/AvatarWebViewHost';

export const metadata: Metadata = {
  title: 'KOI Avatar',
  description: 'Presentation-only KOI companion avatar.',
};

/** This route accepts only an allowlisted local model choice and no user data. */
export default function AvatarHostPage({ searchParams }: { searchParams?: { model?: string } }) {
  const initialModel: AvatarHostModel = searchParams?.model === 'female' ? 'female' : 'male';
  return <AvatarWebViewHost initialModel={initialModel} />;
}
