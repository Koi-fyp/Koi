/** @jest-environment node */
import { POST as anonHandler } from '@/app/api/auth/anonymous/route';
import { POST as linkEmailHandler } from '@/app/api/auth/link-email/route';
import { NextRequest } from 'next/server';

// Mock firebase-admin with comprehensive mocks
jest.mock('@/lib/firebase-admin', () => {
  const mockFieldValue = {
    serverTimestamp: jest.fn().mockReturnValue({ _type: 'serverTimestamp' }),
  };

  const mockAuth = {
    createCustomToken: jest.fn().mockResolvedValue('test-custom-token-123'),
    verifyIdToken: jest.fn().mockResolvedValue({ uid: 'test-user-123', email: 'user@example.com' }),
    updateUser: jest.fn().mockResolvedValue({ uid: 'test-user-123', email: 'test@example.com' }),
    generateEmailVerificationLink: jest.fn().mockResolvedValue('https://test-verification-link.com'),
  };

  const mockFirestore = {
    collection: jest.fn().mockReturnValue({
      doc: jest.fn().mockReturnValue({
        set: jest.fn().mockResolvedValue({}),
        get: jest.fn().mockResolvedValue({
          exists: true,
          data: () => ({ uid: 'test-user-123', koiUuid: 'uuid-123', email: null }),
        }),
        update: jest.fn().mockResolvedValue({}),
      }),
    }),
  };

  const mockAdmin = {
    firestore: {
      FieldValue: mockFieldValue,
      Timestamp: { now: jest.fn() },
    },
  };

  return {
    admin: mockAdmin,
    adminAuth: mockAuth,
    adminFirestore: mockFirestore,
  };
});

describe('Auth API Routes', () => {
  describe('POST /api/auth/anonymous', () => {
    it('creates an anonymous session and returns userId and token', async () => {
      const req = new NextRequest(new URL('http://localhost:3000/api/auth/anonymous'), {
        method: 'POST',
      });

      const res = await anonHandler(req);
      const data = await res.json();

      expect(res.status).toBe(201);
      expect(data).toHaveProperty('userId');
      expect(data).toHaveProperty('token');
      expect(data.token).toBe('test-custom-token-123');
    });
  });

  describe('POST /api/auth/link-email', () => {
    it('links email and password to existing anonymous user', async () => {
      const body = JSON.stringify({
        email: 'user@example.com',
        password: 'password123',
      });

      const req = new NextRequest(new URL('http://localhost:3000/api/auth/link-email'), {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer test-id-token-123',
        },
        body,
      });

      const res = await linkEmailHandler(req);
      const data = await res.json();

      expect(res.status).toBe(200);
      expect(data).toHaveProperty('verificationLink');
      expect(data).toHaveProperty('emailVerified', false);
    });

    it('rejects requests without Authorization header', async () => {
      const body = JSON.stringify({
        email: 'user@example.com',
        password: 'password123',
      });

      const req = new NextRequest(new URL('http://localhost:3000/api/auth/link-email'), {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
        body,
      });

      const res = await linkEmailHandler(req);
      expect(res.status).toBe(401);
    });

    it('requires both email and password in request body', async () => {
      const body = JSON.stringify({
        email: 'user@example.com',
        // password missing
      });

      const req = new NextRequest(new URL('http://localhost:3000/api/auth/link-email'), {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer test-id-token-123',
        },
        body,
      });

      const res = await linkEmailHandler(req);
      expect(res.status).toBe(400);
    });
  });
});
