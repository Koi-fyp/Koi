import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';

// MOB-2 strings (decision B, 2026-10-19): a small English / Urdu table for
// the NEW Care screens only. No flutter_localizations, and existing screens
// keep their English text. Urdu screens are right-to-left.
//
// URDU NEEDS NATIVE REVIEW: every Urdu string below was drafted for
// development and has not been reviewed by a native speaker or the
// clinical team. It is not a validated translation.

enum CareLang { en, ur }

enum CareText {
  care,
  back,
  retry,
  updating,
  loading,
  notAvailableYet,
  offline,
  genericError,
  noLongerAvailable,
  rateLimited,
  demoNotice,
  // Re-check sheet (recent sign-in).
  reauthTitle,
  reauthBody,
  reauthPassword,
  reauthConfirm,
  reauthCancel,
  reauthWrong,
  // Care home.
  myPsychologist,
  yourPsychologist,
  questionnaires,
  questionnairesSub,
  messages,
  messagesSub,
  appointments,
  appointmentsSub,
  notifications,
  notificationsSub,
  findExpert,
  findExpertSub,
  myApplications,
  myApplicationsSub,
  notMonitored,
  // Experts.
  expertsIntro,
  searchLabel,
  acceptingOnly,
  accepting,
  notAccepting,
  noExperts,
  noMatches,
  loadMore,
  apply,
  applyTitle,
  applyIntro,
  consentLabel,
  consentNeeded,
  continueLabel,
  confirmTitle,
  confirmBody,
  sendApplication,
  sending,
  alreadyConnected,
  appliedBefore,
  viewApplication,
  notAcceptingCantApply,
  // Applications.
  stateRequested,
  stateAwaitingPayment,
  statePendingReview,
  stateAccepted,
  stateDeclined,
  stateWithdrawn,
  paymentPending,
  paymentConfirmed,
  paymentExplainer,
  confirmDemoPayment,
  withdraw,
  withdrawTitle,
  withdrawBody,
  withdrawYes,
  keep,
  noApplications,
  acceptedNote,
  declinedNote,
  applicationTitle,
  // Messages.
  professionalMessage,
  noConversations,
  noMessagesYet,
  composerHint,
  send,
  messagePending,
  messageFailed,
  safetyFooter,
  loadOlder,
  you,
  unread,
  // Appointments.
  requestAppointment,
  requestExplainer,
  requesting,
  upcoming,
  pending,
  past,
  cancelled,
  apptRequested,
  apptProposed,
  apptConfirmed,
  apptCompleted,
  apptRejected,
  apptCancelled,
  confirmTime,
  decline,
  cancelAppointment,
  cancelTitle,
  cancelBody,
  cancelYes,
  askAnotherTime,
  askAnotherTimeBody,
  noTimeYet,
  noAppointments,
  appointmentTitle,
  lastUpdated,
  // Notifications.
  markAllRead,
  noNotifications,
  kindAssignment,
  kindNewMessage,
  kindAppointment,
  kindApplication,
  ok,
  // Debug.
  simulateTitle,
  // Questionnaires (MOB-3).
  qLoadingList,
  qNothing,
  qStateAssigned,
  qStateInProgress,
  qStateSubmitted,
  qLoading,
  qSubmitting,
  qOfflineOpen,
  qGone,
  qUnsupported,
  qConflictTitle,
  qConflictBody,
  qUseServer,
  qKeepMine,
  qPrevious,
  qNext,
  qCheckAnswers,
  qStartAgain,
  qRestartTitle,
  qRestartBody,
  qCancel,
  qPleaseAnswer,
  qOptional,
  qNoAnswer,
  qCheckYourAnswers,
  qEdit,
  qSubmit,
  qBackToQuestions,
  qProblemIncomplete,
  qProblemOffline,
  qProblemUnconfirmed,
  qProblemConflict,
  qProblemReauth,
  qSaving,
  qSaved,
  qOfflineNotSynced,
  qNotSaved,
  qConflict,
  qAckTitle,
  qBackToList,
  qNumberInvalid,
  qPictureUnavailable,
  qSources,
  qIncrease,
  qDecrease,
  // Personal safety plan (BATCH SAFETY-PLAN). NEEDS CLINICIAN REVIEW: every
  // sp* text (both languages) was drafted for development and has not been
  // reviewed by a clinician. Never add wording about methods or means.
  spTitle,
  spIntro,
  spAddMore,
  spFootnote,
  spPrivacy,
  spWarningSigns,
  spWarningSignsHelp,
  spCopingAlone,
  spCopingAloneHelp,
  spDistractions,
  spDistractionsHelp,
  spPeopleToAsk,
  spPeopleToAskHelp,
  spProfessionals,
  spProfessionalsHelp,
  spSaferSurroundings,
  spSaferSurroundingsHelp,
  spReasons,
  spReasonsHelp,
  spHelplineFixed,
  spAdd,
  spItemLabel,
  spPhoneLabel,
  spPhoneInvalid,
  spSaveItem,
  spCancel,
  spEditItem,
  spDelete,
  spMoveUp,
  spMoveDown,
  spMaxItems,
  spSaving,
  spSaved,
  spNotSaved,
  spLoadError,
  spLoading,
  spEditPlan,
  spDone,
  spOpen,
  spBreathing,
  spOnboardingTitle,
  spOnboardingBody,
  spCreate,
  spNotNow,
  spCallLabel,
  // AUTH-ENTRY: sign in / create account, the anonymous Care page and the
  // Settings card.
  auCreateTitle,
  auSignInTitle,
  auBusyUpgrade,
  auBusyCreate,
  auBusySignIn,
  auUpgradeIntro,
  auSignInSwitchNote,
  auEmail,
  auPassword,
  auPasswordHint,
  auConfirm,
  auShowPassword,
  auHidePassword,
  auPasswordWarning,
  auCreateButton,
  auSignInButton,
  auSignInInstead,
  auForgot,
  auEnterEmail,
  auEnterPassword,
  auPasswordShort,
  auMismatch,
  auErrEmailInUse,
  auErrWrong,
  auErrNotFound,
  auErrWeak,
  auErrInvalidEmail,
  auErrNetwork,
  auErrTooMany,
  auErrNotAllowed,
  auErrSalt,
  auErrGeneric,
  auResetTitle,
  auResetBody,
  auResetSend,
  auResetSending,
  auResetSent,
  auResetNeedEmail,
  auCancel,
  auPsychLink,
  auPsychTitle,
  auPsychBody,
  auWhy,
  auCareTitle,
  auCareWhy,
  auCareKeep,
  auCareChat,
  auDismiss,
  // MOB-4 (contract v0.5.2): "not set up yet", invitation codes, the
  // 1,000-item cap and the closed-to-new-patients answer.
  m4NotSetUp,
  m4NotSetUpChat,
  m4InviteEntry,
  m4InviteEntrySub,
  m4InviteTitle,
  m4InviteIntro,
  m4InviteLabel,
  m4InviteHint,
  m4InviteConsent,
  m4InviteRedeem,
  m4InviteRedeeming,
  m4InviteFormat,
  m4InviteNotFound,
  m4InviteUsed,
  m4InviteDenied,
  m4InviteAccepted,
  m4MessagesCapped,
  m4AppointmentsCapped,
  m4NotAcceptingNow,
}

