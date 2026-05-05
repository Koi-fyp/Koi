import { db } from '../db';
import { cryptoService } from '../crypto';
import type { Message } from '../../models/index';

export class MessageRepository {
  async save(message: Message): Promise<void> {
    const toStore: Message = {
      ...message,
      content: await cryptoService.encrypt(message.content),
    };
    await db.messages.put(toStore);
  }

  async getById(id: string): Promise<Message | undefined> {
    const msg = await db.messages.get(id);
    if (!msg) return undefined;
    return { ...msg, content: await cryptoService.decrypt(msg.content) };
  }

  async getByConversation(conversationId: string): Promise<Message[]> {
    const msgs = await db.messages
      .where('conversationId')
      .equals(conversationId)
      .sortBy('timestamp');
    return Promise.all(
      msgs.map(async (m) => ({ ...m, content: await cryptoService.decrypt(m.content) })),
    );
  }

  async getUnsynced(): Promise<Message[]> {
    const msgs = await db.messages.where('synced').equals(0).toArray();
    return Promise.all(
      msgs.map(async (m) => ({ ...m, content: await cryptoService.decrypt(m.content) })),
    );
  }

  async markSynced(id: string): Promise<void> {
    await db.messages.update(id, { synced: true });
  }

  async markAllSynced(ids: string[]): Promise<void> {
    await db.transaction('rw', db.messages, async () => {
      for (const id of ids) {
        await db.messages.update(id, { synced: true });
      }
    });
  }

  async deleteByConversation(conversationId: string): Promise<void> {
    await db.messages.where('conversationId').equals(conversationId).delete();
  }

  async delete(id: string): Promise<void> {
    await db.messages.delete(id);
  }
}

export const messageRepository = new MessageRepository();
