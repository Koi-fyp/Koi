# WEB-3 additive contracts (0.5.2)

All 0.5.1 definitions and existing route shapes remain unchanged. Added owner-only profile read/update, closed-patient archival read/write, patient-scoped professional submission history, and a separate professional submission-notification endpoint. No patient response references a professional notification or evaluation schema. Cross-track acknowledgement is pending; no external notification was sent.

Implemented existing directory, human messaging, appointments, in-app notifications and professional activity analytics operations. A new application now requires an explicitly discoverable profile accepting new patients; invitation onboarding remains available independently. Existing accepted/application receipts remain replayable under existing authorization. Published questionnaire, attempt, AI job and submission contracts are unchanged.
