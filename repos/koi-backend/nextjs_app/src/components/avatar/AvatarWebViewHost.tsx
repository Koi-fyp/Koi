'use client';

import { useState } from 'react';
import VRMAvatarRenderer from './VRMAvatarRenderer';
import styles from './AvatarWebViewHost.module.css';

const MODEL_URLS = {
  male: '/models/koi-male.vrm',
  female: '/models/koi-female.vrm',
} as const;

export type AvatarHostModel = keyof typeof MODEL_URLS;

export default function AvatarWebViewHost({ initialModel = 'male' }: { initialModel?: AvatarHostModel }) {
  const [model, setModel] = useState<AvatarHostModel>(initialModel);
  const [ready, setReady] = useState(false);

  return (
    <main className={styles.host} data-testid="avatar-host" data-model={model}>
      <section className={styles.stage} aria-label="KOI companion avatar">
        <VRMAvatarRenderer
          modelUrl={MODEL_URLS[model]}
          minHeight={0}
          maxPixelRatio={1.25}
          exposeController
          notifyKoiBridgeOnReady
          onReady={() => setReady(true)}
          onLoadError={() => setReady(false)}
        />
      </section>
      <div className={styles.toolbar}>
        <label className={styles.modelPicker}>
          <span>Companion</span>
          <select
            aria-label="Companion model"
            value={model}
            onChange={(event) => {
              setReady(false);
              setModel(event.target.value as AvatarHostModel);
            }}
          >
            <option value="male">Raza</option>
            <option value="female">Aisha</option>
          </select>
        </label>
        <span className={styles.status} role="status" aria-live="polite" data-ready={ready}>
          {ready ? 'Avatar ready' : 'Loading avatar'}
        </span>
      </div>
    </main>
  );
}