const Map<CareText, String> _en = {
  CareText.care: 'Care',
  CareText.back: 'Back',
  CareText.retry: 'Try again',
  CareText.updating: 'Updating…',
  CareText.loading: 'Loading…',
  CareText.notAvailableYet: 'This is not available yet.',
  CareText.offline:
      'You seem to be offline. Check your connection and try again.',
  CareText.genericError: 'Something went wrong. Please try again.',
  CareText.noLongerAvailable: 'This is no longer available for your account.',
  CareText.rateLimited: 'Too many tries. Please wait a little and try again.',
  CareText.demoNotice: 'Demo data. Nothing here is real.',
  CareText.reauthTitle: 'Confirm it is you',
  CareText.reauthBody:
      'For your safety, please enter your password again to continue.',
  CareText.reauthPassword: 'Password',
  CareText.reauthConfirm: 'Confirm',
  CareText.reauthCancel: 'Cancel',
  CareText.reauthWrong: 'That password did not work. Please try again.',
  CareText.myPsychologist: 'My Psychologist',
  CareText.yourPsychologist: 'Your psychologist',
  CareText.questionnaires: 'Questionnaires',
  CareText.questionnairesSub: 'Forms your psychologist asked you to fill in',
  CareText.messages: 'Messages',
  CareText.messagesSub: 'Messages with your psychologist',
  CareText.appointments: 'Appointments',
  CareText.appointmentsSub: 'Request and manage appointments',
  CareText.notifications: 'Notifications',
  CareText.notificationsSub: 'Updates about your care',
  CareText.findExpert: 'Find an Expert',
  CareText.findExpertSub: 'Browse psychologists listed in KOI',
  CareText.myApplications: 'My applications',
  CareText.myApplicationsSub: 'Applications you sent to psychologists',
  CareText.notMonitored:
      'Messages with your psychologist are not monitored for emergencies. '
      'If you are in danger, call 1166.',
  CareText.expertsIntro: 'Psychologists who are listed in KOI.',
  CareText.searchLabel: 'Search by name',
  CareText.acceptingOnly: 'Accepting new patients only',
  CareText.accepting: 'Accepting new patients',
  CareText.notAccepting: 'Not accepting new patients',
  CareText.noExperts: 'No experts are listed right now.',
  CareText.noMatches: 'No psychologist matches your search.',
  CareText.loadMore: 'Show more',
  CareText.apply: 'Apply to work with this psychologist',
  CareText.applyTitle: 'Apply',
  CareText.applyIntro:
      'The psychologist will see your application and decide whether to '
      'work with you. Your private KOI chats are never shared.',
  CareText.consentLabel:
      'I agree that this psychologist may see my application and, if they '
      'accept, contact me through KOI.',
  CareText.consentNeeded: 'Please tick the box to continue.',
  CareText.continueLabel: 'Continue',
  CareText.confirmTitle: 'Send your application?',
  CareText.confirmBody:
      'You can withdraw it while the psychologist has not decided yet.',
  CareText.sendApplication: 'Send application',
  CareText.sending: 'Sending…',
  CareText.alreadyConnected: 'You are already connected to this psychologist.',
  CareText.appliedBefore:
      'You applied to this psychologist before. Applying again is not '
      'available yet.',
  CareText.viewApplication: 'View my application',
  CareText.notAcceptingCantApply:
      'This psychologist is not accepting new patients right now.',
  CareText.stateRequested: 'Requested',
  CareText.stateAwaitingPayment: 'Waiting for demo payment',
  CareText.statePendingReview: 'Waiting for the psychologist',
  CareText.stateAccepted: 'Accepted',
  CareText.stateDeclined: 'Declined',
  CareText.stateWithdrawn: 'Withdrawn',
  CareText.paymentPending: 'Payment: Pending (simulated)',
  CareText.paymentConfirmed: 'Payment: Confirmed (simulated)',
  CareText.paymentExplainer:
      'This is a demo step. No money is taken and no card is needed.',
  CareText.confirmDemoPayment: 'Confirm demo payment (simulated)',
  CareText.withdraw: 'Withdraw application',
  CareText.withdrawTitle: 'Withdraw this application?',
  CareText.withdrawBody: 'The psychologist will no longer see it.',
  CareText.withdrawYes: 'Withdraw',
  CareText.keep: 'Keep it',
  CareText.noApplications: 'You have not applied to a psychologist yet.',
  CareText.acceptedNote:
      'The psychologist accepted your application. Pull down on Care to '
      'see your care space.',
  CareText.declinedNote:
      'The psychologist could not take your application. You can look for '
      'another psychologist.',
  CareText.applicationTitle: 'Application',
  CareText.professionalMessage: 'Professional message',
  CareText.noConversations: 'You have no conversations yet.',
  CareText.noMessagesYet: 'No messages yet. Say hello to your psychologist.',
  CareText.composerHint: 'Write a message',
  CareText.send: 'Send',
  CareText.messagePending: 'Sending…',
  CareText.messageFailed: 'Failed — tap to retry',
  CareText.safetyFooter:
      'This chat is not monitored for emergencies. If you are in danger, '
      'call 1166.',
  CareText.loadOlder: 'Show older messages',
  CareText.you: 'You',
  CareText.unread: 'Unread',
  CareText.requestAppointment: 'Request an appointment',
  CareText.requestExplainer:
      'Your psychologist will propose a time. You can then confirm it.',
  CareText.requesting: 'Sending request…',
  CareText.upcoming: 'Upcoming',
  CareText.pending: 'Pending',
  CareText.past: 'Past',
  CareText.cancelled: 'Cancelled',
  CareText.apptRequested: 'Requested',
  CareText.apptProposed: 'Time proposed',
  CareText.apptConfirmed: 'Confirmed',
  CareText.apptCompleted: 'Completed',
  CareText.apptRejected: 'Declined by psychologist',
  CareText.apptCancelled: 'Cancelled',
  CareText.confirmTime: 'Confirm this time',
  CareText.decline: 'Decline',
  CareText.cancelAppointment: 'Cancel appointment',
  CareText.cancelTitle: 'Cancel this appointment?',
  CareText.cancelBody: 'This cannot be undone.',
  CareText.cancelYes: 'Cancel appointment',
  CareText.askAnotherTime: 'Ask for another time',
  CareText.askAnotherTimeBody:
      'This sends a new request. Your confirmed appointment stays until you '
      'cancel it.',
  CareText.noTimeYet: 'No time yet',
  CareText.noAppointments: 'You have no appointments yet.',
  CareText.appointmentTitle: 'Appointment',
  CareText.lastUpdated: 'Last updated',
  CareText.markAllRead: 'Mark all as read',
  CareText.noNotifications: 'You have no notifications.',
  CareText.kindAssignment: 'You have a new questionnaire',
  CareText.kindNewMessage: 'New message from your psychologist',
  CareText.kindAppointment: 'An appointment was updated',
  CareText.kindApplication: 'Your application was updated',
  CareText.ok: 'OK',
  CareText.simulateTitle: 'Simulate psychologist (debug)',
  CareText.qLoadingList: 'Loading questionnaires',
  CareText.qNothing: 'Nothing to fill in right now.',
  CareText.qStateAssigned: 'Not started',
  CareText.qStateInProgress: 'In progress',
  CareText.qStateSubmitted: 'Submitted',
  CareText.qLoading: 'Loading questionnaire…',
  CareText.qSubmitting: 'Submitting…',
  CareText.qOfflineOpen:
      'You seem to be offline. This questionnaire needs a connection to open.',
  CareText.qGone: 'This questionnaire is no longer available.',
  CareText.qUnsupported: 'This questionnaire cannot be shown in this version of the app. Please let your psychologist know.',
  CareText.qConflictTitle: 'These answers were changed somewhere else.',
  CareText.qConflictBody: 'Choose which answers to keep. Nothing is combined.',
  CareText.qUseServer: 'Load the saved answers',
  CareText.qKeepMine: 'Keep this device\'s answers',
  CareText.qPrevious: 'Previous',
  CareText.qNext: 'Next',
  CareText.qCheckAnswers: 'Check answers',
  CareText.qStartAgain: 'Start again',
  CareText.qRestartTitle: 'Start again?',
  CareText.qRestartBody: 'Your answers to this questionnaire will be cleared. This cannot be undone.',
  CareText.qCancel: 'Cancel',
  CareText.qPleaseAnswer: 'Please answer this question.',
  CareText.qOptional: '(optional)',
  CareText.qNoAnswer: 'No answer',
  CareText.qCheckYourAnswers: 'Check your answers',
  CareText.qEdit: 'Edit',
  CareText.qSubmit: 'Submit',
  CareText.qBackToQuestions: 'Back to questions',
  CareText.qProblemIncomplete: 'Please answer the required questions.',
  CareText.qProblemOffline:
      'You seem to be offline. Your answers are kept; connect to submit.',
  CareText.qProblemUnconfirmed: 'We could not confirm your submission. Tap Submit again: it will not be sent twice.',
  CareText.qProblemConflict:
      'These answers were changed somewhere else. Choose which to keep first.',
  CareText.qProblemReauth: 'Please confirm your password to submit.',
  CareText.qSaving: 'Saving…',
  CareText.qSaved: 'Saved',
  CareText.qOfflineNotSynced: 'Offline – not synced',
  CareText.qNotSaved: 'Not saved',
  CareText.qConflict: 'Conflict',
  CareText.qAckTitle: 'Response submitted',
  CareText.qBackToList: 'Back to questionnaires',
  CareText.qNumberInvalid: 'Please enter a number.',
  CareText.qPictureUnavailable: 'Picture unavailable',
  CareText.qSources: 'Source',
  CareText.qIncrease: 'Increase',
  CareText.qDecrease: 'Decrease',
  // Safety plan: NEEDS CLINICIAN REVIEW.
  CareText.spTitle: 'My safety plan',
  CareText.spIntro: 'A plan in your own words for the hard moments. You can add more anytime.',
  CareText.spAddMore: 'You can add more anytime.',
  CareText.spFootnote: 'Based on a widely used safety-planning approach. This does not replace professional help.',
  CareText.spPrivacy:
      'Saved only on this device, encrypted. It is never shared.',
  CareText.spWarningSigns: 'My warning signs',
  CareText.spWarningSignsHelp: 'Thoughts, feelings or situations that tell me a hard time may be starting.',
  CareText.spCopingAlone: 'Things I can do on my own to feel calmer',
  CareText.spCopingAloneHelp:
      'Small things that help me feel a little calmer, like slow breathing.',
  CareText.spDistractions:
      'People and places that help me take my mind off things',
  CareText.spDistractionsHelp:
      'Places to go or people to be around that help me feel less alone.',
  CareText.spPeopleToAsk: 'People I can ask for help',
  CareText.spPeopleToAskHelp:
      'People I trust and can reach out to. A phone number is optional.',
  CareText.spProfessionals: 'Professionals and helplines',
  CareText.spProfessionalsHelp:
      'Helplines and professionals I can contact. 1166 is always here.',
  CareText.spSaferSurroundings: 'Making my surroundings safer',
  CareText.spSaferSurroundingsHelp: 'What could you do to make your surroundings safer when things feel hard?',
  CareText.spReasons: 'My reasons to keep going',
  CareText.spReasonsHelp: 'The people, hopes and things that matter to me.',
  CareText.spHelplineFixed: 'Always here',
  CareText.spAdd: 'Add',
  CareText.spItemLabel: 'In your own words',
  CareText.spPhoneLabel: 'Phone number (optional)',
  CareText.spPhoneInvalid: 'Use digits, spaces, + or - only.',
  CareText.spSaveItem: 'Save',
  CareText.spCancel: 'Cancel',
  CareText.spEditItem: 'Edit',
  CareText.spDelete: 'Delete',
  CareText.spMoveUp: 'Move up',
  CareText.spMoveDown: 'Move down',
  CareText.spMaxItems: 'You can keep up to 10 here.',
  CareText.spSaving: 'Saving…',
  CareText.spSaved: 'Saved on this device',
  CareText.spNotSaved: 'This could not be saved. Please try again.',
  CareText.spLoadError: 'Your plan could not be opened right now.',
  CareText.spLoading: 'Opening your plan…',
  CareText.spEditPlan: 'Edit my plan',
  CareText.spDone: 'Done',
  CareText.spOpen: 'Open my safety plan',
  CareText.spBreathing: 'Try the breathing exercise',
  CareText.spOnboardingTitle: 'Create your safety plan (2 minutes)',
  CareText.spOnboardingBody: 'A few lines in your own words about what helps in hard moments. It stays only on this device. You can do it now or later in Settings.',
  CareText.spCreate: 'Create my safety plan',
  CareText.spNotNow: 'Not now',
  CareText.spCallLabel: 'Call',
  // AUTH-ENTRY.
  CareText.auCreateTitle: 'Create your KOI account',
  CareText.auSignInTitle: 'Sign in',
  CareText.auBusyUpgrade: 'Securing your history…',
  CareText.auBusyCreate: 'Creating your account…',
  CareText.auBusySignIn: 'Signing in…',
  CareText.auUpgradeIntro:
      'Your chats, check-ins and safety plan stay on this account. KOI '
      'encrypts them again with your new password.',
  CareText.auSignInSwitchNote:
      'Signing in to another account does not move this device\'s KOI '
      'history. You will be asked first.',
  CareText.auEmail: 'Email',
  CareText.auPassword: 'Password',
  CareText.auPasswordHint: 'At least 8 characters.',
  CareText.auConfirm: 'Confirm password',
  CareText.auShowPassword: 'Show password',
  CareText.auHidePassword: 'Hide password',
  CareText.auPasswordWarning:
      'Your KOI history is protected with Client-Side Encryption (CSE) at '
      'rest, using your password. If you forget or reset your password, your '
      'saved history cannot be opened again.',
  CareText.auCreateButton: 'Create account',
  CareText.auSignInButton: 'Sign in',
  CareText.auSignInInstead: 'Sign in instead',
  CareText.auForgot: 'Forgot password?',
  CareText.auEnterEmail: 'Please enter your email address.',
  CareText.auEnterPassword: 'Please enter your password.',
  CareText.auPasswordShort: 'Your password needs at least 8 characters.',
  CareText.auMismatch: 'The passwords do not match.',
  CareText.auErrEmailInUse:
      'This email already has a KOI account. Sign in to it instead.',
  CareText.auErrWrong: 'That email and password do not match.',
  CareText.auErrNotFound:
      'We could not find a KOI account with that email. Check it, or create '
      'an account.',
  CareText.auErrWeak:
      'Please choose a stronger password (at least 8 characters).',
  CareText.auErrInvalidEmail: 'Please enter a valid email address.',
  CareText.auErrNetwork:
      'You seem to be offline. Check your connection and try again.',
  CareText.auErrTooMany:
      'Too many attempts. Please wait a moment and try again.',
  CareText.auErrNotAllowed:
      'Account sign-up isn\'t switched on yet. Please try again later.',
  CareText.auErrSalt:
      'Signed in, but your encryption details could not be loaded. Check '
      'your connection and try again.',
  CareText.auErrGeneric: 'Something went wrong. Please try again.',
  CareText.auResetTitle: 'Reset your password?',
  CareText.auResetBody:
      'If you reset your password, the private KOI history saved with your '
      'old password cannot be opened again. Your account stays, but that '
      'history is lost.',
  CareText.auResetSend: 'Send reset email',
  CareText.auResetSending: 'Sending…',
  CareText.auResetSent:
      'If a KOI account exists for this email, a reset link is on its way. '
      'Check your inbox.',
  CareText.auResetNeedEmail: 'Enter your email above first.',
  CareText.auCancel: 'Cancel',
  CareText.auPsychLink: 'I\'m a psychologist',
  CareText.auPsychTitle: 'For psychologists',
  CareText.auPsychBody:
      'Psychologist accounts are created and verified on the KOI website.',
  CareText.auWhy:
      'An account lets you connect with a psychologist and use KOI on '
      'another device.',
  CareText.auCareTitle: 'Connect with a psychologist',
  CareText.auCareWhy:
      'Finding a psychologist, applying and talking with them needs an '
      'account, so your care stays private and only yours.',
  CareText.auCareKeep:
      'Creating an account keeps your chats, check-ins and safety plan, '
      'encrypted again with your new password.',
  CareText.auCareChat: 'You can keep talking to KOI without an account.',
  CareText.auDismiss: 'Dismiss',
  CareText.m4NotSetUp:
      "Your account is created, but care features aren't set up for it yet.",
  CareText.m4NotSetUpChat: 'You can keep talking to KOI as usual.',
  CareText.m4InviteEntry: 'I have an invitation code',
  CareText.m4InviteEntrySub: 'From a psychologist who invited you',
  CareText.m4InviteTitle: 'Invitation code',
  CareText.m4InviteIntro:
      'If a psychologist gave you an invitation code or link, paste it '
      'here to connect with them.',
  CareText.m4InviteLabel: 'Invitation code or link',
  CareText.m4InviteHint: 'Paste the code here',
  CareText.m4InviteConsent:
      'I agree to connect with the psychologist who invited me. They will '
      'be able to message me, arrange appointments and send me '
      'questionnaires through KOI.',
  CareText.m4InviteRedeem: 'Accept invitation',
  CareText.m4InviteRedeeming: 'Accepting…',
  CareText.m4InviteFormat:
      "That doesn't look like an invitation code. Please check it and try "
      'again.',
  CareText.m4InviteNotFound:
      "We couldn't find this invitation for your account.",
  CareText.m4InviteUsed:
      'This code has expired, been cancelled, or was already used.',
  CareText.m4InviteDenied:
      "This invitation can't be used with your account right now.",
  CareText.m4InviteAccepted:
      'Invitation accepted. You are now connected with your psychologist.',
  CareText.m4MessagesCapped:
      'Only part of this conversation could be loaded (1,000 messages).',
  CareText.m4AppointmentsCapped:
      'Only part of your appointments could be loaded (1,000).',
  CareText.m4NotAcceptingNow:
      "This psychologist isn't accepting new patients right now.",
};

