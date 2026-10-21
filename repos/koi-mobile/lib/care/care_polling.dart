/// How often Care asks the platform server again: every interval in one
/// place (LIVE-READY, Firebase free plan: quota-safe).
///
/// - A message thread polls its FIRST page only, every
///   [careThreadPollInterval], and only while its screen is the top route
///   and the app is in the foreground (ThreadController). A tick that brings
///   nothing new changes nothing.
/// - Every page is read again (full reload) only when the thread opens, on
///   pull-to-refresh, when the app comes back to the foreground, and when a
///   new_message notification is tapped (it opens the thread).
///   Known limit: pages come in document-id order (contract v0.5.2), so in
///   a thread of more than one page (over 100 messages) a new
///   message can land on a later page; it then shows on the next full
///   reload, not on a tick.
/// - Appointments and notifications have no timer: they refresh when their
///   screen opens, on pull-to-refresh, and (notifications) on resume.
/// - Nothing polls in the background.
library;

const Duration careThreadPollInterval = Duration(seconds: 30);
