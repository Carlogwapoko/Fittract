import 'package:flutter/material.dart';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:url_launcher/url_launcher.dart';

import '../store/store.dart';
import '../services/google_auth_service.dart';
import '../theme/app_palette.dart';
import 'forgot_password_screen.dart';
import '../widgets/shared_widgets.dart';

const _termsOfServiceUrl = 'https://fittrack-mydatabase.web.app/terms';
const _privacyPolicyUrl = 'https://fittrack-mydatabase.web.app/privacy';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});
  @override
  State<AuthScreen> createState() => _AuthState();
}

class _AuthState extends State<AuthScreen> {
  bool reg = false, agree = false;
  bool googleBusy = false, emailBusy = false;
  bool _obscurePw = true;
  int _googleAttempt = 0;
  String err = '';
  String notice = '';
  final googleAuth = GoogleAuthService();
  final nm = TextEditingController(),
      em = TextEditingController(),
      pw = TextEditingController();

  @override
  void dispose() {
    nm.dispose();
    em.dispose();
    pw.dispose();
    super.dispose();
  }

  String _messageFor(AuthResult result) => switch (result) {
    AuthResult.success => '',
    AuthResult.invalidInput =>
      reg
          ? 'Fill in all fields. Password needs 8+ characters.'
          : 'Enter email and password.',
    AuthResult.unknownEmail => 'No account found for that email.',
    AuthResult.wrongPassword => 'Wrong password.',
    AuthResult.duplicateEmail => 'An account with that email already exists.',
    AuthResult.storageError =>
      'Could not access saved account data. Please try again.',
    AuthResult.serviceError => 'Could not reach the account service. Check your connection and try again.',
  };

  Future<bool> _confirmCloudAccount(String message) async {
    if (!mounted) return false;
    return confirm(context, message, 'Create cloud account');
  }

  Future<bool> _confirmOfflineFallback(String message) async {
    if (!mounted) return false;
    return confirm(context, message, 'Continue offline');
  }

  Future<void> submit() async {
    if (emailBusy) return;
    if (!reg) {
      if (em.text.trim().isEmpty || pw.text.isEmpty) {
        return setState(() => err = 'Enter email and password.');
      }
    } else {
      if (nm.text.trim().isEmpty || em.text.trim().isEmpty) {
        return setState(() => err = 'Fill in all fields.');
      }
      if (pw.text.length < 8) {
        return setState(() => err = 'Password needs 8+ characters.');
      }
      if (!RegExp(r'\d').hasMatch(pw.text)) {
        return setState(
          () => err = 'Use 8+ characters with at least one number.',
        );
      }
      if (!agree) return setState(() => err = 'Please accept the terms.');
    }

    setState(() {
      emailBusy = true;
      err = '';
      notice = '';
    });
    // Paint the busy indicator before password derivation starts.
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    AuthResult result;
    try {
      result = reg
          ? await store.register(
              name: nm.text.trim(),
              email: em.text.trim(),
              password: pw.text,
            )
          : await store.login(
              email: em.text.trim(),
              password: pw.text,
              requestCloudAccountCreation: _confirmCloudAccount,
              requestOfflineFallback: _confirmOfflineFallback,
            );
    } catch (_) {
      // Storage or hashing threw: never leave the button stuck in its busy
      // state — reset it and surface a useful message instead.
      if (!mounted) return;
      setState(() {
        emailBusy = false;
        err = 'Something went wrong. Please try again.';
      });
      return;
    }
    if (!mounted) return;
    if (reg && result == AuthResult.success) {
      // Account creation succeeds but deliberately leaves the app signed
      // out: return to the Login form with a success note. The dashboard
      // stays reachable only through a separate, successful login.
      setState(() {
        emailBusy = false;
        reg = false;
        agree = false;
        pw.clear();
        notice = 'Account created successfully. Please log in.';
      });
      return;
    }
    setState(() {
      emailBusy = false;
      err = _messageFor(result);
    });
  }

