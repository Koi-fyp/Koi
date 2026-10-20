import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';
import '../care/care_strings.dart';
import '../care/care_widgets.dart';
import '../core/auth/auth_service.dart';
import '../core/crypto_context.dart';
import '../widgets/koi_loader.dart';
import '../widgets/neo_button.dart';
import '../widgets/neo_card.dart';
import '../widgets/neo_input.dart';
import 'account_providers.dart';
import 'account_widgets.dart';
import 'auth_entry_widgets.dart';

/// What the account form does.
enum AccountFormMode {
  /// Anonymous → registered, same uid (linkWithCredential).
  upgrade,

  /// Signed out → a new account.
  create,

  /// An existing account (from signed out, or from anonymous: then this
  /// device's history is only OFFERED for a claim afterwards).
  signIn,
}

/// The plain password warning (decided 2026-10-19), on sign-up and unlock.
const String passwordWarning =
    'Your KOI history is protected with Client-Side Encryption (CSE) at '
    'rest, using your password. If you forget or reset your password, your '
    'saved history cannot be opened again.';

/// AUTH-ENTRY: new accounts need at least this many characters (Firebase
/// itself only asks for 6). Signing in to an older account does not check it.
const int minPasswordLength = 8;

/// A friendly line for every account error; never the raw Firebase text.
CareText accountErrorKey(Object e) => switch (e) {
  AccountAuthException(error: AccountAuthError.emailInUse) =>
    CareText.auErrEmailInUse,
  AccountAuthException(error: AccountAuthError.wrongCredentials) =>
    CareText.auErrWrong,
  AccountAuthException(error: AccountAuthError.accountNotFound) =>
    CareText.auErrNotFound,
  AccountAuthException(error: AccountAuthError.weakPassword) =>
    CareText.auErrWeak,
  AccountAuthException(error: AccountAuthError.invalidEmail) =>
    CareText.auErrInvalidEmail,
  AccountAuthException(error: AccountAuthError.network) =>
    CareText.auErrNetwork,
  AccountAuthException(error: AccountAuthError.tooManyRequests) =>
    CareText.auErrTooMany,
  AccountAuthException(error: AccountAuthError.notSupported) =>
    CareText.auErrNotAllowed,
  SaltFetchBlockedError() => CareText.auErrSalt,
  _ => CareText.auErrGeneric,
};

/// English (the unlock and claim screens).
String accountErrorText(Object e) => CareStrings.en.t(accountErrorKey(e));

/// Sign in / create account / save anonymous history to an account.
class AccountAuthScreen extends ConsumerStatefulWidget {
  const AccountAuthScreen({super.key, required this.mode});

  final AccountFormMode mode;

  @override
  ConsumerState<AccountAuthScreen> createState() => _AccountAuthScreenState();
}

class _AccountAuthScreenState extends ConsumerState<AccountAuthScreen> {
  late AccountFormMode _mode = widget.mode;
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  bool _showPassword = false;
  CareText? _emailError;
  CareText? _passwordError;
  CareText? _confirmError;
  CareText? _error;
  bool _offerSignIn = false;
  bool _offerCreate = false;
  bool _resetBusy = false;
  bool _resetSent = false;

  bool get _creating => _mode != AccountFormMode.signIn;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  CareText get _title =>
      _creating ? CareText.auCreateTitle : CareText.auSignInTitle;

  CareText get _busyLabel => switch (_mode) {
    AccountFormMode.upgrade => CareText.auBusyUpgrade,
    AccountFormMode.create => CareText.auBusyCreate,
    AccountFormMode.signIn => CareText.auBusySignIn,
  };

  static bool _looksLikeEmail(String email) {
    final at = email.indexOf('@');
    return at > 0 && at < email.length - 1 && !email.contains(' ');
  }

  CareText? _checkEmail(String email) {
    if (email.isEmpty) return CareText.auEnterEmail;
    if (!_looksLikeEmail(email)) return CareText.auErrInvalidEmail;
    return null;
  }

  void _switchTo(AccountFormMode mode) => setState(() {
    _mode = mode;
    _error = null;
    _emailError = _passwordError = _confirmError = null;
    _offerSignIn = _offerCreate = false;
    _resetSent = false;
  });

