import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';
import '../core/auth/auth_service.dart';
import '../core/crypto_context.dart';
import '../widgets/koi_loader.dart';
import '../widgets/neo_button.dart';
import '../widgets/neo_input.dart';
import 'account_providers.dart';
import 'account_widgets.dart';

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

String accountErrorText(Object e) => switch (e) {
  AccountAuthException(error: AccountAuthError.emailInUse) =>
    'This email already has a KOI account. Sign in to it instead.',
  AccountAuthException(error: AccountAuthError.wrongCredentials) =>
    'That email and password do not match.',
  AccountAuthException(error: AccountAuthError.weakPassword) =>
    'Please choose a longer password (at least 6 characters).',
  AccountAuthException(error: AccountAuthError.invalidEmail) =>
    'Please enter a valid email address.',
  AccountAuthException(error: AccountAuthError.network) =>
    'You seem to be offline. Check your connection and try again.',
  AccountAuthException(error: AccountAuthError.tooManyRequests) =>
    'Too many attempts. Please wait a moment and try again.',
  AccountAuthException(error: AccountAuthError.notSupported) =>
    'Accounts are not available in this version of the app yet.',
  SaltFetchBlockedError() =>
    'Signed in, but your encryption details could not be loaded. Check your '
        'connection and try again.',
  _ => 'Something went wrong. Please try again.',
};

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
  String? _error;
  bool _offerSignIn = false;

  bool get _creating => _mode != AccountFormMode.signIn;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  String get _title => _creating ? 'Create your KOI account' : 'Sign in';

  String get _busyLabel => switch (_mode) {
    AccountFormMode.upgrade => 'Securing your history…',
    AccountFormMode.create => 'Creating your account…',
    AccountFormMode.signIn => 'Signing in…',
  };

  Future<void> _submit() async {
    final email = _email.text.trim();
    final password = _password.text;
    if (email.isEmpty || password.isEmpty) {
      setState(() => _error = 'Please enter your email and password.');
      return;
    }
    if (_creating && password != _confirm.text) {
      setState(() => _error = 'The passwords do not match.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _offerSignIn = false;
    });
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
      setState(() {
        _busy = false;
        _error = accountErrorText(e);
        _offerSignIn =
            anonymous &&
            e is AccountAuthException &&
            e.error == AccountAuthError.emailInUse;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_busy) {
      return Scaffold(body: KoiLoadingPage(label: _busyLabel));
    }
    final anonymous = ref.watch(authServiceProvider).isAnonymous;
    return KoiPage(
      back: true,
      title: _title,
      children: [
        if (_mode == AccountFormMode.upgrade)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Text(
              'Your chats and check-ins stay on this account. KOI encrypts '
              'them again with your new password.',
              style: koiBodyStyle(),
            ),
          ),
        if (_mode == AccountFormMode.signIn && anonymous)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Text(
              'Signing in to another account does not move this device\'s '
              'KOI history. You will be asked first.',
              style: koiBodyStyle(),
            ),
          ),
        NeoInput(
          key: const Key('account-email'),
          label: 'Email',
          controller: _email,
          keyboardType: TextInputType.emailAddress,
        ),
        const SizedBox(height: 14),
        NeoInput(
          key: const Key('account-password'),
          label: 'Password',
          controller: _password,
          obscureText: true,
        ),
        if (_creating) ...[
          const SizedBox(height: 14),
          NeoInput(
            key: const Key('account-confirm'),
            label: 'Confirm password',
            controller: _confirm,
            obscureText: true,
          ),
          const SizedBox(height: 16),
          Text(
            passwordWarning,
            key: const Key('password-warning'),
            style: koiMutedStyle(),
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: 16),
          KoiErrorText(_error!),
        ],
        const SizedBox(height: 24),
        NeoButton(
          key: const Key('account-submit'),
          fullWidth: true,
          onPressed: _submit,
          child: Text(_creating ? 'Create account' : 'Sign in'),
        ),
        if (_offerSignIn) ...[
          const SizedBox(height: 14),
          NeoButton(
            key: const Key('account-sign-in-instead'),
            variant: NeoButtonVariant.ghost,
            fullWidth: true,
            onPressed: () => setState(() {
              _mode = AccountFormMode.signIn;
              _error = null;
              _offerSignIn = false;
            }),
            child: const Text('Sign in instead'),
          ),
        ],
      ],
    );
  }
}
