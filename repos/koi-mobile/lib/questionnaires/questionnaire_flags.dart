/// THE switch for this device's copy of unfinished questionnaire answers
/// (MOB-3).
///
/// true (current): an encrypted local draft (Client-Side Encryption (CSE) at
/// rest, `koi_questionnaire_drafts`) keeps answers, their answer ids and
/// the submit idempotency key across an app restart and while offline.
///
/// false: nothing is written on the device. Answers live in memory and on
/// the server (autosave) only; an offline edit is lost if the app is killed
/// before it syncs, and answer ids made after a Restart are new on resume.
/// Existing rows are still deleted on sign-out, relationship end and submit.
///
/// Open question for the team: contract v0.5.1 semantics say "no protected
/// offline persistence is enabled" on the web. If the team says no local
/// drafts on mobile either, set this to false; nothing else changes.
const bool kQuestionnaireLocalDrafts = true;