// URDU NEEDS NATIVE REVIEW (see the file header).
const Map<CareText, String> _ur = {
  CareText.care: 'نگہداشت',
  CareText.back: 'واپس',
  CareText.retry: 'دوبارہ کوشش کریں',
  CareText.updating: 'تازہ کیا جا رہا ہے…',
  CareText.loading: 'لوڈ ہو رہا ہے…',
  CareText.notAvailableYet: 'یہ ابھی دستیاب نہیں ہے۔',
  CareText.offline:
      'لگتا ہے آپ آف لائن ہیں۔ اپنا کنکشن چیک کریں اور دوبارہ کوشش کریں۔',
  CareText.genericError: 'کچھ غلط ہو گیا۔ براہ کرم دوبارہ کوشش کریں۔',
  CareText.noLongerAvailable: 'یہ اب آپ کے اکاؤنٹ کے لیے دستیاب نہیں ہے۔',
  CareText.rateLimited:
      'بہت زیادہ کوششیں۔ براہ کرم تھوڑا انتظار کریں اور دوبارہ کوشش کریں۔',
  CareText.demoNotice: 'ڈیمو ڈیٹا۔ یہاں کچھ بھی حقیقی نہیں ہے۔',
  CareText.reauthTitle: 'تصدیق کریں کہ یہ آپ ہیں',
  CareText.reauthBody:
      'آپ کی حفاظت کے لیے، جاری رکھنے کے لیے اپنا پاس ورڈ دوبارہ درج کریں۔',
  CareText.reauthPassword: 'پاس ورڈ',
  CareText.reauthConfirm: 'تصدیق کریں',
  CareText.reauthCancel: 'منسوخ کریں',
  CareText.reauthWrong: 'یہ پاس ورڈ کام نہیں آیا۔ براہ کرم دوبارہ کوشش کریں۔',
  CareText.myPsychologist: 'میرے ماہرِ نفسیات',
  CareText.yourPsychologist: 'آپ کے ماہرِ نفسیات',
  CareText.questionnaires: 'سوالنامے',
  CareText.questionnairesSub: 'وہ فارم جو آپ کے ماہرِ نفسیات نے بھرنے کو کہے',
  CareText.messages: 'پیغامات',
  CareText.messagesSub: 'اپنے ماہرِ نفسیات کے ساتھ پیغامات',
  CareText.appointments: 'ملاقاتیں',
  CareText.appointmentsSub: 'ملاقات کی درخواست کریں اور انہیں سنبھالیں',
  CareText.notifications: 'اطلاعات',
  CareText.notificationsSub: 'آپ کی نگہداشت کے بارے میں اپ ڈیٹس',
  CareText.findExpert: 'ماہر تلاش کریں',
  CareText.findExpertSub: 'KOI میں درج ماہرینِ نفسیات دیکھیں',
  CareText.myApplications: 'میری درخواستیں',
  CareText.myApplicationsSub: 'ماہرینِ نفسیات کو بھیجی گئی درخواستیں',
  CareText.notMonitored:
      'آپ کے ماہرِ نفسیات کے ساتھ پیغامات ہنگامی صورتحال کے لیے نہیں دیکھے '
      'جاتے۔ اگر آپ خطرے میں ہیں تو 1166 پر کال کریں۔',
  CareText.expertsIntro: 'وہ ماہرینِ نفسیات جو KOI میں درج ہیں۔',
  CareText.searchLabel: 'نام سے تلاش کریں',
  CareText.acceptingOnly: 'صرف نئے مریض قبول کرنے والے',
  CareText.accepting: 'نئے مریض قبول کر رہے ہیں',
  CareText.notAccepting: 'نئے مریض قبول نہیں کر رہے',
  CareText.noExperts: 'اس وقت کوئی ماہر درج نہیں ہے۔',
  CareText.noMatches: 'آپ کی تلاش سے کوئی ماہرِ نفسیات نہیں ملا۔',
  CareText.loadMore: 'مزید دکھائیں',
  CareText.apply: 'اس ماہرِ نفسیات کے ساتھ کام کرنے کی درخواست دیں',
  CareText.applyTitle: 'درخواست',
  CareText.applyIntro:
      'ماہرِ نفسیات آپ کی درخواست دیکھ کر فیصلہ کریں گے کہ آپ کے ساتھ کام '
      'کریں یا نہیں۔ آپ کی نجی KOI گفتگو کبھی شیئر نہیں کی جاتی۔',
  CareText.consentLabel:
      'میں اتفاق کرتا/کرتی ہوں کہ یہ ماہرِ نفسیات میری درخواست دیکھ سکتے ہیں '
      'اور قبول کرنے پر KOI کے ذریعے مجھ سے رابطہ کر سکتے ہیں۔',
  CareText.consentNeeded: 'جاری رکھنے کے لیے براہ کرم خانے پر نشان لگائیں۔',
  CareText.continueLabel: 'جاری رکھیں',
  CareText.confirmTitle: 'کیا اپنی درخواست بھیجیں؟',
  CareText.confirmBody:
      'جب تک ماہرِ نفسیات فیصلہ نہ کریں، آپ اسے واپس لے سکتے ہیں۔',
  CareText.sendApplication: 'درخواست بھیجیں',
  CareText.sending: 'بھیجا جا رہا ہے…',
  CareText.alreadyConnected: 'آپ پہلے ہی اس ماہرِ نفسیات سے منسلک ہیں۔',
  CareText.appliedBefore:
      'آپ پہلے اس ماہرِ نفسیات کو درخواست دے چکے ہیں۔ دوبارہ درخواست دینا '
      'ابھی دستیاب نہیں ہے۔',
  CareText.viewApplication: 'میری درخواست دیکھیں',
  CareText.notAcceptingCantApply:
      'یہ ماہرِ نفسیات اس وقت نئے مریض قبول نہیں کر رہے۔',
  CareText.stateRequested: 'درخواست دی گئی',
  CareText.stateAwaitingPayment: 'ڈیمو ادائیگی کا انتظار',
  CareText.statePendingReview: 'ماہرِ نفسیات کا انتظار',
  CareText.stateAccepted: 'قبول کر لی گئی',
  CareText.stateDeclined: 'رد کر دی گئی',
  CareText.stateWithdrawn: 'واپس لے لی گئی',
  CareText.paymentPending: 'ادائیگی: زیرِ التوا (فرضی)',
  CareText.paymentConfirmed: 'ادائیگی: تصدیق شدہ (فرضی)',
  CareText.paymentExplainer:
      'یہ ایک ڈیمو مرحلہ ہے۔ کوئی رقم نہیں لی جاتی اور کارڈ کی ضرورت نہیں۔',
  CareText.confirmDemoPayment: 'ڈیمو ادائیگی کی تصدیق کریں (فرضی)',
  CareText.withdraw: 'درخواست واپس لیں',
  CareText.withdrawTitle: 'کیا یہ درخواست واپس لیں؟',
  CareText.withdrawBody: 'ماہرِ نفسیات اسے مزید نہیں دیکھ سکیں گے۔',
  CareText.withdrawYes: 'واپس لیں',
  CareText.keep: 'رہنے دیں',
  CareText.noApplications: 'آپ نے ابھی کسی ماہرِ نفسیات کو درخواست نہیں دی۔',
  CareText.acceptedNote:
      'ماہرِ نفسیات نے آپ کی درخواست قبول کر لی۔ اپنی نگہداشت کی جگہ دیکھنے '
      'کے لیے نگہداشت کو نیچے کھینچیں۔',
  CareText.declinedNote:
      'ماہرِ نفسیات آپ کی درخواست نہیں لے سکے۔ آپ کسی اور ماہرِ نفسیات کو '
      'تلاش کر سکتے ہیں۔',
  CareText.applicationTitle: 'درخواست',
  CareText.professionalMessage: 'پیشہ ورانہ پیغام',
  CareText.noConversations: 'آپ کی ابھی کوئی گفتگو نہیں ہے۔',
  CareText.noMessagesYet:
      'ابھی کوئی پیغام نہیں۔ اپنے ماہرِ نفسیات کو سلام کہیں۔',
  CareText.composerHint: 'پیغام لکھیں',
  CareText.send: 'بھیجیں',
  CareText.messagePending: 'بھیجا جا رہا ہے…',
  CareText.messageFailed: 'ناکام — دوبارہ کوشش کے لیے ٹیپ کریں',
  CareText.safetyFooter:
      'یہ چیٹ ہنگامی صورتحال کے لیے نہیں دیکھی جاتی۔ اگر آپ خطرے میں ہیں تو '
      '1166 پر کال کریں۔',
  CareText.loadOlder: 'پرانے پیغامات دکھائیں',
  CareText.you: 'آپ',
  CareText.unread: 'نہ پڑھا گیا',
  CareText.requestAppointment: 'ملاقات کی درخواست کریں',
  CareText.requestExplainer:
      'آپ کے ماہرِ نفسیات ایک وقت تجویز کریں گے۔ پھر آپ اس کی تصدیق کر سکتے '
      'ہیں۔',
  CareText.requesting: 'درخواست بھیجی جا رہی ہے…',
  CareText.upcoming: 'آنے والی',
  CareText.pending: 'زیرِ التوا',
  CareText.past: 'گزشتہ',
  CareText.cancelled: 'منسوخ شدہ',
  CareText.apptRequested: 'درخواست دی گئی',
  CareText.apptProposed: 'وقت تجویز کیا گیا',
  CareText.apptConfirmed: 'تصدیق شدہ',
  CareText.apptCompleted: 'مکمل',
  CareText.apptRejected: 'ماہرِ نفسیات نے رد کر دی',
  CareText.apptCancelled: 'منسوخ',
  CareText.confirmTime: 'اس وقت کی تصدیق کریں',
  CareText.decline: 'انکار کریں',
  CareText.cancelAppointment: 'ملاقات منسوخ کریں',
  CareText.cancelTitle: 'کیا یہ ملاقات منسوخ کریں؟',
  CareText.cancelBody: 'اسے واپس نہیں کیا جا سکتا۔',
  CareText.cancelYes: 'ملاقات منسوخ کریں',
  CareText.askAnotherTime: 'کسی اور وقت کی درخواست کریں',
  CareText.askAnotherTimeBody:
      'اس سے نئی درخواست بھیجی جاتی ہے۔ آپ کی تصدیق شدہ ملاقات تب تک رہے گی '
      'جب تک آپ اسے منسوخ نہ کریں۔',
  CareText.noTimeYet: 'ابھی کوئی وقت نہیں',
  CareText.noAppointments: 'آپ کی ابھی کوئی ملاقات نہیں ہے۔',
  CareText.appointmentTitle: 'ملاقات',
  CareText.lastUpdated: 'آخری تبدیلی',
  CareText.markAllRead: 'سب کو پڑھا ہوا نشان زد کریں',
  CareText.noNotifications: 'آپ کی کوئی اطلاع نہیں ہے۔',
  CareText.kindAssignment: 'آپ کے لیے ایک نیا سوالنامہ ہے',
  CareText.kindNewMessage: 'آپ کے ماہرِ نفسیات کا نیا پیغام',
  CareText.kindAppointment: 'ایک ملاقات میں تبدیلی ہوئی',
  CareText.kindApplication: 'آپ کی درخواست میں تبدیلی ہوئی',
  CareText.ok: 'ٹھیک ہے',
  CareText.simulateTitle: 'ماہرِ نفسیات کی نقل (ڈیبگ)',
  CareText.qLoadingList: 'سوالنامے کھل رہے ہیں',
  CareText.qNothing: 'ابھی بھرنے کے لیے کچھ نہیں ہے۔',
  CareText.qStateAssigned: 'شروع نہیں ہوا',
  CareText.qStateInProgress: 'جاری ہے',
  CareText.qStateSubmitted: 'جمع ہو گیا',
  CareText.qLoading: 'سوالنامہ کھل رہا ہے…',
  CareText.qSubmitting: 'جمع ہو رہا ہے…',
  CareText.qOfflineOpen:
      'لگتا ہے آپ آف لائن ہیں۔ یہ سوالنامہ کھولنے کے لیے کنکشن ضروری ہے۔',
  CareText.qGone: 'یہ سوالنامہ اب دستیاب نہیں ہے۔',
  CareText.qUnsupported: 'یہ سوالنامہ ایپ کے اس ورژن میں نہیں دکھایا جا سکتا۔ براہِ کرم اپنے ماہرِ نفسیات کو بتائیں۔',
  CareText.qConflictTitle: 'یہ جوابات کسی اور جگہ بدلے گئے ہیں۔',
  CareText.qConflictBody:
      'چنیں کہ کون سے جوابات رکھنے ہیں۔ کچھ ملایا نہیں جاتا۔',
  CareText.qUseServer: 'محفوظ شدہ جوابات لائیں',
  CareText.qKeepMine: 'اس فون کے جوابات رکھیں',
  CareText.qPrevious: 'پچھلا',
  CareText.qNext: 'اگلا',
  CareText.qCheckAnswers: 'جوابات دیکھیں',
  CareText.qStartAgain: 'دوبارہ شروع کریں',
  CareText.qRestartTitle: 'دوبارہ شروع کریں؟',
  CareText.qRestartBody:
      'اس سوالنامے کے آپ کے جوابات مٹ جائیں گے۔ اسے واپس نہیں کیا جا سکتا۔',
  CareText.qCancel: 'منسوخ کریں',
  CareText.qPleaseAnswer: 'براہِ کرم اس سوال کا جواب دیں۔',
  CareText.qOptional: '(اختیاری)',
  CareText.qNoAnswer: 'کوئی جواب نہیں',
  CareText.qCheckYourAnswers: 'اپنے جوابات دیکھیں',
  CareText.qEdit: 'بدلیں',
  CareText.qSubmit: 'جمع کریں',
  CareText.qBackToQuestions: 'سوالات پر واپس',
  CareText.qProblemIncomplete: 'براہِ کرم ضروری سوالات کے جواب دیں۔',
  CareText.qProblemOffline: 'لگتا ہے آپ آف لائن ہیں۔ آپ کے جوابات رکھے گئے ہیں؛ جمع کرنے کے لیے کنکشن جوڑیں۔',
  CareText.qProblemUnconfirmed: 'ہم آپ کے جمع کرانے کی تصدیق نہیں کر سکے۔ دوبارہ "جمع کریں" دبائیں: یہ دو بار نہیں بھیجا جائے گا۔',
  CareText.qProblemConflict:
      'یہ جوابات کسی اور جگہ بدلے گئے ہیں۔ پہلے چنیں کہ کون سے رکھنے ہیں۔',
  CareText.qProblemReauth: 'جمع کرنے کے لیے براہِ کرم اپنا پاس ورڈ تصدیق کریں۔',
  CareText.qSaving: 'محفوظ ہو رہا ہے…',
  CareText.qSaved: 'محفوظ ہو گیا',
  CareText.qOfflineNotSynced: 'آف لائن – ہم آہنگ نہیں',
  CareText.qNotSaved: 'محفوظ نہیں ہوا',
  CareText.qConflict: 'تضاد',
  CareText.qAckTitle: 'جواب جمع ہو گیا',
  CareText.qBackToList: 'سوالناموں پر واپس',
  CareText.qNumberInvalid: 'براہِ کرم ایک عدد لکھیں۔',
  CareText.qPictureUnavailable: 'تصویر دستیاب نہیں',
  CareText.qSources: 'ماخذ',
  CareText.qIncrease: 'بڑھائیں',
  CareText.qDecrease: 'گھٹائیں',
  // Safety plan: NEEDS CLINICIAN REVIEW and NEEDS NATIVE REVIEW.
  CareText.spTitle: 'میرا حفاظتی منصوبہ',
  CareText.spIntro: 'مشکل لمحوں کے لیے آپ کے اپنے الفاظ میں ایک منصوبہ۔ آپ جب چاہیں اس میں مزید لکھ سکتے ہیں۔',
  CareText.spAddMore: 'آپ جب چاہیں مزید لکھ سکتے ہیں۔',
  CareText.spFootnote: 'یہ حفاظتی منصوبہ بندی کے ایک عام طریقے پر مبنی ہے۔ یہ پیشہ ورانہ مدد کا متبادل نہیں ہے۔',
  CareText.spPrivacy: 'صرف اسی ڈیوائس پر، خفیہ (encrypted) شکل میں محفوظ۔ یہ کبھی کسی کے ساتھ شیئر نہیں ہوتا۔',
  CareText.spWarningSigns: 'میری انتباہی علامات',
  CareText.spWarningSignsHelp:
      'وہ خیالات، احساسات یا حالات جو بتاتے ہیں کہ مشکل وقت شروع ہو سکتا ہے۔',
  CareText.spCopingAlone:
      'وہ کام جو میں خود کر کے پرسکون محسوس کر سکتا/سکتی ہوں',
  CareText.spCopingAloneHelp:
      'چھوٹی چیزیں جو مجھے تھوڑا پرسکون کرتی ہیں، جیسے آہستہ سانس لینا۔',
  CareText.spDistractions: 'لوگ اور جگہیں جو میرا دھیان بٹانے میں مدد کرتی ہیں',
  CareText.spDistractionsHelp:
      'وہ جگہیں یا لوگ جن کے ساتھ میں کم تنہا محسوس کرتا/کرتی ہوں۔',
  CareText.spPeopleToAsk: 'وہ لوگ جن سے میں مدد مانگ سکتا/سکتی ہوں',
  CareText.spPeopleToAskHelp:
      'وہ لوگ جن پر مجھے بھروسہ ہے۔ فون نمبر لکھنا ضروری نہیں۔',
  CareText.spProfessionals: 'ماہرین اور ہیلپ لائنز',
  CareText.spProfessionalsHelp: 'ہیلپ لائنز اور ماہرین جن سے میں رابطہ کر سکتا/سکتی ہوں۔ 1166 ہمیشہ یہاں موجود ہے۔',
  CareText.spSaferSurroundings: 'اپنے ماحول کو زیادہ محفوظ بنانا',
  CareText.spSaferSurroundingsHelp: 'جب حالات مشکل لگیں تو آپ اپنے ماحول کو زیادہ محفوظ بنانے کے لیے کیا کر سکتے ہیں؟',
  CareText.spReasons: 'آگے بڑھتے رہنے کی میری وجوہات',
  CareText.spReasonsHelp: 'وہ لوگ، امیدیں اور چیزیں جو میرے لیے اہم ہیں۔',
  CareText.spHelplineFixed: 'ہمیشہ موجود',
  CareText.spAdd: 'شامل کریں',
  CareText.spItemLabel: 'اپنے الفاظ میں',
  CareText.spPhoneLabel: 'فون نمبر (اختیاری)',
  CareText.spPhoneInvalid: 'صرف ہندسے، خالی جگہ، + یا - استعمال کریں۔',
  CareText.spSaveItem: 'محفوظ کریں',
  CareText.spCancel: 'منسوخ کریں',
  CareText.spEditItem: 'ترمیم کریں',
  CareText.spDelete: 'حذف کریں',
  CareText.spMoveUp: 'اوپر کریں',
  CareText.spMoveDown: 'نیچے کریں',
  CareText.spMaxItems: 'یہاں آپ زیادہ سے زیادہ 10 رکھ سکتے ہیں۔',
  CareText.spSaving: 'محفوظ ہو رہا ہے…',
  CareText.spSaved: 'اس ڈیوائس پر محفوظ ہو گیا',
  CareText.spNotSaved: 'یہ محفوظ نہیں ہو سکا۔ براہِ کرم دوبارہ کوشش کریں۔',
  CareText.spLoadError: 'آپ کا منصوبہ اس وقت نہیں کھل سکا۔',
  CareText.spLoading: 'آپ کا منصوبہ کھل رہا ہے…',
  CareText.spEditPlan: 'اپنے منصوبے میں ترمیم کریں',
  CareText.spDone: 'مکمل',
  CareText.spOpen: 'میرا حفاظتی منصوبہ کھولیں',
  CareText.spBreathing: 'سانس کی مشق کریں',
  CareText.spOnboardingTitle: 'اپنا حفاظتی منصوبہ بنائیں (2 منٹ)',
  CareText.spOnboardingBody: 'مشکل لمحوں میں کیا مدد کرتا ہے، اس بارے میں اپنے الفاظ میں چند سطریں۔ یہ صرف اسی ڈیوائس پر رہتا ہے۔ آپ ابھی یا بعد میں سیٹنگز میں بنا سکتے ہیں۔',
  CareText.spCreate: 'اپنا حفاظتی منصوبہ بنائیں',
  CareText.spNotNow: 'ابھی نہیں',
  CareText.spCallLabel: 'کال کریں',
  // AUTH-ENTRY. NEEDS NATIVE REVIEW.
  CareText.auCreateTitle: 'اپنا KOI اکاؤنٹ بنائیں',
  CareText.auSignInTitle: 'سائن ان',
  CareText.auBusyUpgrade: 'آپ کی تاریخ محفوظ کی جا رہی ہے…',
  CareText.auBusyCreate: 'آپ کا اکاؤنٹ بن رہا ہے…',
  CareText.auBusySignIn: 'سائن ان ہو رہا ہے…',
  CareText.auUpgradeIntro:
      'آپ کی بات چیت، چیک اِنز اور حفاظتی منصوبہ اسی اکاؤنٹ میں رہیں گے۔ '
      'KOI انہیں آپ کے نئے پاس ورڈ سے دوبارہ خفیہ کرتا ہے۔',
  CareText.auSignInSwitchNote:
      'کسی دوسرے اکاؤنٹ میں سائن ان کرنے سے اس ڈیوائس کی KOI تاریخ منتقل '
      'نہیں ہوتی۔ پہلے آپ سے پوچھا جائے گا۔',
  CareText.auEmail: 'ای میل',
  CareText.auPassword: 'پاس ورڈ',
  CareText.auPasswordHint: 'کم از کم 8 حروف۔',
  CareText.auConfirm: 'پاس ورڈ کی تصدیق کریں',
  CareText.auShowPassword: 'پاس ورڈ دکھائیں',
  CareText.auHidePassword: 'پاس ورڈ چھپائیں',
  CareText.auPasswordWarning:
      'آپ کی KOI تاریخ آپ کے پاس ورڈ کے ساتھ Client-Side Encryption (CSE) '
      'at rest سے محفوظ ہے۔ اگر آپ اپنا پاس ورڈ بھول جائیں یا ری سیٹ کریں تو '
      'آپ کی محفوظ تاریخ دوبارہ نہیں کھل سکے گی۔',
  CareText.auCreateButton: 'اکاؤنٹ بنائیں',
  CareText.auSignInButton: 'سائن ان کریں',
  CareText.auSignInInstead: 'اس کے بجائے سائن ان کریں',
  CareText.auForgot: 'پاس ورڈ بھول گئے؟',
  CareText.auEnterEmail: 'براہ کرم اپنا ای میل پتا لکھیں۔',
  CareText.auEnterPassword: 'براہ کرم اپنا پاس ورڈ لکھیں۔',
  CareText.auPasswordShort: 'پاس ورڈ کم از کم 8 حروف کا ہونا چاہیے۔',
  CareText.auMismatch: 'دونوں پاس ورڈ ایک جیسے نہیں ہیں۔',
  CareText.auErrEmailInUse:
      'اس ای میل کا پہلے سے KOI اکاؤنٹ موجود ہے۔ اس کے بجائے اس میں سائن ان '
      'کریں۔',
  CareText.auErrWrong: 'یہ ای میل اور پاس ورڈ آپس میں نہیں ملتے۔',
  CareText.auErrNotFound:
      'اس ای میل کا کوئی KOI اکاؤنٹ نہیں ملا۔ ای میل چیک کریں، یا نیا اکاؤنٹ '
      'بنائیں۔',
  CareText.auErrWeak: 'براہ کرم زیادہ مضبوط پاس ورڈ چنیں (کم از کم 8 حروف)۔',
  CareText.auErrInvalidEmail: 'براہ کرم درست ای میل پتا لکھیں۔',
  CareText.auErrNetwork:
      'لگتا ہے آپ آف لائن ہیں۔ اپنا کنکشن چیک کریں اور دوبارہ کوشش کریں۔',
  CareText.auErrTooMany:
      'بہت زیادہ کوششیں ہو گئیں۔ تھوڑی دیر رکیں اور دوبارہ کوشش کریں۔',
  CareText.auErrNotAllowed:
      'اکاؤنٹ بنانے کی سہولت ابھی شروع نہیں ہوئی۔ براہ کرم بعد میں دوبارہ '
      'کوشش کریں۔',
  CareText.auErrSalt:
      'سائن ان ہو گیا، لیکن آپ کی خفیہ کاری کی تفصیلات لوڈ نہیں ہو سکیں۔ '
      'اپنا کنکشن چیک کریں اور دوبارہ کوشش کریں۔',
  CareText.auErrGeneric: 'کچھ غلط ہو گیا۔ براہ کرم دوبارہ کوشش کریں۔',
  CareText.auResetTitle: 'پاس ورڈ ری سیٹ کریں؟',
  CareText.auResetBody:
      'اگر آپ پاس ورڈ ری سیٹ کرتے ہیں تو پرانے پاس ورڈ سے محفوظ کی گئی آپ '
      'کی نجی KOI تاریخ دوبارہ نہیں کھل سکے گی۔ آپ کا اکاؤنٹ باقی رہے گا، '
      'لیکن وہ تاریخ ضائع ہو جائے گی۔',
  CareText.auResetSend: 'ری سیٹ ای میل بھیجیں',
  CareText.auResetSending: 'بھیجی جا رہی ہے…',
  CareText.auResetSent:
      'اگر اس ای میل کا KOI اکاؤنٹ موجود ہے تو ری سیٹ لنک بھیج دیا گیا ہے۔ '
      'اپنا ان باکس دیکھیں۔',
  CareText.auResetNeedEmail: 'پہلے اوپر اپنا ای میل لکھیں۔',
  CareText.auCancel: 'منسوخ کریں',
  CareText.auPsychLink: 'میں ماہرِ نفسیات ہوں',
  CareText.auPsychTitle: 'ماہرینِ نفسیات کے لیے',
  CareText.auPsychBody:
      'ماہرینِ نفسیات کے اکاؤنٹ KOI ویب سائٹ پر بنائے اور تصدیق کیے جاتے '
      'ہیں۔',
  CareText.auWhy:
      'اکاؤنٹ کے ذریعے آپ کسی ماہرِ نفسیات سے رابطہ کر سکتے ہیں اور KOI کو '
      'دوسری ڈیوائس پر استعمال کر سکتے ہیں۔',
  CareText.auCareTitle: 'کسی ماہرِ نفسیات سے رابطہ کریں',
  CareText.auCareWhy:
      'ماہرِ نفسیات تلاش کرنے، درخواست دینے اور ان سے بات کرنے کے لیے اکاؤنٹ '
      'ضروری ہے، تاکہ آپ کی دیکھ بھال نجی اور صرف آپ کی رہے۔',
  CareText.auCareKeep:
      'اکاؤنٹ بنانے سے آپ کی بات چیت، چیک اِنز اور حفاظتی منصوبہ برقرار رہتے '
      'ہیں، آپ کے نئے پاس ورڈ سے دوبارہ خفیہ کر کے۔',
  CareText.auCareChat: 'آپ اکاؤنٹ کے بغیر بھی KOI سے بات جاری رکھ سکتے ہیں۔',
  CareText.auDismiss: 'بند کریں',
  CareText.m4NotSetUp:
      'آپ کا اکاؤنٹ بن گیا ہے، لیکن اس کے لیے نگہداشت کی سہولیات ابھی ترتیب '
      'نہیں دی گئیں۔',
  CareText.m4NotSetUpChat: 'آپ پہلے کی طرح KOI سے بات جاری رکھ سکتے ہیں۔',
  CareText.m4InviteEntry: 'میرے پاس دعوتی کوڈ ہے',
  CareText.m4InviteEntrySub: 'اُس ماہرِ نفسیات کی طرف سے جس نے آپ کو مدعو کیا',
  CareText.m4InviteTitle: 'دعوتی کوڈ',
  CareText.m4InviteIntro:
      'اگر کسی ماہرِ نفسیات نے آپ کو دعوتی کوڈ یا لنک دیا ہے تو اُن سے منسلک '
      'ہونے کے لیے اسے یہاں پیسٹ کریں۔',
  CareText.m4InviteLabel: 'دعوتی کوڈ یا لنک',
  CareText.m4InviteHint: 'کوڈ یہاں پیسٹ کریں',
  CareText.m4InviteConsent:
      'میں اُس ماہرِ نفسیات سے منسلک ہونے پر متفق ہوں جس نے مجھے مدعو کیا۔ وہ '
      'KOI کے ذریعے مجھے پیغام بھیج سکیں گے، ملاقاتیں طے کر سکیں گے اور '
      'سوالنامے بھیج سکیں گے۔',
  CareText.m4InviteRedeem: 'دعوت قبول کریں',
  CareText.m4InviteRedeeming: 'قبول کی جا رہی ہے…',
  CareText.m4InviteFormat:
      'یہ دعوتی کوڈ نہیں لگتا۔ براہِ کرم اسے چیک کر کے دوبارہ کوشش کریں۔',
  CareText.m4InviteNotFound: 'یہ دعوت آپ کے اکاؤنٹ کے لیے نہیں ملی۔',
  CareText.m4InviteUsed:
      'اس کوڈ کی میعاد ختم ہو چکی ہے، یہ منسوخ ہو چکا ہے، یا پہلے ہی استعمال ہو '
      'چکا ہے۔',
  CareText.m4InviteDenied:
      'یہ دعوت ابھی آپ کے اکاؤنٹ کے ساتھ استعمال نہیں ہو سکتی۔',
  CareText.m4InviteAccepted:
      'دعوت قبول ہو گئی۔ اب آپ اپنے ماہرِ نفسیات سے منسلک ہیں۔',
  CareText.m4MessagesCapped:
      'اس گفتگو کا صرف ایک حصہ لوڈ ہو سکا (1,000 پیغامات)۔',
  CareText.m4AppointmentsCapped:
      'آپ کی ملاقاتوں کا صرف ایک حصہ لوڈ ہو سکا (1,000)۔',
  CareText.m4NotAcceptingNow: 'یہ ماہرِ نفسیات ابھی نئے مریض قبول نہیں کر رہے۔',
};

