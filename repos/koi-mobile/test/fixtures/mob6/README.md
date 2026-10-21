# MOB-6 test fixtures (TEST ONLY: never bundled in the app)

`contracts_v0.5.2_fixtures.json` is the contract's own example file, copied
byte for byte:

| Fixture | Source (koi-backend `origin/feat/koi2-ui-overhaul` f9ed940, read with git show) | git blob | sha256 |
|---|---|---|---|
| `contracts_v0.5.2_fixtures.json` | `nextjs_app/contracts/v0.5.2/fixtures.json` | `c21f78d41d1b02bc1dd7b2193c4e1e9d942c3b68` | `be6224276ec98b8a015498338284aff6d82f801731fb7acaa6da2026ca59f95c` |

MOB6-01 parses its valid patient cases; MOB6-02 checks that its invalid
patient cases are refused. The Urdu text in the source file is `????`: the
characters were already lost upstream (question for the web track). The tests
do not depend on it.
