import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import '../widgets/auth_widgets.dart';
import '../widgets/mobile_page_shell.dart';

class ForgotPasswordPage extends StatefulWidget {
  const ForgotPasswordPage({super.key});

  @override
  State<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends State<ForgotPasswordPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailKey = GlobalKey<FormFieldState<String>>();
  final _emailController = TextEditingController();
  final _codeController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  Timer? _timer;
  DateTime? _resendAt;
  int _secondsLeft = 0;
  bool _sending = false;
  bool _resetting = false;
  String? _requestedEmail;
  String? _notice;

  bool get _busy => _sending || _resetting;
  String get _email => _emailController.text.trim().toLowerCase();

  @override
  void dispose() {
    _timer?.cancel();
    _emailController.dispose();
    _codeController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  String? _validateEmail(String? value) {
    final email = (value ?? '').trim();
    return email.length <= 254 &&
            RegExp(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$')
                .hasMatch(email)
        ? null
        : 'Enter a valid email address.';
  }

  String? _validateCode(String? value) {
    return RegExp(r'^\d{6}$').hasMatch((value ?? '').trim())
        ? null
        : 'Enter the 6-digit code.';
  }

  String? _validatePassword(String? value) {
    if (value == null || value.length < 6) return 'Use at least 6 characters.';
    if (utf8.encode(value).length > 72) {
      return 'Password is too long (maximum 72 UTF-8 bytes).';
    }
    return null;
  }

  void _showError(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _startCountdown(int seconds) {
    _timer?.cancel();
    _resendAt = DateTime.now().add(Duration(seconds: seconds));
    setState(() => _secondsLeft = seconds);
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      final remaining =
          (_resendAt!.difference(DateTime.now()).inMilliseconds / 1000).ceil();
      setState(() => _secondsLeft = remaining > 0 ? remaining : 0);
      if (_secondsLeft == 0) timer.cancel();
    });
  }

  Future<void> _sendCode() async {
    if (_busy || _secondsLeft > 0) return;
    if (!(_emailKey.currentState?.validate() ?? false)) return;
    final target = _email;
    setState(() {
      _sending = true;
      _notice = null;
    });
    try {
      final response = await AuthService.requestPasswordResetCode(target);
      if (!mounted) return;
      setState(() {
        _requestedEmail = target;
        _codeController.clear();
        _notice = response['message']?.toString() ??
            'If this email has a password account, check your inbox and spam folder.';
      });
      _startCountdown((response['retryAfterSeconds'] as num?)?.toInt() ?? 60);
    } on AuthException catch (error) {
      if (mounted) _showError(error.message);
    } catch (_) {
      if (mounted) _showError('Unable to send the code. Please try again.');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _resetPassword() async {
    if (_busy) return;
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_requestedEmail != _email) {
      _showError('Request a code for this email address first.');
      return;
    }
    setState(() => _resetting = true);
    try {
      await AuthService.resetPassword(
        email: _email,
        code: _codeController.text,
        newPassword: _newPasswordController.text,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Password reset successfully. Sign in with your new password.',
          ),
        ),
      );
      Navigator.of(context).pop();
    } on AuthException catch (error) {
      if (mounted) _showError(error.message);
    } catch (_) {
      if (mounted) {
        _showError('Unable to reset your password. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _resetting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return MobilePageShell(
      child: Column(
        children: [
          const GlobalVillageHeader(showBackButton: true),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(22, 28, 22, 28),
              child: Form(
                key: _formKey,
                child: Column(
                  children: [
                    const AuthPageTitle(
                      title: 'Forgot Password',
                      subtitle: 'Verify your email to reset your password.',
                    ),
                    const SizedBox(height: 24),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8F8F8),
                        border: Border.all(color: AppTheme.border),
                        borderRadius: BorderRadius.circular(7),
                      ),
                      child: const Text(
                        'Use the email address you registered with. Codes expire in 10 minutes. '
                        'Only the newest code works. If you signed up only with Google, use Google sign-in.',
                        style: TextStyle(
                          color: AppTheme.muted,
                          fontSize: 12.5,
                          height: 1.4,
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    const FieldLabel('Email Address'),
                    TextFormField(
                      key: _emailKey,
                      controller: _emailController,
                      readOnly: _busy,
                      validator: _validateEmail,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      autofillHints: const [AutofillHints.email],
                      onChanged: (_) {
                        if (_requestedEmail != null &&
                            _email != _requestedEmail) {
                          setState(() {
                            _requestedEmail = null;
                            _notice = null;
                            _codeController.clear();
                          });
                        }
                      },
                      decoration: const InputDecoration(
                        hintText: 'Enter your registered email',
                      ),
                    ),
                    const SizedBox(height: 18),
                    OutlineActionButton(
                      label: _sending
                          ? 'Sending...'
                          : _secondsLeft > 0
                              ? 'Resend in ${_secondsLeft}s'
                              : 'Send Code',
                      onPressed: _busy || _secondsLeft > 0 ? null : _sendCode,
                    ),
                    if (_notice != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        _notice!,
                        style: const TextStyle(
                          color: AppTheme.muted,
                          fontSize: 12.5,
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                    const FieldLabel('Verification Code'),
                    TextFormField(
                      controller: _codeController,
                      readOnly: _busy,
                      validator: _validateCode,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      autofillHints: const [AutofillHints.oneTimeCode],
                      maxLength: 6,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        hintText: 'Enter the 6-digit code',
                        counterText: '',
                      ),
                    ),
                    const SizedBox(height: 20),
                    const FieldLabel('New Password'),
                    PasswordField(
                      controller: _newPasswordController,
                      hintText: 'Create a new password',
                      validator: _validatePassword,
                    ),
                    const SizedBox(height: 20),
                    const FieldLabel('Confirm Password'),
                    PasswordField(
                      controller: _confirmPasswordController,
                      hintText: 'Confirm your new password',
                      validator: (value) =>
                          value == _newPasswordController.text &&
                                  (value?.isNotEmpty ?? false)
                              ? null
                              : 'Passwords do not match.',
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) => _resetPassword(),
                    ),
                    const SizedBox(height: 24),
                    PrimaryButton(
                      label: 'Reset Password',
                      onPressed: _busy ? null : _resetPassword,
                      isBusy: _resetting,
                    ),
                    const SizedBox(height: 6),
                    UnderlineTextButton(
                      label: 'Back to Login',
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