  Future<void> signInWithGoogle() async {
    if (googleBusy) return;
    if (reg && !agree) {
      setState(() => err = 'Please accept the terms.');
      return;
    }
    final attempt = ++_googleAttempt;
    setState(() {
      googleBusy = true;
      err = '';
      notice = '';
    });
    try {
      final account = await googleAuth.signIn();
      if (!mounted || attempt != _googleAttempt) return;
      store.activateGoogleAccount(
        uid: account.uid,
        email: account.email,
        displayName: account.displayName.isEmpty
            ? nm.text
            : account.displayName,
        photoUrl: account.photoUrl,
      );
    } on GoogleSignInException catch (error) {
      _showGoogleError(googleAuthErrorMessage(error), attempt);
    } on FirebaseAuthException catch (error) {
      _showGoogleError(googleAuthErrorMessage(error), attempt);
    } on FirebaseException catch (error) {
      _showGoogleError(googleAuthErrorMessage(error), attempt);
    } on StateError catch (error) {
      _showGoogleError(googleAuthErrorMessage(error), attempt);
    } catch (error) {
      // Anything unexpected (plugin-channel failures, unsupported
      // platforms, …) gets the generic mapped fallback: a short, safe
      // message with no raw error details, tokens or configuration text.
      _showGoogleError(googleAuthErrorMessage(error), attempt);
    } finally {
      if (mounted && attempt == _googleAttempt) {
        setState(() => googleBusy = false);
      }
    }
  }

  void _showGoogleError(String message, int attempt) {
    if (attempt == _googleAttempt && message.isNotEmpty && mounted) {
      setState(() => err = message);
    }
  }

