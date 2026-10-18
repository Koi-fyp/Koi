// Copied from repos/koi-backend/nextjs_app/src/components/avatar/AvatarWebViewHost.tsx (branch feat/avatar-webview-host, commit 223e97c).
// Copied, do not edit here: change upstream and re-copy.
'use client';

import VRMAvatarRenderer from './VRMAvatarRenderer';
import styles from './AvatarWebViewHost.module.css';

const MODEL_URLS = {
  male: '/models/koi-male.vrm',
  female: '/models/koi-female.vrm',
} as const;

export type AvatarHostModel = keyof typeof MODEL_URLS;

export default function AvatarWebViewHost({ model = 'male' }: { model?: AvatarHostModel }) {
  return (
    <main className={styles.host} data-testid="avatar-host" data-model={model}>
      <section className={styles.stage} aria-label="KOI companion avatar">
        <VRMAvatarRenderer
          modelUrl={MODEL_URLS[model]}
          minHeight={0}
          maxPixelRatio={1.25}
          exposeController
          notifyKoiBridgeOnReady
          showStatus={false}
        />
      </section>
    </main>
  );
}
