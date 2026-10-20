# WEB-3 local verification

Use the existing WEB-2 emulator setup. No live environment values, provider credentials, production rules or deployment settings changed.

In separate PowerShell sessions, from this application:

```powershell
$env:CI='true'
npx --yes --package firebase-tools@15.34.0 firebase emulators:start --only 'auth,firestore' --project demo-koi-platform-web1 --config dev/platform-emulator/firebase.json
```

For the Next process and functional harness, set:

```powershell
$env:KOI_PLATFORM_MODE='emulator'
$env:KOI_PLATFORM_FIREBASE_PROJECT_ID='demo-koi-platform-web1'
$env:FIRESTORE_EMULATOR_HOST='127.0.0.1:5180'
$env:FIREBASE_AUTH_EMULATOR_HOST='127.0.0.1:5199'
$env:NEXT_PUBLIC_KOI_PLATFORM_FIREBASE_PROJECT_ID='demo-koi-platform-web1'
$env:NEXT_PUBLIC_KOI_PLATFORM_AUTH_EMULATOR_URL='http://127.0.0.1:5199'
npm run dev -- --hostname 127.0.0.1 --port 3107
```

Run `node scripts/web3-emulator-functional.cjs` in the second environment-configured session. The harness guards emulator addresses/project, creates fictional identities using the restricted verification CLI, seeds only fictional General registration, and saves new evidence under `review/web-3/evidence`. It never writes WEB-2 evidence. Chrome or Playwright Chromium is required. The explicitly labelled AI interpretation/failure fixture tests review isolation; no provider is called.

Then run `node scripts/web3-emulator-security.cjs` to verify direct Firestore denial for all new collections and a real Firebase Anonymous Auth directory denial. It uses only the same guarded local emulators.

Manual flow: `/professional` → existing verified account → Manage patients and submissions → save profile with discoverable/accepting settings. `/patient` → existing registered General account → find/select professional → consent/apply → demo payment. Psychologist accepts or invites; assigns a published version. Open a roster conversation for messages/appointment proposals. Patient confirms time or cancels. For rescheduling, cancel then request again. Patient details show scoped submission history and closed-record archival. Notifications and activity have explicit refresh buttons.

No public registration or new seeded production accounts were added. Do not use emulator fixture identities or deny-all emulator rules as deployment evidence. Retain the reviewed-production configuration gate and independently verify published rules, project, IAM, indexes and backend hosting before rollout.

New equality queries use organization/relationship, recipient, or fixed directory scopes plus document-ID pagination. Real production query/index validation remains pending; emulator success is not proof of production index availability.
