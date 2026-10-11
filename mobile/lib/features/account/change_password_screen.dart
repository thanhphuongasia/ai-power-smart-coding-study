/// Màn đổi mật khẩu: kiểm tra phía client (độ dài, xác nhận khớp), rồi gọi
/// server. Thành công → báo và đóng màn.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/api_client.dart';
import '../../data/auth_repository.dart';

const _minLength = 10;

class ChangePasswordScreen extends ConsumerStatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  ConsumerState<ChangePasswordScreen> createState() =>
      _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends ConsumerState<ChangePasswordScreen> {
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  /// Trả về thông báo lỗi tiếng Việt, hoặc null nếu input hợp lệ.
  static String? _validate(String current, String next, String confirm) {
    if (current.isEmpty) return 'Nhập mật khẩu hiện tại.';
    if (next.length < _minLength) {
      return 'Mật khẩu mới phải có ít nhất $_minLength ký tự.';
    }
    if (next != confirm) return 'Xác nhận mật khẩu không khớp.';
    return null;
  }

  static String _message(AuthErrorKind kind) => switch (kind) {
    AuthErrorKind.wrongPassword => 'Mật khẩu hiện tại không đúng.',
    AuthErrorKind.weakPassword =>
      'Mật khẩu mới chưa đạt yêu cầu. Hãy chọn mật khẩu khác.',
    AuthErrorKind.tooManyAttempts =>
      'Thử quá nhiều lần. Hãy đợi một lúc rồi thử lại.',
    AuthErrorKind.sessionExpired => 'Phiên đã hết hạn, hãy đăng nhập lại.',
    AuthErrorKind.invalidCredentials || AuthErrorKind.network =>
      'Không kết nối được máy chủ. Kiểm tra mạng rồi thử lại.',
  };

  Future<void> _submit() async {
    if (_busy) return;
    final current = _current.text;
    final next = _next.text;
    final validation = _validate(current, next, _confirm.text);
    if (validation != null) {
      setState(() => _error = validation);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(authControllerProvider.notifier)
          .changePassword(current, next);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Đã đổi mật khẩu.')));
      context.pop();
    } on AuthError catch (e) {
      if (mounted) setState(() => _error = _message(e.kind));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const Key('change-password-screen'),
      appBar: AppBar(title: const Text('Đổi mật khẩu')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  key: const Key('cp-current'),
                  controller: _current,
                  obscureText: true,
                  autofillHints: const [AutofillHints.password],
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Mật khẩu hiện tại',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const Key('cp-new'),
                  controller: _next,
                  obscureText: true,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    labelText: 'Mật khẩu mới',
                    helperText: 'Ít nhất $_minLength ký tự',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const Key('cp-confirm'),
                  controller: _confirm,
                  obscureText: true,
                  onSubmitted: (_) => _submit(),
                  decoration: const InputDecoration(
                    labelText: 'Nhập lại mật khẩu mới',
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    key: const Key('cp-error'),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                FilledButton(
                  key: const Key('cp-submit'),
                  onPressed: _busy ? null : _submit,
                  child: _busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Đổi mật khẩu'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
