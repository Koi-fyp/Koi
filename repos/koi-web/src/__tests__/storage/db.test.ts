import 'fake-indexeddb/auto';
import { db } from '../../lib/db';

afterEach(async () => {
  await db.close();
});

test('KoiDatabase opens with all 5 tables', () => {
  expect(db.users).toBeDefined();
  expect(db.messages).toBeDefined();
  expect(db.moodEntries).toBeDefined();
  expect(db.cbtSessions).toBeDefined();
  expect(db.tasks).toBeDefined();
});

test('tables start empty', async () => {
  expect(await db.users.count()).toBe(0);
  expect(await db.messages.count()).toBe(0);
  expect(await db.moodEntries.count()).toBe(0);
  expect(await db.cbtSessions.count()).toBe(0);
  expect(await db.tasks.count()).toBe(0);
});
