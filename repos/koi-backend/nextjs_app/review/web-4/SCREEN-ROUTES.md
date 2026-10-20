# GUI routes

Base URL: `http://127.0.0.1:3107`. The routes below were mapped from actual `src/app/**/page.tsx` files and workspace sections. Query/hash URLs are section links within the existing authorized workspace, not new API endpoints. Deep links cannot bypass backend authorization.

| Screen | URL | Access |
| --- | --- | --- |
| Original landing page | `/?home=1` | Public; original bare `/` retains companion-session redirect behavior |
| Unified account sign-in/menu | `/account` | Public sign-in; menu uses authenticated server capabilities |
| Expert discovery/profile details/application | `/patient?view=experts#experts` | Registered General/Patient |
| Care overview/invitations/application status | `/patient` | Registered General; patient sections require active relationship |
| My Psychologist/human conversation | `/patient?view=care#care` | Active relationship |
| Assigned questionnaires | `/patient?view=questionnaires#questionnaires` | Active relationship |
| Questionnaire runner/pre-submit review/acknowledgement | `/patient` or questionnaire section → Open questionnaire / View acknowledgement | Owned assignment, active relationship; no patient result screen |
| Human messages | `/patient?view=messages#care` | Active relationship |
| Patient appointments | `/patient?view=appointments#care` | Active relationship; shared conversation card |
| In-app notifications | `/patient?view=notifications#notifications` | Active relationship for this menu entry; underlying inbox also supports General application notices |
| Professional workspace/organization creation | `/professional` | Verified psychologist; creation only when eligible |
| Organization dashboard/profile | `/professional?view=dashboard#practice-dashboard` | Verified active owner |
| Manual drafts/editor/publishing | `/professional?view=questionnaires#professional-questionnaires` | Verified active owner |
| Immutable published version | `/professional?version=VERSION_ID` | Authorized owning practice; copy the bookmark from the published preview |
| Roster/invitations/applications/assignments | `/professional?view=patients#patients` | Verified active owner |
| Patient details/history/closed-record archival | Patients → Patient details | Scoped owner; selected patient remains in memory |
| Raw submissions/evaluation/review | `/professional?view=submissions#submissions` → Inspect submission | Scoped verified owner only |
| Professional analytics | `/professional?view=analytics#practice-analytics` | Verified active owner |
| Professional human messages/appointments | Patients → Open conversation | Active relationship within own practice |
| Professional submission updates/inbox | Professional Dashboard → respective cards | Scoped owner/recipient |
| Original onboarding | `/onboarding` | Original companion flow |
| Original text companion | `/chat` | Original companion session; provider connectivity required for replies |
| Original avatar/voice scene | `/companion-scene` | Original companion session and supported device/provider features |
| Renderer-only avatar host | `/avatar-host` | Presentation-only route; no new account navigation injected |
| Companion history | `/history` | Original local companion ownership |
| Original personal progress | `/progress` | Original companion session; distinct from professional questionnaire analytics |
| Settings | `/settings` | Original companion session |
| Privacy settings | `/settings/privacy` | Original companion session |
| Export/import/report | `/settings/export`, `/settings/import`, `/settings/report` | Original local ownership and existing safeguards |
| About/how it works | `/about`, `/how-it-works` | Public |

Section links retain the existing full workspace rather than introducing duplicate screens. Some professional actions use in-memory selection; their buttons are the entry points instead of invented standalone URLs. All navigation preserves Neo components/tokens, spinner and reduced-motion behavior.
