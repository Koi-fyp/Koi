# FIXES_REPORT (run 2): 2026-10-20

Worktree: E:\Koi\web-final\repos\koi-backend\nextjs_app. RUN PART 2: YES.

## Summary

| Part | Result |
|---|---|
| FIRST RUN | PASS |
| PART 1: live rules script | **BLOCKED-BY-PERMISSION**: Write to `scripts/` denied. File not created, not checked, not committed |
| PART 2: poll budget patch | **BLOCKED-BY-PERMISSION**: Write/Edit to `src/` denied. Nothing applied or committed. Exact patch below |
| FINAL | tsc clean; full suite **688/688 passed** (86 suites) on the **unchanged** tree |

Files changed: **none** (only this gitignored report). Commits: **none**.
The run did not work around the denials.

The denial text in each case was `File is in a directory that is denied by your permission settings.`
It covered: `scripts/web5-rules-security-live.cjs` (Write), `src/lib/platform/poll-config.ts` (Write),
`src/app/api/v1/me/access-events/route.ts` (Edit), and `src/components/platform/PlatformNavigation.tsx` (Edit).
`.claude/settings.json` (or a user/managed settings deny rule) appears to deny writes everywhere except
`.local/` [GUESS: I did not open `.claude/**`]. The run needs write permission for `scripts/` and `src/`.

## FIRST RUN

- [RUN git branch --show-current] `integrate/web-ahmad`
- [RUN git status --short] empty (`.env.test` was removed by Ahmad)
- START = `881cbdb608e58a53b816252a4db3770d3a968e86` [RUN git rev-parse HEAD]
- [RUN node -v] v20.12.2
- [RUN git ls-files --eol public/illustrations] all 3 SVGs `i/lf w/lf attr/-text`. This is as expected.

## PART 1: live rules script (BLOCKED)

- [RUN Glob scripts/web5-rules-security*.cjs] only the original exists, so the spec's step 2 (create) applies.
- I read the original [FILE scripts/web5-rules-security.cjs:1-39]. I prepared a copy with exactly three changes, but the Write was denied:
  1. Line 1 header becomes:
     `// Local test against the LIVE published ruleset (captured 2026-10-20) only: exact loopback emulators, no cloud credential, no AI.`
  2. Old block [FILE scripts/web5-rules-security.cjs:25-32], to be replaced (still inside `if(p.uid){...}`) by the spec's new block, verbatim:
     ```js
           for(const collection of ['users','conversations','mood_entries','wellness_progress','tasks']){
             const sub=collection==='conversations'?'/messages/demo':collection==='mood_entries'?'/entries/demo':collection==='tasks'?'/items/demo':'';
             const own=`${root}/${collection}/${p.uid}${sub}`,foreign=`${root}/${collection}/someone_else${sub}`;
             assert.equal((await fetch(own,{method:'PATCH',headers,body:JSON.stringify({fields:{fictional:{booleanValue:true}}})})).status,200);legacy++;
             assert.equal((await fetch(own,{headers})).status,200);legacy++;
             assert.equal((await fetch(foreign,{headers})).status,403);legacy++;
             assert.equal((await fetch(foreign,{method:'PATCH',headers,body:JSON.stringify({fields:{fictional:{booleanValue:true}}})})).status,403);legacy++;
           }
     ```
     (The new block is the one in the prompt: users/{uid} own PATCH/GET 200, foreign GET/PATCH 403,
     malformed nested message 403, and the 4 legacy roots PATCH 403. That is 9 assertions per authenticated principal, 36 in total.)
  3. The `scope` string at [FILE scripts/web5-rules-security.cjs:35] changes to the live-rules text from the prompt.
     `legacy_preservation_assertions`, `guard()` and every other line stay identical.
- Note: the default `source` (`dev/web5-reference/firestore.rules`, line 9) is unchanged, as the spec asks. So
  `source_sha256` hashes whatever path you pass as argv[2]. Pass `.local/koi-web5/live-before-demo/published.rules`
  explicitly, or the evidence will hash the reference file.
- `node --check`: not run on the new file (it does not exist). STATUS: NOT RUN (it needs emulators, and the file was not created).

