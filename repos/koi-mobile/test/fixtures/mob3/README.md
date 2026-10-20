# MOB-3 test fixtures (TEST ONLY: never bundled in the app)

`who5_en_template.json` and `dass21_en_template.json` are the `template`
objects (a `QuestionnaireDraft`) of the AI track's curated instrument files,
extracted unchanged with `JSON.stringify(template, null, 2)`:

| Fixture | Source (KOI-Psycholov `origin/master` bb65e6b, read with git show) | sha256 of the source file |
|---|---|---|
| `who5_en_template.json` | `resources/psychology/curated/who5_en.json` | `830925919756628e2a5d20b4d319ed25b6f27b87362800bbd3b9f1365574727b` |
| `dass21_en_template.json` | `resources/psychology/curated/dass21_en.json` | `9922f2b3390be7e4e6562653e30b0555ccdc505b6d0c77ac3cd092ad42e7dca6` |

The source files' `scoring` blocks were left out on purpose: the patient app
never holds scoring data.

WHO-5: © WHO, 2024. License: CC-BY-NC-SA 3.0 IGO (`redistribution_reviewed:
false`). DASS-21: Lovibond & Lovibond, public domain, may not be modified.
Because redistribution is not reviewed, both stay in tests only (MOB-1 rule
"no clinical instrument wording in the app"). They prove word-for-word
rendering (MOB3-31, MOB3-32).
