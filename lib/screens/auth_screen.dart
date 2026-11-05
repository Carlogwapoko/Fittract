import 'package:flutter/material.dart';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:url_launcher/url_launcher.dart';

import '../store/store.dart';
import '../services/google_auth_service.dart';
import 'forgot_password_screen.dart';
import '../widgets/shared_widgets.dart';

const _termsOfServiceUrl = 'https://fittrack-mydatabase.web.app/terms';
const _privacyPolicyUrl = 'https://fittrack-mydatabase.web.app/privacy';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});
  @override
  State<AuthScreen> createState() => _AuthState();
}

class _AuthState extends State<AuthScreen> with WidgetsBindingObserver {
  bool reg = false, agree = false;
  bool googleBusy = false, emailBusy = false;
  bool _googleAuthWasBackgrounded = false;
  bool _obscurePw = true;
  int _googleAttempt = 0;
  String err = '';
  String notice = '';
  final googleAuth = GoogleAuthService();
  final nm = TextEditingController(),
      em = TextEditingController(),
      pw = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    nm.dispose();
    em.dispose();
    pw.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      _googleAuthWasBackgrounded = true;
      return;
    }

    if (state == AppLifecycleState.resumed && _googleAuthWasBackgrounded) {
      _googleAuthWasBackgrounded = false;
      if (googleBusy && mounted) {
        setState(() => googleBusy = false);
      }
    }
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
      final credential = await googleAuth.signIn();
      if (!mounted || attempt != _googleAttempt) return;
      final user = credential.user;
      if (user == null) {
        throw StateError('Google sign-in did not return an account.');
      }
      store.activateGoogleAccount(
        uid: user.uid,
        email: user.email ?? '',
        displayName: user.displayName ?? nm.text,
        photoUrl: user.photoURL,
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
    final dark = Theme.of(context).brightness == Brightness.dark;
    const borderColor = Color(0xFF9DB5B1);
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: const BorderSide(color: borderColor, width: 1.5),
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
          color: dark ? kMint : const Color(0xFF005A50),
          width: 3,
        ),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: kRed, width: 1.5),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: kRed, width: 3),
      ),
    );
  }

  Color _linkColor(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
      ? const Color(0xFF8FE3D0)
      : const Color(0xFF005A50);

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

  ButtonStyle _agreementLinkStyle(BuildContext context) =>
      _linkStyle(context).copyWith(
        textStyle: const WidgetStatePropertyAll(
          TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w500,
            decoration: TextDecoration.none,
          ),
        ),
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
    final color = switch (strength) {
      0 => Theme.of(context).colorScheme.outlineVariant,
      1 => const Color(0xFFCA5757),
      2 => const Color(0xFFE6A23C),
      3 => const Color(0xFF8DAE45),
      _ => const Color(0xFF16806F),
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
        width: 44,
        height: 44,
        child: Center(
          child: Transform.scale(
            scale: 1.2,
            child: Checkbox(
              key: const ValueKey('terms-checkbox'),
              value: agree,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              onChanged: (value) => setState(() => agree = value ?? false),
            ),
          ),
        ),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: InkWell(
          key: const ValueKey('terms-agreement-row'),
          onTap: () => setState(() => agree = !agree),
          borderRadius: BorderRadius.circular(8),
          focusColor: _linkColor(context).withValues(alpha: .22),
          child: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 6),
                child: Text('I agree to the ', style: TextStyle(fontSize: 14)),
              ),
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
      ),
    ],
  );

  Widget _policyLinks(BuildContext context) => Wrap(
    alignment: WrapAlignment.center,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      TextButton(
        style: _linkStyle(context),
        onPressed: () => _openLegalLink(_termsOfServiceUrl),
        child: const Text('Terms of Service'),
      ),
      Text(
        '·',
        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
      ),
      TextButton(
        style: _linkStyle(context),
        onPressed: () => _openLegalLink(_privacyPolicyUrl),
        child: const Text('Privacy Policy'),
      ),
    ],
  );

  ThemeData _authTheme(BuildContext context) {
    final dark =
        store.on('dark') ||
        MediaQuery.platformBrightnessOf(context) == Brightness.dark;
    final brightness = dark ? Brightness.dark : Brightness.light;
    final scheme = ColorScheme.fromSeed(seedColor: kPri, brightness: brightness)
        .copyWith(
          primary: dark ? kMint : kPri,
          onPrimary: dark ? kInk : Colors.white,
          secondary: dark ? kMint : kDk,
          surface: dark ? kSurfaceDark : Colors.white,
          onSurface: dark ? const Color(0xFFE4EFEC) : kInk,
          outlineVariant: dark ? kLineDark : kLn,
        );
    return Theme.of(context).copyWith(
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: dark ? kBgDark : kBg,
    );
  }

  @override
  Widget build(BuildContext context) => Theme(
    data: _authTheme(context),
    child: Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: constraints.maxHeight - 32,
              ),
              child: IntrinsicHeight(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      height: 150,
                      padding: const EdgeInsets.all(kGapXl),
                      clipBehavior: Clip.antiAlias,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Color(0xFF2C5A5A), kDk],
                        ),
                      ),
                      child: Stack(
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                '▲ FITTRACK',
                                style: TextStyle(
                                  color: kMint,
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
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 27,
                                  fontWeight: FontWeight.w800,
                                  height: 1.08,
                                ),
                              ),
                            ],
                          ),
                          Positioned(
                            right: -14,
                            bottom: -27,
                            child: IgnorePointer(
                              child: SvgPicture.asset(
                                'assets/images/progress_rings.svg',
                                width: 112,
                                height: 112,
                                semanticsLabel: 'Decorative progress rings',
                              ),
                            ),
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
                          style: _linkStyle(context),
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
                        child: Text(err, style: const TextStyle(color: kRed)),
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
                                ? const Color(0xFFB7C0BE)
                                : Theme.of(context).colorScheme.primary,
                          ),
                          foregroundColor: WidgetStateProperty.resolveWith(
                            (states) => states.contains(WidgetState.disabled)
                                ? const Color(0xFF485552)
                                : Theme.of(context).colorScheme.onPrimary,
                          ),
                          side: WidgetStateProperty.resolveWith(
                            (states) => states.contains(WidgetState.focused)
                                ? BorderSide(
                                    color: _linkColor(context),
                                    width: 3,
                                  )
                                : BorderSide.none,
                          ),
                          shape: WidgetStatePropertyAll(
                            RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                        ),
                        child: emailBusy
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : Text(reg ? 'Create account' : 'Log in'),
                      ),
                    ),
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
                        onPressed: googleBusy || (reg && !agree)
                            ? null
                            : signInWithGoogle,
                        style: ButtonStyle(
                          backgroundColor: const WidgetStatePropertyAll(
                            Colors.white,
                          ),
                          foregroundColor: const WidgetStatePropertyAll(
                            Color(0xFF202124),
                          ),
                          side: WidgetStateProperty.resolveWith(
                            (states) => BorderSide(
                              color: states.contains(WidgetState.focused)
                                  ? const Color(0xFF005A50)
                                  : const Color(0xFF9DB5B1),
                              width: states.contains(WidgetState.focused)
                                  ? 3
                                  : 1.5,
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
                                  Text(
                                    reg
                                        ? 'Sign up with Google'
                                        : 'Continue with Google',
                                    style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                      ),
                    ),
                    const Spacer(),
                    const SizedBox(height: kGapLg),
                    _policyLinks(context),
                    Center(
                      child: TextButton(
                        style: _linkStyle(context),
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
    ),
  );
}
