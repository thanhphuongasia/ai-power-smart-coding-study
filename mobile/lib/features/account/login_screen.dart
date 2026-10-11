import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/api_client.dart';
import '../../data/auth_repository.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  static String _message(AuthErrorKind kind) => switch (kind) {
    AuthErrorKind.invalidCredentials => 'Email hoặc mật khẩu không đúng.',
    AuthErrorKind.tooManyAttempts =>
      'Thử quá nhiều lần. Vui lòng đợi một lúc rồi thử lại.',
    AuthErrorKind.wrongPassword ||
    AuthErrorKind.weakPassword ||
    AuthErrorKind.sessionExpired ||
    AuthErrorKind.network =>
      'Không kết nối được máy chủ. Kiểm tra mạng rồi thử lại.',
  };

  Future<void> _submit() async {
    if (_busy) return;
    final email = _email.text.trim();
    if (email.isEmpty || _password.text.isEmpty) {
      setState(() => _error = 'Nhập email và mật khẩu');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(authControllerProvider.notifier)
          .login(email, _password.text);
      // Thành công: AuthGate tự chuyển sang app, màn này bị gỡ.
    } on AuthError catch (e) {
      if (mounted) setState(() => _error = _message(e.kind));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const Key('login-screen'),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Đăng nhập',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 24),
                TextField(
                  key: const Key('login-email'),
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.email],
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(labelText: 'Email'),
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const Key('login-password'),
                  controller: _password,
                  obscureText: true,
                  autofillHints: const [AutofillHints.password],
                  onSubmitted: (_) => _submit(),
                  decoration: const InputDecoration(labelText: 'Mật khẩu'),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    key: const Key('login-error'),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                FilledButton(
                  key: const Key('login-submit'),
                  onPressed: _busy ? null : _submit,
                  child: _busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Đăng nhập'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
