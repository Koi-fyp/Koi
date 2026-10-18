/** @jest-environment jsdom */
import React from 'react';
import { render, screen } from '@testing-library/react';
import type { VRMAvatarRendererProps } from '@/components/avatar/VRMAvatarRenderer';

const mockRendererProps: VRMAvatarRendererProps[] = [];
const mockRendererMounts = { count: 0 };
jest.mock('@/components/companion/CompanionScene.module.css', () => ({}));
jest.mock('@/components/avatar/VRMAvatarRenderer', () => {
  const { useEffect } = jest.requireActual<typeof import('react')>('react');
  return {
    __esModule: true,
    default: function MockVRMAvatarRenderer(props: VRMAvatarRendererProps) {
      mockRendererProps.push(props);
      useEffect(() => { mockRendererMounts.count++; }, []);
      return <div data-testid="vrm-renderer" />;
    },
  };
});

import CompanionScene, { type CompanionSceneProps } from '@/components/companion/CompanionScene';
import type { KoiEmotion } from '@/components/avatar/VRMAvatarController';

const EMOTIONS: KoiEmotion[] = ['neutral', 'joy', 'angry', 'sorrow', 'fun'];
const INTENSITIES = [0, 0.3, 0.7, 1.0];
const baseProps: CompanionSceneProps = {
  companionName: 'Aisha', messages: [], subtitle: '', onBack: () => undefined, onEnd: () => undefined,
};
const lastProps = () => mockRendererProps[mockRendererProps.length - 1];

describe('CompanionScene emotion props reach the VRM renderer', () => {
  const originalResizeObserver = globalThis.ResizeObserver;
  // jsdom has no ResizeObserver; the text panel shown when the avatar is disabled uses one.
  beforeAll(() => { globalThis.ResizeObserver = class { observe() {} unobserve() {} disconnect() {} } as unknown as typeof ResizeObserver; });
  afterAll(() => { globalThis.ResizeObserver = originalResizeObserver; });
  beforeEach(() => { mockRendererProps.length = 0; mockRendererMounts.count = 0; });

  it('passes all 5 emotions x {0, 0.3, 0.7, 1.0} unchanged without remounting the renderer', () => {
    const view = render(<CompanionScene {...baseProps} modelUrl="/models/koi-female.vrm" emotion="neutral" emotionIntensity={0} />);
    for (const emotion of EMOTIONS) {
      for (const intensity of INTENSITIES) {
        view.rerender(<CompanionScene {...baseProps} modelUrl="/models/koi-female.vrm" emotion={emotion} emotionIntensity={intensity} conversationState="speaking" />);
        expect(lastProps().emotion).toBe(emotion);
        expect(Object.is(lastProps().emotionIntensity, intensity)).toBe(true);
        expect(lastProps().conversationState).toBe('speaking');
        expect(lastProps().modelUrl).toBe('/models/koi-female.vrm');
      }
    }
    expect(screen.getAllByTestId('vrm-renderer')).toHaveLength(1);
    expect(mockRendererMounts.count).toBe(1);
  });

  it('does not substitute or normalize values at the scene level', () => {
    render(<CompanionScene {...baseProps} modelUrl="/models/koi-male.vrm" />);
    expect(lastProps().emotion).toBeUndefined();
    expect(lastProps().emotionIntensity).toBeUndefined();
    expect(lastProps().minHeight).toBe(0);
    expect(lastProps().maxPixelRatio).toBe(1.5);
  });

  it.each([['/models/koi-male.vrm'], ['/models/koi-female.vrm'], [undefined]])('passes modelUrl %p through unchanged', (modelUrl) => {
    render(<CompanionScene {...baseProps} modelUrl={modelUrl} emotion="joy" emotionIntensity={0.7} />);
    expect(lastProps().modelUrl).toBe(modelUrl);
  });

  it('does not mount the renderer when avatarEnabled is false and unmounts it when disabled later', () => {
    const view = render(<CompanionScene {...baseProps} modelUrl="/models/koi-female.vrm" emotion="joy" emotionIntensity={1} avatarEnabled={false} />);
    expect(screen.queryByTestId('vrm-renderer')).toBeNull();
    expect(screen.queryByRole('region', { name: 'Companion avatar' })).toBeNull();
    expect(mockRendererProps).toHaveLength(0);
    expect(mockRendererMounts.count).toBe(0);

    view.rerender(<CompanionScene {...baseProps} modelUrl="/models/koi-female.vrm" emotion="joy" emotionIntensity={1} />);
    expect(screen.getByTestId('vrm-renderer')).toBeInTheDocument();
    view.rerender(<CompanionScene {...baseProps} modelUrl="/models/koi-female.vrm" emotion="sorrow" emotionIntensity={0.3} avatarEnabled={false} />);
    expect(screen.queryByTestId('vrm-renderer')).toBeNull();
    expect(lastProps().emotion).toBe('joy');
  });
});

it('renders block-level notice content (product controls) without a DOM nesting warning', () => {
  const errors = jest.spyOn(console, 'error').mockImplementation(() => {});
  try {
    render(<CompanionScene {...baseProps} modelUrl="/models/koi-female.vrm" notice={<><div data-testid="controls"><button type="button">New Chat</button></div>Notice text</>} />);
    expect(screen.getByTestId('controls').parentElement!.tagName).toBe('DIV');
    expect(errors.mock.calls.flat().join(' ')).not.toMatch(/validateDOMNesting|cannot be a descendant|cannot appear as a descendant/);
  } finally { errors.mockRestore(); }
});
