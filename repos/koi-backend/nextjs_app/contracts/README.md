# KOI application platform contracts

Canonical location for this workspace: `repos/koi-backend/nextjs_app/contracts/`.
This is a **local contract freeze proposal**, version **0.5.0**, prepared for Web,
Flutter and AI review. It is not an implemented API, a deployed security policy,
or cross-track sign-off. No source was copied to another owner's repository and
no external handoff message was sent.

- [OpenAPI 3.1 endpoint contract](v0.5.0/openapi.json)
- [Canonical shared JSON Schema, Draft-07](v0.5.0/contracts.schema.json)
- [Synthetic integration fixtures](v0.5.0/fixtures.json)
- [Authorization, transaction and lifecycle rules](v0.5.0/semantics.md)
- [Collection read/write matrix](v0.5.0/authorization-matrix.md)
- [Future implementation acceptance cases](v0.5.0/acceptance-cases.json)
- [Frozen file hashes](v0.5.0/freeze-manifest.json)

OpenAPI references the canonical schemas rather than duplicating their fields.
`semantics.md` and the matrix are normative: JSON Schema cannot prove resource
ownership, relational constraints, unique question IDs, or transaction behavior.
All operation paths are proposed; `x-status: proposed_not_implemented` identifies
this explicitly. Existing `/api/auth/*` and companion `/api/v1/chat` are outside
this new platform contract and remain unchanged.

Validate locally with `node scripts/validate-web05-contract.cjs`. The validator
uses Next's existing bundled Draft-07 validator, adds no dependency, and checks
fixture shape, references, patient DTO reachability, endpoint metadata and frozen
hashes. It does **not** execute access controls, Firestore rules, transactions,
Firebase authentication, provider calls or an OpenAPI standards conformance suite.

Freeze discipline: do not edit 0.5.0 after this review snapshot. A contract change
gets a new version directory, changelog, updated fixtures and hashes. Breaking
pre-1.0 changes increment the minor version; compatible additions/fixes increment
the patch version. Web/Mobile/AI owners must acknowledge the reviewed version
before implementation or client generation against it. Notify other tracks only
through an authorized handoff; this task does not authorize messaging them.

No instrument or illustration is approved by these schemas. No WHO-5, DASS-21 or
IPIP wording, scoring rules, translation or licensing evidence was seeded.

WEB-2 implementation adds the compatible [0.5.1 package](v0.5.1/CHANGELOG.md),
with [OpenAPI](v0.5.1/openapi.json), [schemas](v0.5.1/contracts.schema.json),
[fixtures](v0.5.1/fixtures.json) and [implementation semantics](v0.5.1/semantics.md).
All 96 original definitions and frozen 0.5.0 files remain unchanged. Existing
patient/questionnaire DTO version constants remain `0.5.0`; the additive package
version is `0.5.1`. Five new professional operations add roster/submission discovery,
submission workspace and explicit review decisions. Cross-track acknowledgement
has not been claimed; see [WEB-2 handoff](implementations/WEB-2.md).
Validate the extension with `node scripts/validate-web2-contract.cjs`.
