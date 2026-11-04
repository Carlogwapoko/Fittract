import 'package:flutter/material.dart';

import '../store/store.dart';
import '../widgets/shared_widgets.dart';

class ForgotPasswordScreen extends StatefulWidget {
  final String initialEmail;

  const ForgotPasswordScreen({super.key, this.initialEmail = ''});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  late final TextEditingController _email;
  bool _busy = false;
  String _error = '';
  String _notice = '';

  @override
  void initState() {
    super.initState();
    _email = TextEditingController(text: widget.initialEmail);
  }

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _sendResetLink() async {
    if (_busy) return;
    final email = _email.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      setState(() {
        _error = 'Enter a valid email address.';
        _notice = '';
      });
      return;
    }

    setState(() {
      _busy = true;
      _error = '';
      _notice = '';
    });
    final result = await store.sendPasswordReset(email);
    if (!mounted) return;

    setState(() {
      _busy = false;
      switch (result) {
        case AuthResult.success:
        case AuthResult.unknownEmail:
          _notice =
              'If an online account exists for this email, a password reset link has been sent. '
              'Check your inbox and spam folder. Accounts created offline on this device cannot receive reset emails.';
        case AuthResult.invalidInput:
          _error = 'Enter a valid email address.';
        case AuthResult.serviceError:
        case AuthResult.storageError:
        case AuthResult.wrongPassword:
        case AuthResult.duplicateEmail:
          _error = 'Could not reach the password reset service. Check your connection and try again.';
      }
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Find your account')),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(kGapLg),
        children: [
          const SizedBox(height: kGapXl),
          const Icon(Icons.lock_reset, size: 56),
          const SizedBox(height: kGapLg),
          const Text(
            'Reset your password',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: kGapSm),
          const Text(
            'Enter the email address for your account. If it has an online account, we’ll send a secure reset link to that email.',
          ),
          const SizedBox(height: kGapXl),
          TextField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
            decoration: const InputDecoration(labelText: 'Email address'),
            onSubmitted: (_) => _sendResetLink(),
          ),
          if (_error.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: kGapMd),
              child: Text(_error, style: const TextStyle(color: kRed)),
            ),
          if (_notice.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: kGapMd),
              child: Text(_notice, style: const TextStyle(color: kPri)),
            ),
          const SizedBox(height: kGapLg),
          if (_busy)
            const Center(child: CircularProgressIndicator())
          else
            btn('Send reset link', _sendResetLink),
        ],
      ),
    ),
  );
}
