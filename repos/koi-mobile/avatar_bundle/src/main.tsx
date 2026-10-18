// Mobile entry: does what repos/koi-backend/nextjs_app/src/app/avatar-host/page.tsx
// does (feat/avatar-webview-host 223e97c) — read ?model=, mount the host,
// nothing else. `female` picks female; anything else picks male.
import './base.css';
import { createRoot } from 'react-dom/client';
import AvatarWebViewHost, { type AvatarHostModel } from './components/avatar/AvatarWebViewHost';

// Older Android WebViews (< Chromium 93) lack Object.hasOwn, which
// VRMAvatarController.ts uses.
if (!Object.hasOwn) Object.defineProperty(Object, 'hasOwn', { value: (o: object, k: PropertyKey) => Object.prototype.hasOwnProperty.call(o, k), configurable: true, writable: true });

const model: AvatarHostModel = new URLSearchParams(window.location.search).get('model') === 'female' ? 'female' : 'male';
createRoot(document.getElementById('root')!).render(<AvatarWebViewHost model={model} />);
