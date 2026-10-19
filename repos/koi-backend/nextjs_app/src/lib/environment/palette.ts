export type AvatarEnvironmentEmotion = 'neutral' | 'joy' | 'angry' | 'sorrow' | 'fun';
export type EnvironmentMood = AvatarEnvironmentEmotion | 'calm';
export const environmentPalette = {
  call: { neutral: '#FFE5D9', joy: '#FFE0A3', angry: '#E0C3D3', sorrow: '#CBC5DD', fun: '#CBE1BF', calm: '#C1D9D8' },
  chat: { neutral: '#FFE5D9', joy: '#FFE2B8', angry: '#EDD1D6', sorrow: '#E0D2DC', fun: '#E0E2C9', calm: '#DADED8' },
} as const;
export function environmentEmotion(value: unknown): AvatarEnvironmentEmotion {
  return typeof value === 'string' && ['neutral', 'joy', 'angry', 'sorrow', 'fun'].includes(value)
    ? value as AvatarEnvironmentEmotion : 'neutral';
}
