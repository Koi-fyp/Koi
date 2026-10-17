import { resolveAvatarPreference } from '@/lib/avatar/avatarPreference';

describe('avatar preference resolver', () => {
  it('maps Aisha to the actual female PNG and VRM', () => {
    expect(resolveAvatarPreference({ companion: 'aisha', avatar: 'female_human' })).toMatchObject({
      status: 'selected', companion: 'aisha', avatar: 'female_human', imageSrc: '/Female.png', modelUrl: '/models/koi-female.vrm',
    });
  });

  it('uses the canonical companion to repair old skipped-step mismatches', () => {
    expect(resolveAvatarPreference({ companion: 'aisha', avatar: 'fox' })).toMatchObject({ avatar: 'female_human', modelUrl: '/models/koi-female.vrm' });
    expect(resolveAvatarPreference({ companion: 'raza', avatar: 'female_human' })).toMatchObject({ avatar: 'male_human', modelUrl: '/models/koi-male.vrm' });
  });

  it('maps Raza to the male representation and preserves Koi as an unavailable fox', () => {
    expect(resolveAvatarPreference({ companion: 'raza' })).toMatchObject({ imageSrc: '/Male.png', modelUrl: '/models/koi-male.vrm' });
    expect(resolveAvatarPreference({ companion: 'koi', avatar: 'fox' })).toMatchObject({ avatar: 'fox', imageSrc: null, modelUrl: null });
  });

  it('supports explicit avatar-only legacy profiles and never guesses for missing data', () => {
    expect(resolveAvatarPreference({ avatar: 'female_human' })).toMatchObject({ companion: 'aisha' });
    expect(resolveAvatarPreference(undefined)).toEqual({ status: 'unselected' });
    expect(resolveAvatarPreference({ avatar: undefined, companion: undefined })).toEqual({ status: 'unselected' });
  });
});