## PART 2: Firestore read budget (BLOCKED; analysis done)

### Verified facts
- The stream re-checks every 2 s with a 250 s cap: [FILE src/app/api/v1/me/access-events/route.ts:21] (`> 250000`), [FILE route.ts:29] (`setTimeout(tick, 2000)`).
  Each tick calls `rt.authenticate(req)` and `service.capabilities()` [FILE route.ts:22].
- The nav polls every 5000 ms [FILE src/components/platform/PlatformNavigation.tsx:21]. Hidden tabs do not fetch:
  `refresh` returns early when `document.hidden` [FILE PlatformNavigation.tsx:17].
- `authenticate` calls `verifyIdToken(token, true)` [FILE src/lib/platform/server/runtime.ts:22]. With
  checkRevoked=true, that is a Firebase Auth API call on each tick (not Firestore reads, but still a network call).
- **Important finding:** the client watchdog locks and aborts the stream after **7000 ms without any event**
  [FILE src/lib/platform/access-monitor.ts:15], then reconnects after 1.5 s [FILE access-monitor.ts:34].
  A naive change of the tick to 10 s would cause a lock/reconnect loop every ~7 s. Each reconnect costs 2
  capabilities calls (the `first` call plus an immediate tick), so reads would **go up** and protected screens would flicker.
  My patch therefore keeps a read-free 2 s heartbeat and runs authenticate + capabilities only every `KOI_PLATFORM_ACCESS_POLL_MS`.
- Hidden tabs and the stream: the client already aborts and locks the stream on `visibilitychange` when it becomes hidden or goes offline,
  and does not reconnect while hidden [FILE access-monitor.ts:13,36]. So the stream **already closes for hidden tabs**.

### Reads per capabilities() call [FILE src/lib/platform/server/service.ts:54-79] (estimate from code, not a measurement)
- Always: `tx.get` accounts, psychologist_verifications, organization_owners = **3**.
- Professional owner: plus `tx.get` organizations and organization_memberships = **+2** (lines 65-66).
- General access: plus `tx.query` patient_relationships (limit 201) = **max(1, R)** billed reads (line 73).
- Per active relationship: `authority()` = 4 `tx.get` (accounts, psychologist_verifications, organizations, organization_memberships) [FILE service.ts:28-33] = **+4R**.
- Typical patient with general access and 0 relationships = **4**. With 1 relationship = 3+1+4 = **8**. Unregistered or no general access = **3**.

### Per visible tab-hour (stream + nav both open; 4 reads/call)
Stream connections per hour ≈ 3600 / 251.5 ≈ 14.3. Each one costs 1 `first` call plus its ticks.

| | Stream calls/h | Nav calls/h | Total calls/h | Reads/h @4 | Reads/h @8 |
|---|---|---|---|---|---|
| Current (2 s / 5 s) | ≈14.3 × (1+126) ≈ 1816 | 720 | ≈2536 | ≈10,100 | ≈20,300 |
| New defaults (10 s / 15 s) | ≈14.3 × (1+26) ≈ 386 | 240 | ≈626 | ≈2,500 | ≈5,000 |

That is roughly a 4x reduction. Against the Spark free tier (50,000 reads/day [GUESS: quota from memory, not verified]),
an idle visible tab now uses about 1/20 of the daily quota per hour instead of about 1/5.
Focus and visibilitychange events add extra nav refreshes, which are not counted here.

### Exact patch to apply (prepared; Edit denied)

New file `src/lib/platform/poll-config.ts`:
```ts
/** Client-safe polling intervals. Fail-safe: non-integer input uses the default, out-of-range input is clamped. */
export function parsePollMs(raw: string | undefined, fallback: number, min: number, max: number): number {
  if (raw === undefined || !/^\d+$/.test(raw.trim())) return fallback;
  const value = Number(raw.trim());
  return Number.isSafeInteger(value) ? Math.min(max, Math.max(min, value)) : fallback;
}
/** Server stream: how often capabilities are re-checked (Firestore reads). */
export const accessPollMs = (raw = process.env.KOI_PLATFORM_ACCESS_POLL_MS) => parsePollMs(raw, 10000, 2000, 60000);
/** Navigation: how often /api/v1/me/capabilities is polled while visible. */
export const navPollMs = (raw = process.env.NEXT_PUBLIC_KOI_PLATFORM_NAV_POLL_MS) => parsePollMs(raw, 15000, 5000, 120000);
```
(`process.env.NEXT_PUBLIC_...` is written literally so that Next inlines it in the client bundle.)

