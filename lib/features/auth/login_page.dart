import 'package:flutter/material.dart';

import '../../core/api/api_exception.dart';
import '../../config/api_config.dart';
import '../../state/app_scope.dart';
import '../../state/auth_state.dart';
import '../../ui/brand/logo.dart';
import '../../ui/kit/feedback.dart';
import '../../ui/kit/inputs.dart';
import '../../ui/kit/primitives.dart';
import '../../ui/theme.dart';

/// Port of `features/auth/pages/login-page.tsx` + `features/auth/services`.
///
/// The user service is never queued, so a failed sign-in fails loudly instead
/// of silently replaying when the connection returns.
class LoginPage extends StatefulWidget {
  const LoginPage({super.key, this.guestRouteLabel, this.onGuest});

  final String? guestRouteLabel;
  final VoidCallback? onGuest;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _username = TextEditingController();
  final _password = TextEditingController();
  bool _showPw = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  bool get _canSubmit =>
      _username.text.trim().isNotEmpty &&
      _password.text.isNotEmpty &&
      !_busy;

  Future<void> _submit() async {
    if (!_canSubmit) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final services = AppScope.read(context);
    final auth = services.auth;
    auth.setBusy(true);
    try {
      final response = await services.api.post(
        ServiceNames.users,
        '/auth/login',
        body: {
          'username': _username.text.trim(),
          'password': _password.text,
        },
        includeAuth: false,
      );
      if (response is! Map) {
        throw ApiException('Unexpected sign-in response');
      }
      final map = Map<String, dynamic>.from(response);
      final token = (map['access_token'] ?? map['token']) as String?;
      final rawUser = map['user'];
      if (token == null || token.isEmpty || rawUser is! Map) {
        throw ApiException('Sign-in response was missing the session');
      }
      final user = AppUser.fromJson(Map<String, dynamic>.from(rawUser));
      await auth.login(token, user);
      await services.onSessionChanged();
      if (mounted) setState(() {});
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      auth.setBusy(false);
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final t = context.texts;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 32, 24, 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: AutofillGroup(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const AppLogo(size: 46),
                    const SizedBox(height: 28),
                    Text('Sign in', style: t.headlineSmall),
                    const SizedBox(height: 6),
                    Text(
                      'Use the credentials issued by your administrator.',
                      style: t.bodyMedium?.copyWith(color: c.fgMuted),
                    ),
                    const SizedBox(height: 22),
                    if (_error != null) ...[
                      AppNotice(message: _error!, tone: AppTone.danger),
                      const SizedBox(height: 14),
                    ],
                    AppField(
                      label: 'Username',
                      required: true,
                      child: AppTextInput(
                        controller: _username,
                        hint: 'Enter your username',
                        icon: Icons.person_outline,
                        textInputAction: TextInputAction.next,
                        autofillHints: const [AutofillHints.username],
                        textCapitalization: TextCapitalization.none,
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    const SizedBox(height: 14),
                    AppField(
                      label: 'Password',
                      required: true,
                      child: AppTextInput(
                        controller: _password,
                        hint: 'Enter your password',
                        icon: Icons.lock_outline,
                        obscureText: !_showPw,
                        textInputAction: TextInputAction.done,
                        autofillHints: const [AutofillHints.password],
                        onChanged: (_) => setState(() {}),
                        onSubmitted: (_) => _submit(),
                        suffix: IconButton(
                          icon: Icon(
                            _showPw
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                            size: 17,
                          ),
                          onPressed: () =>
                              setState(() => _showPw = !_showPw),
                          tooltip: _showPw ? 'Hide password' : 'Show password',
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    AppButton(
                      label: 'Sign in',
                      variant: AppButtonVariant.primary,
                      size: AppButtonSize.lg,
                      expand: true,
                      icon: Icons.login,
                      loading: _busy,
                      onPressed: _canSubmit ? _submit : null,
                    ),
                    const SizedBox(height: 10),
                    AppButton(
                      label: widget.guestRouteLabel ?? 'Continue as guest',
                      variant: AppButtonVariant.ghost,
                      size: AppButtonSize.lg,
                      expand: true,
                      onPressed: widget.onGuest,
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Icon(Icons.wifi_off_rounded, size: 13, color: c.fgFaint),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Sign-in needs a connection. Everything after it works '
                            'offline and syncs when you are back in range.',
                            style: t.bodySmall
                                ?.copyWith(color: c.fgFaint, fontSize: context.fs(11.5)),
                          ),
                        ),
                      ],
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
}