/// The strings and direction of the new Care screens.
@immutable
class CareStrings {
  const CareStrings(this.lang);

  static const CareStrings en = CareStrings(CareLang.en);
  static const CareStrings ur = CareStrings(CareLang.ur);

  final CareLang lang;

  bool get isUrdu => lang == CareLang.ur;
  TextDirection get direction => isUrdu ? TextDirection.rtl : TextDirection.ltr;

  /// Urdu script needs a taller line (same as the MOB-1 questionnaire
  /// text); the glyphs come from the system Urdu font.
  double get lineHeight => isUrdu ? 1.9 : 1.5;

  String t(CareText k) => (isUrdu ? _ur : _en)[k] ?? _en[k]!;

  /// For the completeness test.
  static Map<CareText, String> table(CareLang lang) =>
      lang == CareLang.ur ? _ur : _en;

  String messageTo(String name) =>
      isUrdu ? '$name کو پیغام' : 'Message to $name';

  /// "Question 3 of 7" (questionnaire progress).
  String questionOf(int n, int total) =>
      isUrdu ? 'سوال $n از $total' : 'Question $n of $total';

  String charCount(int n, int max) => '$n / $max';

  String numberBelowMin(String min) => isUrdu
      ? 'سب سے کم اجازت شدہ عدد $min ہے۔'
      : 'The lowest allowed number is $min.';

