/** @jest-environment node */
const mockAuth={},mockDb={},mockInitialize=jest.fn();
const mockAdmin={apps:[] as any[],app:jest.fn(),initializeApp:mockInitialize,credential:{cert:jest.fn(()=>({}))}};
jest.mock('firebase-admin',()=>({__esModule:true,default:mockAdmin}));
import { getAdminServices } from '@/lib/firebase-admin';
const defaultApp={name:'[DEFAULT]',auth:()=>mockAuth,firestore:()=>mockDb};
beforeEach(()=>{jest.clearAllMocks();process.env.FIREBASE_ADMIN_SDK=JSON.stringify({project_id:'koi-companion-fyp',private_key:'fixture'});mockInitialize.mockReturnValue(defaultApp);});
it('initializes the companion default app when only the platform named app exists',()=>{mockAdmin.apps=[{name:'koi-platform-server-web1'}];expect(getAdminServices()).toEqual({adminAuth:mockAuth,adminFirestore:mockDb});expect(mockInitialize).toHaveBeenCalledTimes(1);expect(mockAdmin.app).not.toHaveBeenCalled();});
it('reuses the existing companion default app and leaves the named app alone',()=>{mockAdmin.apps=[{name:'koi-platform-server-web1'},defaultApp];expect(getAdminServices().adminAuth).toBe(mockAuth);expect(mockInitialize).not.toHaveBeenCalled();});
