// Functional browser checks against the EXISTING local Next server.
// All care API and sign-in responses are synthetic frontend fixtures. No emulator
// accounts/data are created or read. Every non-fixture write and external request is blocked.
const { chromium } = require('playwright');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const BASE = 'http://127.0.0.1:3107';
const OUT = path.resolve(__dirname, '../.local/care-interactions');
const stamp = new Date().toISOString();
const content = { kind: 'custom_questionnaire', validation_status: 'not_validated', origin: 'manual', locales: ['en', 'ur'], title: { en: 'Fixture form 1', ur: '\u0646\u0645\u0648\u0646\u06c1' }, questions: [{ id: 'fixture-question', type: 'short_text', prompt: { en: 'Fixture response', ur: '\u0633\u0648\u0627\u0644' }, required: true, max_length: 1000 }] };
const patients = ['Alpha', 'Beta', ...Array.from({ length: 8 }, (_, i) => 'Other ' + i)].map((label, index) => ({ id: 'fixture-rel-' + index, organization_id: 'fixture-org', psychologist_uid: 'fixture-pro', patient_uid: 'Fixture Patient ' + label, state: 'active', consent_version: 'care-consent-v1', activated_at: stamp, revision: 1 }));
const drafts = Array.from({ length: 12 }, (_, i) => ({ id: 'fixture-draft-' + i, organization_id: 'fixture-org', psychologist_uid: 'fixture-pro', revision: 2, content: { ...content, title: { en: 'Fixture form ' + (i + 1) } }, created_at: stamp, updated_at: stamp }));
const snapshot = { id: 'fixture-version', questionnaire_id: 'fixture-draft-0', organization_id: 'fixture-org', psychologist_uid: 'fixture-pro', source_revision: 1, content, content_sha256: '0'.repeat(64), published_at: stamp, schema_version: '0.5.0' };
const submission = { id: 'fixture-submission', organization_id: 'fixture-org', patient_uid: patients[0].patient_uid, questionnaire_version_id: snapshot.id, submitted_at: stamp, answers: [{ question_id: 'fixture-question', type: 'short_text', value: 'Original fixture response, retained exactly.' }] };
const caps = { uid: 'fixture-pro', contract_version: '0.5.0', account_state: 'registered', authorization_revision: 1, capabilities: { professional_workspace: true, expert_directory: false, companion_account_sync: false, create_organization: false }, professional_organization_ids: ['fixture-org'], active_patient_relationships: [] };
const pageOf = items => ({ items, next_cursor: null });
function fixture(url, reviews, revision) {
  const p = url.pathname;
  if (p.endsWith('/capabilities')) return caps;
  if (p.includes('/questionnaire-versions/')) return snapshot;
  if (p.endsWith('/questionnaires')) return pageOf(drafts);
  if (p.includes('/questionnaires/')) return drafts.find(d => p.endsWith('/' + d.id));
  if (p.endsWith('/patient-relationships')) return pageOf(patients);
  if (p.endsWith('/archive')) return { archived: false, revision: 0 };
  if (p.endsWith('/workspace')) return { submission, questionnaire: { content }, evaluation: { id: 'fixture-evaluation', interpretation: null, validated_scores: [], evidence: [] }, job: { state: 'queued' }, review_revision: revision };
  if (p.endsWith('/review-decisions')) return pageOf(reviews);
  if (p.endsWith('/submissions')) return pageOf([submission]);
  if (p.includes('/relationships/') && p.endsWith('/messages')) { const id = p.split('/')[4]; return pageOf([{ id: 'message-' + id, relationship_id: id, sender_uid: id === patients[1].id ? patients[1].patient_uid : patients[0].patient_uid, body: 'Read-only fixture thread ' + id, created_at: stamp }]); }
  if (p.endsWith('/profile')) return { organization_id: 'fixture-org', psychologist_uid: 'fixture-pro', display_name: 'Fictional preview practice', bio: 'Frontend fixture only.', discoverable: true, accepting_new_patients: false, revision: 1 };
  if (p.endsWith('/analytics')) return { organization_id: 'fixture-org', series: [{ questionnaire_version_id: snapshot.id, scoring_version: 'not_applicable', enrolled: 3, submitted: 1, points: [{ date: stamp.slice(0, 10), submitted: 1 }] }] };
  return pageOf([]);
}
function syntheticToken() {
  const seconds = Math.floor(Date.now() / 1000);
  const payload = { iss: 'https://securetoken.google.com/demo-koi-fixture', aud: 'demo-koi-fixture', auth_time: seconds, iat: seconds, exp: seconds + 3600, user_id: 'fixture-pro', sub: 'fixture-pro', email: 'frontend-fixture@koi-demo.example', email_verified: true, firebase: { identities: { email: ['frontend-fixture@koi-demo.example'] }, sign_in_provider: 'password' } };
  return [Buffer.from(JSON.stringify({ alg: 'none', typ: 'JWT' })).toString('base64url'), Buffer.from(JSON.stringify(payload)).toString('base64url'), ''].join('.');
}
async function resultVisible(page, id) {
  await page.waitForFunction(id => document.activeElement?.id === id, id);
  const bounds = await page.locator('#' + id).boundingBox();
  assert.ok(bounds && bounds.y >= -2 && bounds.y < page.viewportSize().height - 48, id + ' heading must be in the viewport');
  assert.ok(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth + 1), 'No horizontal overflow');
}
(async () => {
  fs.mkdirSync(OUT, { recursive: true });
  const executablePath = ['C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe', 'C:/Program Files/Google/Chrome/Application/chrome.exe'].find(fs.existsSync);
  const browser = await chromium.launch({ headless: true, ...(executablePath ? { executablePath } : {}) });
  const results = [];
  try {
    for (const width of [390, 768, 1280, 1440]) {
      const context = await browser.newContext({ viewport: { width, height: 900 }, reducedMotion: 'reduce' });
      const blockedWrites = [], pageErrors = [], transport = [];
      const token = syntheticToken();
      let revision = 2;
      let reviews = [2, 1].map(number => ({ decision: number === 2 ? 'feedback' : 'reject', review: { id: 'fixture-review-' + number, organization_id: 'fixture-org', evaluation_id: 'fixture-evaluation', reviewer_uid: 'fixture-pro', revision: number, conclusion: 'Previous fixture conclusion ' + number, feedback: 'Previous fixture feedback ' + number, created_at: stamp } }));
      await context.route('**/*', async route => {
        const request = route.request(), url = new URL(request.url()), method = request.method();
        const json = body => route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify(body) });
        // These responses never reach Firebase, even if the app was configured for cloud auth.
        if (url.pathname.includes('accounts:signInWithPassword')) return json({ localId: 'fixture-pro', email: 'frontend-fixture@koi-demo.example', registered: true, idToken: token, refreshToken: 'fixture-refresh-only', expiresIn: '3600' });
        if (url.pathname.includes('accounts:lookup')) return json({ users: [{ localId: 'fixture-pro', email: 'frontend-fixture@koi-demo.example', emailVerified: true, providerUserInfo: [{ providerId: 'password', email: 'frontend-fixture@koi-demo.example', rawId: 'frontend-fixture@koi-demo.example' }], createdAt: '0', lastLoginAt: '0' }] });
        if (url.pathname.includes('/token') && /securetoken/.test(url.href)) return json({ access_token: token, id_token: token, refresh_token: 'fixture-refresh-only', expires_in: '3600', user_id: 'fixture-pro' });
        if (url.pathname.startsWith('/api/v1/')) {
          transport.push({ method, path: url.pathname });
          if (method === 'GET') return json(fixture(url, reviews, revision));
          if (method === 'POST' && url.pathname === '/api/v1/professional/patient-invitations') return json({ invitation_id: 'fixture-invitation', token: 'fixture-invitation-only', expires_at: stamp });
          if (method === 'POST' && url.pathname === '/api/v1/professional/review-decisions') {
            const body = request.postDataJSON();
            assert.equal(body.expected_review_revision, revision);
            assert.equal(body.evaluation_id, 'fixture-evaluation');
            assert.equal(body.organization_id, 'fixture-org');
            assert.ok(!('answers' in body), 'Review requests must not modify submitted answers');
            revision++;
            const saved = { decision: body.decision, review: { id: 'fixture-review-' + revision, organization_id: body.organization_id, evaluation_id: body.evaluation_id, reviewer_uid: 'fixture-pro', revision, conclusion: body.conclusion, feedback: body.feedback, created_at: stamp } };
            reviews = [saved, ...reviews]; return json(saved);
          }
          blockedWrites.push(url.pathname); return route.abort();
        }
        if (url.origin === BASE && method === 'GET' && (url.pathname.startsWith('/_next/') || ['/professional', '/account', '/icon.svg', '/favicon.ico'].includes(url.pathname))) return route.continue();
        return route.abort();
      });
      const page = await context.newPage();
      page.on('pageerror', error => pageErrors.push(error.message));
      page.setDefaultTimeout(30000);
      await page.goto(BASE + '/professional?view=patients', { waitUntil: 'domcontentloaded', timeout: 120000 });
      await page.getByRole('textbox', { name: 'Email', exact: true }).fill('frontend-fixture@koi-demo.example');
      await page.getByLabel('Password', { exact: true }).fill('Frontend-fixture-only-2026');
      await page.getByRole('button', { name: 'Sign in', exact: true }).click();
      const nav = page.getByRole('navigation', { name: 'Practice navigation' });
      const row = label => page.locator('article.care-patient-row').filter({ hasText: 'Fixture Patient ' + label });
      await row('Beta').getByRole('button', { name: 'Patient details', exact: true }).focus();
      await page.keyboard.press('Enter');
      await resultVisible(page, 'selected-patient');
      assert.match(await page.locator('#selected-patient-heading').textContent(), /Beta/);
      await page.screenshot({ path: path.join(OUT, 'patient-details-' + width + '.png'), fullPage: false });
      await page.getByRole('button', { name: 'Close patient details' }).click();
      await page.waitForFunction(() => document.activeElement?.textContent === 'Patient details');
      await row('Beta').getByRole('link', { name: 'Open conversation' }).click();
      await resultVisible(page, 'selected-human-conversation');
      await page.getByRole('log', { name: 'Messages', exact: true }).getByText('Read-only fixture thread fixture-rel-1').waitFor();
      await page.getByRole('textbox', { name: 'Message', exact: true }).fill('Unsent frontend fixture');
      await nav.getByRole('link', { name: 'Patients & assignments' }).click();
      await page.goBack();
      await resultVisible(page, 'selected-human-conversation');
      assert.equal(await page.getByRole('textbox', { name: 'Message', exact: true }).inputValue(), 'Unsent frontend fixture');
      await page.screenshot({ path: path.join(OUT, 'selected-thread-' + width + '.png'), fullPage: false });
      await nav.getByRole('link', { name: 'Patients & assignments' }).click();
      const picker = page.getByRole('combobox', { name: 'Published questionnaire', exact: true });
      await picker.locator('option[value="fixture-version"]').waitFor({ state: 'attached' });
      await picker.selectOption('fixture-version');
      assert.equal(await picker.inputValue(), 'fixture-version');
      await row('Alpha').getByRole('link', { name: 'Appointments', exact: true }).click();
      await resultVisible(page, 'patient-appointments');
      assert.match(await page.locator('#patient-appointments-heading').textContent(), /Alpha/);
      await nav.getByRole('link', { name: 'Submission review', exact: true }).click();
      await page.getByRole('button', { name: 'Inspect submission', exact: true }).click();
      await resultVisible(page, 'selected-submission');
      await page.getByRole('heading', { name: 'Submission and clinician review' }).waitFor();
      assert.equal(await page.getByRole('heading', { name: 'Fixture form 1', exact: true }).count(), 1);
      const originalAnswer = page.getByRole('textbox', { name: 'Fixture response', exact: true });
      assert.equal(await originalAnswer.inputValue(), 'Original fixture response, retained exactly.');
      assert.ok(await originalAnswer.isDisabled(), 'Patient answers remain immutable');
      const reviewNav = page.getByRole('navigation', { name: 'Submission review sections' });
      await reviewNav.getByRole('link', { name: '1. Submission overview' }).click();
      await resultVisible(page, 'review-fixture-submission-overview');
      if ([390, 1440].includes(width)) await page.screenshot({ path: path.join(OUT, 'submission-overview-' + width + '.png'), fullPage: false });
      await reviewNav.getByRole('link', { name: '4. Psychologist review' }).focus();
      await page.keyboard.press('Enter');
      await resultVisible(page, 'review-fixture-submission-review');
      assert.ok(await page.getByRole('button', { name: 'Approve review' }).isDisabled());
      assert.ok(await page.getByRole('button', { name: 'Reject evaluation' }).isDisabled());
      assert.ok(await page.getByRole('button', { name: 'Save feedback' }).isDisabled());
      assert.ok(await page.getByText('Enter a psychologist conclusion to enable', { exact: false }).isVisible());
      await page.getByRole('textbox', { name: 'Review feedback', exact: true }).fill('Optional fixture feedback');
      assert.ok(await page.getByRole('button', { name: 'Save feedback' }).isDisabled());
      await page.getByRole('textbox', { name: 'Psychologist conclusion', exact: true }).fill('Manual professional fixture conclusion');
      assert.ok(await page.getByRole('button', { name: 'Save feedback' }).isEnabled());
      await page.goBack();
      await resultVisible(page, 'review-fixture-submission-overview');
      await page.goForward();
      await resultVisible(page, 'review-fixture-submission-review');
      assert.equal(await page.getByRole('textbox', { name: 'Psychologist conclusion', exact: true }).inputValue(), 'Manual professional fixture conclusion');
      if ([390, 1440].includes(width)) await page.screenshot({ path: path.join(OUT, 'review-form-' + width + '.png'), fullPage: false });
      page.once('dialog', dialog => dialog.accept());
      await page.getByRole('button', { name: 'Save feedback' }).click();
      await page.getByText('Review revision 3 saved. Original answers and interpretation are preserved.', { exact: true }).waitFor();
      assert.equal(await originalAnswer.inputValue(), 'Original fixture response, retained exactly.');
      await reviewNav.getByRole('link', { name: '5. Review history' }).click();
      await resultVisible(page, 'review-fixture-submission-history');
      await page.locator('.care-history-entry summary').filter({ hasText: /^Revision 3:/ }).click();
      assert.ok(await page.getByText('Manual professional fixture conclusion', { exact: true }).isVisible());
      if ([390, 1440].includes(width)) await page.screenshot({ path: path.join(OUT, 'review-history-' + width + '.png'), fullPage: false });
      await nav.getByRole('link', { name: 'Questionnaires', exact: true }).click();
      await page.getByRole('button', { name: 'Open draft: Fixture form 1', exact: true }).click();
      await resultVisible(page, 'questionnaire-editor');
      await page.getByRole('textbox', { name: /Title.*English/ }).fill('Unsaved frontend fixture title');
      await page.getByRole('button', { name: 'Inspect published revision' }).click();
      await resultVisible(page, 'published-questionnaire-panel');
      assert.equal(await page.getByRole('textbox', { name: /Title.*English/ }).inputValue(), 'Unsaved frontend fixture title');
      await nav.getByRole('link', { name: 'Practice overview', exact: true }).click();
      const shortcut = page.getByRole('link', { name: 'Manage questionnaires', exact: true });
      assert.equal(await shortcut.getAttribute('href'), '/professional?view=questionnaires#professional-questionnaires');
      const style = await shortcut.evaluate(element => ({ color: getComputedStyle(element).backgroundColor, border: getComputedStyle(element).borderTopStyle, decoration: getComputedStyle(element).textDecorationLine, shadow: getComputedStyle(element).boxShadow }));
      assert.equal(style.decoration, 'none'); assert.equal(style.border, 'solid'); assert.notEqual(style.shadow, 'none');
      if ([390, 1440].includes(width)) await page.screenshot({ path: path.join(OUT, 'overview-actions-' + width + '.png'), fullPage: true });
      await page.getByRole('link', { name: 'View assignments and submissions' }).click();
      await resultVisible(page, 'workspace-heading');
      await page.getByRole('heading', { name: /Fixture form 1.*Revision 1/ }).waitFor();
      const totals = page.getByLabel('Assignment and submission totals');
      assert.ok(await totals.isVisible());
      await page.getByLabel('Activity from date', { exact: true }).fill('2000-01-01');
      await page.getByLabel('Activity to date', { exact: true }).fill('2000-01-02');
      assert.match(await totals.innerText(), /Submitted in selected dates\s+0/);
      await page.getByLabel('Activity from date', { exact: true }).fill('');
      await page.getByLabel('Activity to date', { exact: true }).fill('');
      if ([390, 1440].includes(width)) await page.screenshot({ path: path.join(OUT, 'usage-analytics-' + width + '.png'), fullPage: true });
      await page.getByRole('link', { name: 'View published questionnaire', exact: true }).click();
      await resultVisible(page, 'published-questionnaire-panel');
      await page.goBack();
      await page.getByRole('heading', { name: 'Assignments & Submissions', exact: true, level: 1 }).waitFor();
      await page.goForward();
      await page.getByRole('region', { name: 'Published questionnaire' }).waitFor();
      await nav.getByRole('link', { name: 'Patients & assignments' }).click();
      await page.locator('summary').filter({ hasText: /^Invitations$/ }).click();
      await page.getByRole('button', { name: 'Create secure invitation' }).click();
      await resultVisible(page, 'created-invitation');
      // Account is a full navigation: explicitly discard only the synthetic unsaved fixture.
      page.on('dialog', dialog => dialog.accept());
      await nav.getByRole('link', { name: 'Account & access', exact: true }).click();
      await page.getByRole('heading', { name: 'Your practice', exact: true }).waitFor();
      assert.equal(await page.getByRole('link', { name: 'Professional Dashboard', exact: true }).count(), 1);
      assert.match(await page.getByRole('link', { name: 'Professional Dashboard', exact: true }).getAttribute('class'), /care-link--primary/);
      assert.equal(await page.getByRole('link', { name: 'Professional Questionnaires', exact: true }).count(), 0);
      assert.ok(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth + 1), 'Account has no overflow');
      assert.deepEqual(blockedWrites, [], 'Only intercepted invitation and review fixtures may be written');
      assert.deepEqual(pageErrors, [], 'No browser runtime errors');
      assert.ok(transport.every(row => !/questionnaire-drafts|chat|crisis|speech/.test(row.path)), 'No AI or companion endpoints');
      results.push({ width, patientDetails: true, selectedConversation: true, unsentDraft: true, history: true, appointments: true, submission: true, questionnaireEditor: true, immutableOriginalAnswers: true, reviewValidation: true, reviewSaveFixture: true, reviewHistory: true, sectionNavigation: true, linkStyling: true, publishedSelector: true, publishedVersion: true, invitationFixture: true, accountGroups: true, writesToEmulators: 0 });
      await context.close();
      console.log('PASS interactive care workflows at ' + width + 'px');
    }
    fs.writeFileSync(path.join(OUT, 'results.json'), JSON.stringify(results, null, 2));
  } finally { await browser.close(); }
})().catch(error => { console.error(error.message); process.exitCode = 1; });