`src/app/api/v1/me/access-events/route.ts`:
```diff
 import { hash } from '@/lib/platform/server/contract';
+import { accessPollMs } from '@/lib/platform/poll-config';
 export const runtime = 'nodejs';
 export const dynamic = 'force-dynamic';
+/** Read-free keepalive; must stay well under the client's 7 s stall deadline (access-monitor.ts). */
+const HEARTBEAT_MS = 2000;
@@
-        const encoder = new TextEncoder(), started = Date.now(); let previous = '', sequence = Math.max(1, first.authorization_revision);
+        const encoder = new TextEncoder(), started = Date.now(), pollMs = accessPollMs(); let previous = '', checkedAt = 0, sequence = Math.max(1, first.authorization_revision);
@@
             if (stopped || req.signal.aborted || Date.now() - started > 250000) { close(); return; }
+            if (Date.now() - checkedAt < pollMs) { controller.enqueue(encoder.encode(': heartbeat\n\n')); timer = setTimeout(tick, HEARTBEAT_MS); return; }
+            checkedAt = Date.now();
             const currentActor = await rt.authenticate(req), caps = await rt.service.capabilities(currentActor);
@@
-            timer = setTimeout(tick, 2000);
+            timer = setTimeout(tick, HEARTBEAT_MS);
```
The first tick still checks immediately (`checkedAt = 0`). Loss of `registered` still closes the stream. The 250 s cap is kept.

`src/components/platform/PlatformNavigation.tsx`:
```diff
 import { platformLinks } from '@/lib/platform/navigation';
+import { navPollMs } from '@/lib/platform/poll-config';
@@
-    void refresh(); const timer = setInterval(refresh, 5000);
+    void refresh(); const timer = setInterval(refresh, navPollMs());
```

New test `src/__tests__/platform/poll-config.test.ts`:
```ts
import { accessPollMs, navPollMs, parsePollMs } from '@/lib/platform/poll-config';
it('uses defaults for missing or non-integer input', () => {
  for (const raw of [undefined, '', 'abc', '10.5', '-3000', '1e4']) { expect(accessPollMs(raw)).toBe(10000); expect(navPollMs(raw)).toBe(15000); }
});
it('accepts valid integers', () => { expect(accessPollMs('30000')).toBe(30000); expect(navPollMs(' 20000 ')).toBe(20000); });
it('clamps below the minimum', () => { expect(accessPollMs('100')).toBe(2000); expect(navPollMs('0')).toBe(5000); });
it('clamps above the maximum', () => { expect(accessPollMs('999999')).toBe(60000); expect(navPollMs('999999')).toBe(120000); });
it('falls back when the integer is unsafe', () => { expect(parsePollMs('9'.repeat(20), 7, 1, 10)).toBe(7); });
```

Existing tests: no timing changes are needed (verified by reading them). `lifecycle-routes.test.ts:53-61` reads only
the first chunk, which is still an immediate capabilities check. `navigation.test.tsx` triggers refresh through `focus`, not the
interval. `access-monitor.test.tsx:34` (8001 ms stall) tests the client watchdog, which is unchanged.
Suggested addition (not written): a route test showing that capabilities is not called again within `pollMs` while heartbeats continue.

Commit to use once permitted:
`git add src/lib/platform/poll-config.ts src/app/api/v1/me/access-events/route.ts src/components/platform/PlatformNavigation.tsx src/__tests__/platform/poll-config.test.ts`
then `git commit -m "Web: configurable capability polling (defaults 10s stream / 15s nav) to protect Firestore Spark quota"`.

## FINAL (on START, unchanged tree)

- [RUN npx tsc --noEmit --incremental false] no output (clean).
- [RUN npm test -- --runInBand] `Test Suites: 86 passed, 86 total`, `Tests: 688 passed, 688 total`. The expected 688 is confirmed, and the line-ending fix holds.
  Test runs used: 1 of 2.