  Future<void> _submit() async {
    final email = _email.text.trim();
    final password = _password.text;
    final emailError = _checkEmail(email);
    final passwordError = password.isEmpty
        ? CareText.auEnterPassword
        : (_creating && password.length < minPasswordLength
              ? CareText.auPasswordShort
              : null);
    final confirmError = _creating && password != _confirm.text
        ? CareText.auMismatch
        : null;
    setState(() {
      _emailError = emailError;
      _passwordError = passwordError;
      _confirmError = passwordError == null ? confirmError : null;
      _error = null;
      _offerSignIn = _offerCreate = false;
      _resetSent = false;
    });
    if (emailError != null || passwordError != null || confirmError != null) {
      return;
    }
    setState(() => _busy = true);
    final account = ref.read(accountControllerProvider);
    final anonymous = ref.read(authServiceProvider).isAnonymous;
    try {
      switch (_mode) {
        case AccountFormMode.upgrade:
          await account.upgradeAnonymous(email, password);
        case AccountFormMode.create:
          await account.createAccount(email, password);
        case AccountFormMode.signIn:
          await account.signInExisting(email, password);
      }
      if (mounted) Navigator.of(context).maybePop();
    } catch (e) {
      if (!mounted) return;
      final error = e is AccountAuthException ? e.error : null;
      setState(() {
        _busy = false;
        _error = accountErrorKey(e);
        _offerSignIn = _creating && error == AccountAuthError.emailInUse;
        _offerCreate =
            !_creating &&
            error == AccountAuthError.accountNotFound &&
            (anonymous || ref.read(authServiceProvider).user == null);
      });
    }
  }

