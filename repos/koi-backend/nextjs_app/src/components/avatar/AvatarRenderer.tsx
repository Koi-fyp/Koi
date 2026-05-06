'use client';
import { useEffect, useRef } from 'react';
import { AvatarAnimator, Emotion } from './AvatarAnimator';

interface AvatarRendererProps {
  emotion: Emotion;
}

const THREE_CDN = 'https://cdnjs.cloudflare.com/ajax/libs/three.js/r128/three.min.js';
const GLB_URL = '/models/fox.glb';

function loadScript(src: string): Promise<void> {
  return new Promise((resolve, reject) => {
    if (document.querySelector(`script[src="${src}"]`)) { resolve(); return; }
    const s = document.createElement('script');
    s.src = src;
    s.onload = () => resolve();
    s.onerror = () => reject(new Error(`Failed to load ${src}`));
    document.head.appendChild(s);
  });
}

export default function AvatarRenderer({ emotion }: AvatarRendererProps) {
  const containerRef = useRef<HTMLDivElement>(null);
  const animatorRef = useRef<AvatarAnimator | null>(null);

  useEffect(() => {
    if (!containerRef.current) return;
    const container = containerRef.current;
    let mounted = true;

    (async () => {
      try {
        await loadScript(THREE_CDN);
        if (!mounted) return;

        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        const THREE = (window as any).THREE;
        if (!THREE) return;

        const animator = new AvatarAnimator(THREE);
        animatorRef.current = animator;
        animator.mount(container);

        // Try GLB — fails silently, sphere persists
        try {
          const res = await fetch(GLB_URL, { method: 'HEAD' });
          if (res.ok) {
            const gltfSrc = 'https://cdn.jsdelivr.net/npm/three@0.128.0/examples/js/loaders/GLTFLoader.js';
            await loadScript(gltfSrc);
            // eslint-disable-next-line @typescript-eslint/no-explicit-any
            const GLTFLoader = (window as any).THREE?.GLTFLoader;
            if (GLTFLoader) animator.loadGLB(GLB_URL, GLTFLoader);
          }
        } catch { /* sphere stays */ }
      } catch { /* no Three.js — render nothing */ }
    })();

    const observer = new ResizeObserver((entries) => {
      const rect = entries[0].contentRect;
      animatorRef.current?.resize(rect.width, rect.height);
    });
    observer.observe(container);

    return () => {
      mounted = false;
      observer.disconnect();
      animatorRef.current?.destroy();
      animatorRef.current = null;
    };
  }, []);

  useEffect(() => {
    animatorRef.current?.setEmotion(emotion);
  }, [emotion]);

  return (
    <div
      ref={containerRef}
      style={{ width: '100%', height: '100%' }}
      aria-hidden="true"
    />
  );
}