  String numberAboveMax(String max) => isUrdu
      ? 'سب سے زیادہ اجازت شدہ عدد $max ہے۔'
      : 'The highest allowed number is $max.';

  String numberStep(String step) =>
      isUrdu ? '$step کے وقفے سے لکھیں۔' : 'Use steps of $step.';

  String numberRange(String min, String max) =>
      isUrdu ? '$min سے $max تک' : 'From $min to $max';

  String submittedAt(String time) =>
      isUrdu ? 'جمع کرنے کا وقت: $time' : 'Submitted at $time';

  String unreadCount(int n) => isUrdu ? '$n نہ پڑھے گئے' : '$n unread';

  String notificationsBell(int n) =>
      isUrdu ? 'اطلاعات، $n نہ پڑھی گئیں' : 'Notifications, $n unread';

  /// "Mon 20 Oct, 14:30" in the phone's local time zone.
  String dateTime(DateTime utc) {
    final d = utc.toLocal();
    final hh = d.hour.toString().padLeft(2, '0');
    final mm = d.minute.toString().padLeft(2, '0');
    final day = (isUrdu ? _urDays : _enDays)[d.weekday - 1];
    final month = (isUrdu ? _urMonths : _enMonths)[d.month - 1];
    return '$day ${d.day} $month, $hh:$mm';
  }