  Widget _visibilityToggle({
    required bool obscured,
    required VoidCallback onToggle,
  }) {
    final label = obscured ? 'Show password' : 'Hide password';
    return Semantics(
      button: true,
      label: label,
      child: IconButton(
        constraints: const BoxConstraints.tightFor(width: 44, height: 44),
        style: ButtonStyle(
          side: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.focused)
                ? BorderSide(color: _linkColor(context), width: 2)
                : BorderSide.none,
          ),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        icon: Icon(
          obscured ? Icons.visibility_outlined : Icons.visibility_off_outlined,
        ),
        tooltip: label,
        onPressed: onToggle,
      ),
    );
  }

  InputDecoration _inputDecoration(
    BuildContext context,
    String label, {
    Widget? suffixIcon,
  }) {
    final borderColor = Theme.of(context).colorScheme.outline;
    final borderWidth = appTokensOf(context).inputBorderWidth;
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: BorderSide(color: borderColor, width: borderWidth),
    );
    return InputDecoration(
      labelText: label,
      floatingLabelBehavior: FloatingLabelBehavior.auto,
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: Theme.of(context).colorScheme.surface,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: border,
      enabledBorder: border,
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(
          color: primaryOf(context),
          width: appTokensOf(context).focusedInputBorderWidth,
        ),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(
          color: Theme.of(context).colorScheme.error,
          width: borderWidth,
        ),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(
          color: Theme.of(context).colorScheme.error,
          width: appTokensOf(context).focusedInputBorderWidth,
        ),
      ),
    );
  }

  Color _linkColor(BuildContext context) => primaryOf(context);

  ButtonStyle _linkStyle(BuildContext context) => ButtonStyle(
    foregroundColor: WidgetStatePropertyAll(_linkColor(context)),
    textStyle: const WidgetStatePropertyAll(
      TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w500,
        decoration: TextDecoration.underline,
      ),
    ),
    padding: const WidgetStatePropertyAll(
      EdgeInsets.symmetric(horizontal: 8, vertical: 8),
    ),
    side: WidgetStateProperty.resolveWith(
      (states) => states.contains(WidgetState.focused)
          ? BorderSide(color: _linkColor(context), width: 2)
          : BorderSide.none,
    ),
    shape: WidgetStatePropertyAll(
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ),
  );

  ButtonStyle _toggleLinkStyle(BuildContext context) =>
      _linkStyle(context).copyWith(
        textStyle: const WidgetStatePropertyAll(
          TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w500,
            decoration: TextDecoration.none,
          ),
        ),
      );

  ButtonStyle _agreementLinkStyle(BuildContext context) =>
      _toggleLinkStyle(context).copyWith(
        textStyle: const WidgetStatePropertyAll(
          TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            decoration: TextDecoration.none,
          ),
        ),
        minimumSize: const WidgetStatePropertyAll(Size(0, 36)),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 2),
        ),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
      );

  Future<void> _openLegalLink(String url) async {
    try {
      final opened = await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.platformDefault,
      );
      if (!opened && mounted) {
        snack(context, 'Could not open the link. Please try again.');
      }
    } on PlatformException {
      if (mounted) snack(context, 'Could not open the link. Please try again.');
    } on Exception {
      if (mounted) snack(context, 'Could not open the link. Please try again.');
    }
  }

  int get _passwordStrength {
    final value = pw.text;
    if (value.isEmpty) return 0;
    var strength = 1;
    if (value.length >= 8) strength++;
    if (value.length >= 8 && RegExp(r'\d').hasMatch(value)) strength++;
    if (strength == 3 &&
        (RegExp(r'[A-Z]').hasMatch(value) ||
            RegExp(r'[^A-Za-z0-9]').hasMatch(value))) {
      strength++;
    }
    return strength;
  }

  Widget _passwordStrengthMeter(BuildContext context) {
    final strength = _passwordStrength;
    final colors = Theme.of(context).colorScheme;
    final color = switch (strength) {
      0 => colors.outlineVariant,
      1 => colors.error,
      2 => colors.tertiary,
      _ => colors.primary,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            for (var i = 0; i < 4; i++)
              Expanded(
                child: Container(
                  key: ValueKey('password-strength-$i'),
                  height: 4,
                  margin: EdgeInsets.only(right: i == 3 ? 0 : 6),
                  decoration: BoxDecoration(
                    color: i < strength
                        ? color
                        : Theme.of(context).colorScheme.outlineVariant,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          'Use 8+ characters with at least one number.',
          style: TextStyle(
            fontSize: 13,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _agreementRow(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.center,
    children: [
      SizedBox(
        width: 40,
        height: 40,
        child: Center(
          child: Checkbox(
            key: const ValueKey('terms-checkbox'),
            value: agree,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            onChanged: (value) => setState(() => agree = value ?? false),
          ),
        ),
      ),
      const SizedBox(width: 4),
      Expanded(
        child: Wrap(
          key: const ValueKey('terms-agreement-row'),
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            const Text('I agree to the ', style: TextStyle(fontSize: 14)),
            TextButton(
              key: const ValueKey('terms-agreement-link'),
              style: _agreementLinkStyle(context),
              onPressed: () => _openLegalLink(_termsOfServiceUrl),
              child: const Text('Terms of Service'),
            ),
            const Text(' and ', style: TextStyle(fontSize: 14)),
            TextButton(
              key: const ValueKey('privacy-agreement-link'),
              style: _agreementLinkStyle(context),
              onPressed: () => _openLegalLink(_privacyPolicyUrl),
              child: const Text('Privacy Policy'),
            ),
            const Text('.', style: TextStyle(fontSize: 14)),
          ],
        ),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight - 32),
            child: IntrinsicHeight(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    key: const ValueKey('login-hero-card'),
                    height: MediaQuery.sizeOf(context).width < 360 ? 160 : 150,
                    padding: const EdgeInsets.all(kGapXl),
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          appTokensOf(context).heroBackground,
                          appTokensOf(context).heroBackground,
                        ],
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '▲ FITTRACK',
                                style: TextStyle(
                                  color: appTokensOf(context).mintTint,
                                  fontSize: 19,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: .6,
                                ),
                              ),
                              const Spacer(),
                              Text(
                                reg
                                    ? 'Build a routine.\nFind your rhythm.'
                                    : 'Small steps.\nStronger you.',
                                key: const ValueKey('login-hero-slogan'),
                                style: TextStyle(
                                  color: appTokensOf(context).heroForeground,
                                  fontSize: switch (MediaQuery.sizeOf(context)
                                      .width) {
                                    < 360 => 14,
                                    < 400 => 15,
                                    _ => 24,
                                  },
                                  fontWeight: FontWeight.w800,
                                  height: 1.08,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: kGapSm),
                        SvgPicture.asset(
                          'assets/images/progress_rings.svg',
                          key: const ValueKey('login-progress-rings'),
                          width: 80,
                          height: 80,
                          semanticsLabel: 'Decorative progress rings',
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: kGapLg),
                  Text(
                    reg ? 'Create your account' : 'Welcome back',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: kGapSm),
                  if (reg) ...[
                    SizedBox(
                      height: 56,
                      child: TextField(
                        controller: nm,
                        textCapitalization: TextCapitalization.words,
                        textAlignVertical: TextAlignVertical.center,
                        decoration: _inputDecoration(context, 'Full name'),
                      ),
                    ),
                    const SizedBox(height: kGapMd),
                  ],
                  SizedBox(
                    height: 56,
                    child: TextField(
                      controller: em,
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.email],
                      textAlignVertical: TextAlignVertical.center,
                      decoration: _inputDecoration(context, 'Email address'),
                    ),
                  ),
                  const SizedBox(height: kGapMd),
                  SizedBox(
                    height: 56,
                    child: TextField(
                      controller: pw,
                      obscureText: _obscurePw,
                      autofillHints: reg
                          ? const [AutofillHints.newPassword]
                          : const [AutofillHints.password],
                      textAlignVertical: TextAlignVertical.center,
                      onChanged: reg ? (_) => setState(() {}) : null,
                      decoration: _inputDecoration(
                        context,
                        'Password',
                        suffixIcon: _visibilityToggle(
                          obscured: _obscurePw,
                          onToggle: () =>
                              setState(() => _obscurePw = !_obscurePw),
                        ),
                      ),
                    ),
                  ),
                  if (reg) ...[
                    const SizedBox(height: kGapSm),
                    _passwordStrengthMeter(context),
                    const SizedBox(height: kGapMd),
                    _agreementRow(context),
                  ] else ...[
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        style: _toggleLinkStyle(context),
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => ForgotPasswordScreen(
                              initialEmail: em.text.trim(),
                            ),
                          ),
                        ),
                        child: const Text('Forgot password?'),
                      ),
                    ),
                  ],
                  if (err.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Text(
                        err,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  if (notice.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Text(
                        notice,
                        style: TextStyle(color: _linkColor(context)),
                      ),
                    ),
                  const SizedBox(height: kGapSm),
                  SizedBox(
                    height: 52,
                    child: FilledButton(
                      onPressed: emailBusy || (reg && !agree) ? null : submit,
                      style: ButtonStyle(
                        backgroundColor: WidgetStateProperty.resolveWith(
                          (states) => states.contains(WidgetState.disabled)
                              ? Theme.of(context)
                                    .colorScheme
                                    .surfaceContainerHighest
                              : Theme.of(context).colorScheme.primary,
                        ),
                        foregroundColor: WidgetStateProperty.resolveWith(
                          (states) => states.contains(WidgetState.disabled)
                              ? Theme.of(context).colorScheme.onSurfaceVariant
                              : Theme.of(context).colorScheme.onPrimary,
                        ),
                        side: WidgetStateProperty.resolveWith(
                          (states) => states.contains(WidgetState.focused)
                              ? BorderSide(color: _linkColor(context), width: 3)
                              : BorderSide.none,
                        ),
                        shape: WidgetStatePropertyAll(
                          RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                      child: emailBusy
                          ? SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                            )
                          : Text(reg ? 'Create account' : 'Log in'),
                    ),
                  ),
                  if (!reg) ...[
                    const SizedBox(height: kGapMd),
                    Row(
                      children: [
                        Expanded(
                          child: Divider(
                            color: Theme.of(context).colorScheme.outlineVariant,
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Text(
                            'or',
                            style: TextStyle(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Divider(
                            color: Theme.of(context).colorScheme.outlineVariant,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: kGapMd),
                    SizedBox(
                      height: 52,
                      child: OutlinedButton(
                        onPressed: googleBusy ? null : signInWithGoogle,
                        style: ButtonStyle(
                          backgroundColor: WidgetStatePropertyAll(
                            Theme.of(context).colorScheme.surface,
                          ),
                          foregroundColor: WidgetStatePropertyAll(
                            Theme.of(context).colorScheme.onSurface,
                          ),
                          side: WidgetStateProperty.resolveWith(
                            (states) => BorderSide(
                              color: states.contains(WidgetState.focused)
                                  ? primaryOf(context)
                                  : Theme.of(context).colorScheme.outline,
                              width: states.contains(WidgetState.focused)
                                  ? appTokensOf(context).focusedInputBorderWidth
                                  : appTokensOf(context).inputBorderWidth,
                            ),
                          ),
                          shape: WidgetStatePropertyAll(
                            RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                        ),
                        child: googleBusy
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  SvgPicture.asset(
                                    'assets/images/google_g.svg',
                                    width: 20,
                                    height: 20,
                                    semanticsLabel: 'Google',
                                  ),
                                  const SizedBox(width: 12),
                                  Flexible(
                                    child: Text(
                                      'Continue with Google',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                      ),
                    ),
                  ],
                  const Spacer(),
                  Center(
                    child: TextButton(
                      style: _toggleLinkStyle(context),
                      onPressed: () => setState(() {
                        reg = !reg;
                        agree = false;
                        err = '';
                        notice = '';
                      }),
                      child: Text(
                        reg
                            ? 'Already a member? Log in'
                            : 'New here? Create an account',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
