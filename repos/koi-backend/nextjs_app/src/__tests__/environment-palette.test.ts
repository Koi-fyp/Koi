import { readFileSync } from 'fs';
import { environmentEmotion, environmentPalette } from '@/lib/environment/palette';

const expected = [
  ['neutral', '#FFE5D9', '#FFE5D9'], ['joy', '#FFE0A3', '#FFE2B8'],
  ['angry', '#E0C3D3', '#EDD1D6'], ['sorrow', '#CBC5DD', '#E0D2DC'],
  ['fun', '#CBE1BF', '#E0E2C9'], ['calm', '#C1D9D8', '#DADED8'],
] as const;
const luminance = (hex: string) => {
  const rgb = hex.slice(1).match(/../g)!.map(v => parseInt(v, 16) / 255)
    .map(v => v <= 0.04045 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4);
  return rgb[0] * 0.2126 + rgb[1] * 0.7152 + rgb[2] * 0.0722;
};
it.each(expected)('%s matches both approved tints and passes body contrast', (mood, call, chat) => {
  expect(environmentPalette.call[mood]).toBe(call);
  expect(environmentPalette.chat[mood]).toBe(chat);
  for (const color of [call, chat]) expect((luminance(color) + 0.05) / (luminance('#4B5563') + 0.05)).toBeGreaterThanOrEqual(4.5);
});
it.each(['happy', 'sad', 'anxious', 'calm', 'unknown', '', null, undefined, {}])('rejects non-avatar emotion %p', value => {
  expect(environmentEmotion(value)).toBe('neutral');
});
it('declares the exact transition and reduced-motion override', () => {
  const css = readFileSync('src/app/globals.css', 'utf8');
  expect(css).toMatch(/\.environment-background\s*\{\s*transition: background-color 1\.8s ease-in-out;/);
  expect(css).toMatch(/@media\s*\(prefers-reduced-motion: reduce\)\s*\{\s*\.environment-background\s*\{\s*transition: none;/);
});