  /// "14:30 – 15:20" or the start alone.
  String timeRange(DateTime? start, DateTime? end) {
    if (start == null) return t(CareText.noTimeYet);
    final s = dateTime(start);
    if (end == null) return s;
    final e = end.toLocal();
    return '$s – ${e.hour.toString().padLeft(2, '0')}:'
        '${e.minute.toString().padLeft(2, '0')}';
  }

  static const _enDays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  static const _urDays = [
    'پیر',
    'منگل',
    'بدھ',
    'جمعرات',
    'جمعہ',
    'ہفتہ',
    'اتوار',
  ];
  static const _enMonths = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  static const _urMonths = [
    'جنوری',
    'فروری',
    'مارچ',
    'اپریل',
    'مئی',
    'جون',
    'جولائی',
    'اگست',
    'ستمبر',
    'اکتوبر',
    'نومبر',
    'دسمبر',
  ];
}

/// The signed-in user's saved Settings language ('en' | 'ur'); English
/// while loading or when nothing is saved. Re-read whenever a Care screen
/// is rebuilt after the Care tab was left (autoDispose).
final careLanguageProvider = FutureProvider.autoDispose<CareLang>((ref) async {
  final uid = ref.watch(authServiceProvider.select((a) => a.user?.uid));
  if (uid == null) return CareLang.en;
  try {
    final prefs = await ref.read(settingsPrefsStoreProvider).load(uid);
    return prefs.language == 'ur' ? CareLang.ur : CareLang.en;
  } catch (_) {
    return CareLang.en;
  }
});

final careStringsProvider = Provider.autoDispose<CareStrings>((ref) {
  final lang = ref.watch(careLanguageProvider).valueOrNull ?? CareLang.en;
  return lang == CareLang.ur ? CareStrings.ur : CareStrings.en;
});
