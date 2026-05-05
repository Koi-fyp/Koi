import 'fake-indexeddb/auto';
import { db } from '../../lib/db';
import { UserRepository } from '../../lib/repositories/user_repository';
import type { User } from '../../models/index';

function makeUser(id: string): User {
  return {
    id,
    createdAt: new Date('2024-01-01'),
    lastActive: new Date('2024-01-01'),
    profile: { language: 'en' },
    settings: {},
    stats: {
      total_conversations: 0,
      total_check_ins: 0,
      current_streak: 0,
      longest_streak: 0,
      jigsaw_pieces: 0,
    },
  };
}

describe('UserRepository', () => {
  let repo: UserRepository;

  beforeEach(() => { repo = new UserRepository(); });
  afterEach(async () => { await db.users.clear(); });

  it('saves and retrieves a user', async () => {
    await repo.save(makeUser('u1'));
    const found = await repo.getById('u1');
    expect(found).toBeDefined();
    expect(found!.id).toBe('u1');
  });

  it('returns undefined for missing id', async () => {
    expect(await repo.getById('missing')).toBeUndefined();
  });

  it('updates lastActive', async () => {
    const before = new Date('2024-01-01');
    await repo.save({ ...makeUser('u2'), lastActive: before });
    await repo.updateLastActive('u2');
    const updated = await repo.getById('u2');
    expect(updated!.lastActive.getTime()).toBeGreaterThan(before.getTime());
  });

  it('deletes a user', async () => {
    await repo.save(makeUser('u3'));
    await repo.delete('u3');
    expect(await repo.getById('u3')).toBeUndefined();
  });

  it('getAll returns all users', async () => {
    await repo.save(makeUser('u4'));
    await repo.save(makeUser('u5'));
    expect((await repo.getAll()).length).toBe(2);
  });
});
