import 'fake-indexeddb/auto';
import { db } from '../../lib/db';
import { MoodRepository } from '../../lib/repositories/mood_repository';
import type { MoodEntry } from '../../models/index';

function makeEntry(id: string, userId: string, timestamp: Date): MoodEntry {
  return {
    id, userId, timestamp,
    mood_rating: 3, connection_rating: 3, energy_rating: 3,
    loneliness_score: 0.5, synced: false,
  };
}

describe('MoodRepository', () => {
  let repo: MoodRepository;

  beforeEach(() => { repo = new MoodRepository(); });
  afterEach(async () => { await db.moodEntries.clear(); });

  it('saves and retrieves an entry', async () => {
    await repo.save(makeEntry('e1', 'user1', new Date('2024-01-01')));
    const found = await repo.getById('e1');
    expect(found!.mood_rating).toBe(3);
  });

  it('getByUser returns entries for that user only', async () => {
    await repo.save(makeEntry('e2', 'user2', new Date('2024-01-01')));
    await repo.save(makeEntry('e3', 'user2', new Date('2024-01-02')));
    await repo.save(makeEntry('e4', 'user3', new Date('2024-01-01')));
    expect((await repo.getByUser('user2')).length).toBe(2);
  });

  it('getUnsynced returns only unsynced entries', async () => {
    await repo.save(makeEntry('e5', 'user4', new Date()));
    await repo.save({ ...makeEntry('e6', 'user4', new Date()), synced: true });
    const unsynced = await repo.getUnsynced();
    expect(unsynced.length).toBe(1);
    expect(unsynced[0].id).toBe('e5');
  });

  it('markSynced updates flag', async () => {
    await repo.save(makeEntry('e7', 'user5', new Date()));
    await repo.markSynced('e7');
    expect((await repo.getById('e7'))!.synced).toBe(true);
  });

  it('delete removes entry', async () => {
    await repo.save(makeEntry('e8', 'user6', new Date()));
    await repo.delete('e8');
    expect(await repo.getById('e8')).toBeUndefined();
  });
});
