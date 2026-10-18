import { render, screen } from '@testing-library/react';
jest.mock('@/components/companion/CompanionScene.module.css', () => ({}));
import CompanionHeader, { companionHeaderTitle } from '../components/companion/CompanionHeader';
import { resolveAvatarPreference } from '../lib/avatar/avatarPreference';

describe('CompanionHeader', () => {
  it.each([
    ['aisha', 'female_human', 'Aisha'],
    ['raza', 'male_human', 'Raza'],
    ['koi', 'fox', 'KOI'],
  ] as const)('%s: title is the companion, subtitle and back label are consistent', (companion, avatar, title) => {
    const name = companionHeaderTitle(resolveAvatarPreference({ companion, avatar }));
    expect(name).toBe(title);
    const { container } = render(<CompanionHeader name={name} onBack={() => {}} settingsOpen={false} />);
    expect(screen.getByRole('heading', { level: 1 })).toHaveTextContent(new RegExp(`^${title}$`));
    expect(screen.getByText('Avatar conversation')).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Back to chat' })).toBeInTheDocument();
    expect(container.textContent).not.toMatch(/sandbox/i);
    if (title !== 'KOI') expect(container.textContent).not.toMatch(/KOI/);
  });

  it('unselected or not-yet-loaded preferences show KOI', () => {
    expect(companionHeaderTitle({ status: 'unselected' })).toBe('KOI');
    expect(companionHeaderTitle(null)).toBe('KOI');
  });
});
