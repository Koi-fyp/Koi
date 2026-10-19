# 0.5.0 — initial local review freeze

Prepared 2026-10-19 for WEB-0.5. Not deployed or cross-track signed off.

- Separate server registration, explicit General grant, clinician verification,
  organization membership and patient relationships from legacy profile/auth flags.
- Freeze manual form/revision/publish semantics and shared question/answer/asset types.
- Define server-only autosave, atomic submission and patient acknowledgement firewall.
- Separate professional evaluation/review/job DTOs and internal leased worker access.
- Define later invitations, applications, demo payments, messaging, appointment and
  in-app notification boundaries without implementing them.
- Include schema fixtures, deferred integration acceptance cases, collection matrix
  and explicit deployment/retention/Flutter prerequisites.

Next implementation checkpoint: verified psychologist -> organization -> manual
questionnaire -> immutable publish, using synthetic data until live rules and
deployment identity are verified. No patient/AI feature is implemented here.
