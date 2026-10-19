import 'server-only';
import type { NextRequest } from 'next/server';
import type { Auth } from 'firebase-admin/auth';
import type { Firestore } from 'firebase-admin/firestore';
import { firestoreStore } from './firestore-store';
import { PlatformService, type Actor } from './service';
import { LifecycleService } from './lifecycle';
import { PlatformError, unavailable } from './errors';
import { checkSchema } from './contract';

export interface Runtime { service: PlatformService; authenticate: (req: NextRequest) => Promise<Actor> }
export function getPlatformRuntime(): Runtime {
  let services: { auth: Auth; db: Firestore; config: { project: string; cursorKey: string } };
  try { services = require('./admin-config.cjs').getPlatformAdmin(); } catch { throw unavailable(); }
  const { auth, db, config } = services;
  return {
    service: new LifecycleService(firestoreStore(db), config.cursorKey),
    authenticate: async req => {
      const bearer = req.headers.get('authorization')?.match(/^Bearer ([^\s]+)$/);
      if (!bearer || bearer[1].length > 16000) throw new PlatformError(401, 'unauthenticated');
      try {
        const decoded = await auth.verifyIdToken(bearer[1], true);
        if (decoded.aud !== config.project || decoded.iss !== `https://securetoken.google.com/${config.project}` || decoded.uid !== decoded.sub) throw new Error('Identity project mismatch');
        checkSchema('Uid', decoded.uid);
        return { uid: decoded.uid, authTime: decoded.auth_time };
      } catch { throw new PlatformError(401, 'unauthenticated'); }
    },
  };
}