- [RUN git status --short] empty. [RUN git log --oneline START..HEAD] empty. [RUN git diff --stat START HEAD] empty.

## Deviations

1. Nothing was written outside `.local/` (permission denials). Parts 1 and 2 were prepared only.
2. Part 2 design deviation (deliberate): `KOI_PLATFORM_ACCESS_POLL_MS` controls the **capabilities and authenticate re-check**
   interval, not the SSE write interval. Heartbeats stay at 2 s because of the client's 7 s watchdog. Revocation
   (token revoked, or capabilities lost) is now detected within ≤ POLL_MS (default 10 s) instead of ≤ 2 s. Server-side
   authorization on every API call is unchanged.

## Decisions for Ahmad

1. **Permissions:** allow Write/Edit for `scripts/web5-rules-security-live.cjs` and the 4 Part 2 paths, then re-run Parts 1 and 2.
   They are fully specified above.
2. **Default intervals:** 10 s stream / 15 s nav is recommended. If the shared Spark quota is tight, 20-30 s for the stream is
   still safe for UI locking, because every API call re-authorizes on the server. Keep the stream ≤ 60 s.
3. **Hidden tabs:** the stream already closes on hidden [FILE access-monitor.ts:36] and does not reconnect while hidden
   [FILE access-monitor.ts:13]. No change needed.
4. **Watchdog coupling:** if you ever want the server heartbeat slower than 2 s, `access-monitor.ts:15` (7000 ms) must change too.
5. **Live rules evidence:** pass the published.rules path as argv[2] so that `source_sha256` matches sha 73d9fbd8….

## PART 2 APPLIED (START 067e274 → 34e432d)

Files changed (4 files, +27 / -3):
- new `src/lib/platform/poll-config.ts` (client-safe, no imports)
- `src/app/api/v1/me/access-events/route.ts`
- `src/components/platform/PlatformNavigation.tsx`
- new `src/__tests__/platform/poll-config.test.ts` (5 tests: defaults/invalid, valid, below min, above max, unsafe integer)

Watchdog check (7 s silence timeout is never hit):
- Client: `access-monitor.ts:15` `if (Date.now() - last > 7000) { lock(); attempt?.abort(); }`; `last` is reset on every `\n\n`-terminated frame, heartbeats included (`access-monitor.ts:29`).
- Server: `route.ts:8` `const HEARTBEAT_MS = 2000;`
  `route.ts:25` `if (Date.now() - checkedAt < pollMs) { controller.enqueue(encoder.encode(': heartbeat\n\n')); timer = setTimeout(tick, HEARTBEAT_MS); return; }`
  `route.ts:34` `timer = setTimeout(tick, HEARTBEAT_MS);` (after a check tick, which also enqueues either `authorization_changed` or a heartbeat).
- So every tick writes a frame, and ticks are 2 s apart. On check ticks the gap is 2 s plus authenticate + capabilities latency, the same as before the change. The poll interval only controls when `checkedAt` lets a check through; it never delays a write. Gap stays about 2 s, well under 7 s.
- First tick: `checkedAt = 0` means an immediate check. 250 s cap (`route.ts:24`), close on loss of `registered`, and close on error are unchanged. The hidden-tab close is client-side and unchanged.

Runs:
- [RUN npx tsc --noEmit --incremental false] clean.
- [RUN npm test -- --runInBand poll-config, lifecycle-routes, navigation, access-monitor] 4 suites / 14 tests passed. navigation.test.tsx prints a React act() warning from the `refresh` catch path (code I did not touch). I did not check whether it also appears before this change, because stash/checkout are not allowed.
- [RUN npm test -- --runInBand --silent] `Test Suites: 87 passed, 87 total`, `Tests: 693 passed, 693 total` (was 86/688; +1 suite, +5 tests).
- Commit `34e432d`, explicit-path `git add` of the 4 files.

Deviations:
1. No existing test needed a timing change, so none was edited.
2. Full run used `--silent` to cut console noise. Counts are unaffected.
3. Git warned about LF→CRLF on the 2 new files (working-copy notice only).
4. The suggested route test (no capabilities re-call within pollMs) was not added. It was not in scope.