  /// "Forgot password?": warn first (a reset makes the old CSE history
  /// unreadable), then ask Firebase to send its reset email.
  Future<void> _forgot(CareStrings s) async {
    final email = _email.text.trim();
    final emailError = _checkEmail(email);
    if (emailError != null) {
      setState(() {
        _emailError = email.isEmpty ? CareText.auResetNeedEmail : emailError;
        _resetSent = false;
      });
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => Directionality(
        textDirection: s.direction,
        child: Dialog(
          backgroundColor: Colors.transparent,
          elevation: 0,
          insetPadding: const EdgeInsets.all(20),
          child: NeoCard(
            key: const Key('reset-dialog'),
            variant: NeoCardVariant.elevated,
            padding: const EdgeInsets.all(20),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Semantics(
                    header: true,
                    child: Text(
                      s.t(CareText.auResetTitle),
                      style: koiTitleStyle(22)
                          .copyWith(height: s.isUrdu ? 1.6 : null),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    s.t(CareText.auResetBody),
                    key: const Key('reset-warning'),
                    style: careBody(s),
                  ),
                  const SizedBox(height: 8),
                  Text(s.t(CareText.auPasswordWarning), style: careMuted(s)),
                  const SizedBox(height: 20),
                  NeoButton(
                    key: const Key('reset-confirm'),
                    fullWidth: true,
                    onPressed: () => Navigator.of(context).pop(true),
                    child: CareButtonLabel(s.t(CareText.auResetSend)),
                  ),
                  const SizedBox(height: 10),
                  NeoButton(
                    key: const Key('reset-cancel'),
                    variant: NeoButtonVariant.ghost,
                    fullWidth: true,
                    onPressed: () => Navigator.of(context).pop(false),
                    child: CareButtonLabel(s.t(CareText.auCancel)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    if (ok != true || !mounted) return;
    setState(() {
      _resetBusy = true;
      _error = null;
      _emailError = null;
      _resetSent = false;
    });
    CareText? error;
    try {
      await ref.read(authServiceProvider).sendPasswordResetEmail(email);
    } on AccountAuthException catch (e) {
      // Never say whether an account exists for this email.
      if (e.error != AccountAuthError.accountNotFound) {
        error = accountErrorKey(e);
      }
    } catch (e) {
      error = accountErrorKey(e);
    }
    if (!mounted) return;
    setState(() {
      _resetBusy = false;
      _error = error;
      _resetSent = error == null;
    });
  }

  Widget _fieldError(CareText? error, String key, CareStrings s) =>
      error == null
      ? const SizedBox.shrink()
      : Padding(
          padding: const EdgeInsets.only(top: 8),
          child: KeyedSubtree(key: Key(key), child: KoiErrorText(s.t(error))),
        );

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(careStringsProvider);
    if (_busy) {
      return Directionality(
        textDirection: s.direction,
        child: Scaffold(body: KoiLoadingPage(label: s.t(_busyLabel))),
      );
    }
    final anonymous = ref.watch(authServiceProvider).isAnonymous;
    return Directionality(
      textDirection: s.direction,
      child: KoiPage(
        back: true,
        backLabel: s.t(CareText.back),
        children: [
          // KoiPage's title, with the taller Urdu line.
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Semantics(
              header: true,
              child: Text(
                s.t(_title),
                key: const Key('account-title'),
                style: koiTitleStyle().copyWith(height: s.isUrdu ? 1.6 : null),
              ),
            ),
          ),
          if (_mode == AccountFormMode.upgrade)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Text(s.t(CareText.auUpgradeIntro), style: careBody(s)),
            ),
          if (_mode == AccountFormMode.signIn && anonymous)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Text(s.t(CareText.auSignInSwitchNote), style: careBody(s)),
            ),
          NeoInput(
            key: const Key('account-email'),
            label: s.t(CareText.auEmail),
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            textDirection: TextDirection.ltr,
          ),
          _fieldError(_emailError, 'account-email-error', s),
          const SizedBox(height: 14),
          NeoInput(
            key: const Key('account-password'),
            label: s.t(CareText.auPassword),
            controller: _password,
            obscureText: !_showPassword,
            textDirection: TextDirection.ltr,
          ),
          if (_creating)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(s.t(CareText.auPasswordHint), style: careMuted(s)),
            ),
          _fieldError(_passwordError, 'account-password-error', s),
          if (_creating) ...[
            const SizedBox(height: 14),
            NeoInput(
              key: const Key('account-confirm'),
              label: s.t(CareText.auConfirm),
              controller: _confirm,
              obscureText: !_showPassword,
              textDirection: TextDirection.ltr,
            ),
            _fieldError(_confirmError, 'account-confirm-error', s),
          ],
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: KoiTextLink(
              key: const Key('account-show-password'),
              strings: s,
              label: s.t(
                _showPassword
                    ? CareText.auHidePassword
                    : CareText.auShowPassword,
              ),
              onTap: () => setState(() => _showPassword = !_showPassword),
            ),
          ),
          if (_creating) ...[
            const SizedBox(height: 8),
            Text(
              s.t(CareText.auPasswordWarning),
              key: const Key('password-warning'),
              style: careMuted(s),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 16),
            KeyedSubtree(
              key: const Key('account-error'),
              child: KoiErrorText(s.t(_error!)),
            ),
          ],
          if (_resetSent) ...[
            const SizedBox(height: 16),
            KoiNoticeCard(
              key: const Key('account-reset-sent'),
              message: s.t(CareText.auResetSent),
            ),
          ],
          const SizedBox(height: 24),
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: koiMinTouch),
            child: NeoButton(
              key: const Key('account-submit'),
              fullWidth: true,
              onPressed: _resetBusy ? null : _submit,
              child: CareButtonLabel(
                s.t(
                  _creating ? CareText.auCreateButton : CareText.auSignInButton,
                ),
              ),
            ),
          ),
          if (_offerSignIn) ...[
            const SizedBox(height: 14),
            NeoButton(
              key: const Key('account-sign-in-instead'),
              variant: NeoButtonVariant.ghost,
              fullWidth: true,
              onPressed: () => _switchTo(AccountFormMode.signIn),
              child: CareButtonLabel(s.t(CareText.auSignInInstead)),
            ),
          ],
          if (_offerCreate) ...[
            const SizedBox(height: 14),
            NeoButton(
              key: const Key('account-create-instead'),
              variant: NeoButtonVariant.ghost,
              fullWidth: true,
              onPressed: () => _switchTo(
                anonymous ? AccountFormMode.upgrade : AccountFormMode.create,
              ),
              child: CareButtonLabel(s.t(CareText.auCreateButton)),
            ),
          ],
          if (!_creating) ...[
            const SizedBox(height: 8),
            if (_resetBusy)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: KoiLoader(
                  compact: true,
                  label: s.t(CareText.auResetSending),
                ),
              )
            else
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: KoiTextLink(
                  key: const Key('account-forgot'),
                  strings: s,
                  label: s.t(CareText.auForgot),
                  onTap: () => _forgot(s),
                ),
              ),
          ],
          const SizedBox(height: 8),
          const Align(
            alignment: AlignmentDirectional.centerStart,
            child: PsychologistLink(),
          ),
        ],
      ),
    );
  }
}
