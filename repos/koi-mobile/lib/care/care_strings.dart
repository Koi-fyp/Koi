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
