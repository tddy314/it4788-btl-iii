import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../core/errors/app_failure.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/app_text_field.dart';
import '../auth/auth_repository.dart';
import '../auth/auth_validation.dart';

class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key, required this.repository});
  final AuthRepository repository;
  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _form = GlobalKey<FormState>();
  final _old = TextEditingController();
  final _next = TextEditingController();
  final _confirm = TextEditingController();
  final _cancel = CancelToken();
  bool _busy = false;
  bool _visible = false;
  String? _error;
  Future<void> _submit() async {
    if (_busy || !_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.repository.changePassword(
        _old.text,
        _next.text,
        cancelToken: _cancel,
      );
      if (!mounted) return;
      _old.clear();
      _next.clear();
      _confirm.clear();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Đổi mật khẩu thành công.')));
      Navigator.of(context).pop();
    } on AppFailure catch (error) {
      if (!mounted) return;
      setState(
        () => _error = error.kind == FailureKind.timeout
            ? 'Chưa xác nhận được kết quả đổi mật khẩu. Không gửi lại tự động; vui lòng kiểm tra trước khi thử lại.'
            : error.message,
      );
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Không thể đổi mật khẩu. Vui lòng thử lại.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _cancel.cancel();
    _old.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Đổi mật khẩu')),
    body: SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Form(
              key: _form,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Nhập mật khẩu hiện tại và xác nhận mật khẩu mới.',
                  ),
                  const SizedBox(height: 24),
                  AppTextField(
                    label: 'Mật khẩu hiện tại',
                    controller: _old,
                    obscureText: !_visible,
                    enabled: !_busy,
                    validator: AuthValidation.password,
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: 16),
                  AppTextField(
                    label: 'Mật khẩu mới',
                    controller: _next,
                    obscureText: !_visible,
                    enabled: !_busy,
                    validator: (value) =>
                        AuthValidation.newPassword(value, _old.text),
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: 16),
                  AppTextField(
                    label: 'Nhập lại mật khẩu mới',
                    controller: _confirm,
                    obscureText: !_visible,
                    enabled: !_busy,
                    validator: (value) =>
                        AuthValidation.password(value) ??
                        (value == _next.text
                            ? null
                            : 'Mật khẩu xác nhận không khớp.'),
                    textInputAction: TextInputAction.done,
                    onFieldSubmitted: (_) => _submit(),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: _busy
                          ? null
                          : () => setState(() => _visible = !_visible),
                      child: Text(_visible ? 'Ẩn mật khẩu' : 'Hiện mật khẩu'),
                    ),
                  ),
                  if (_error != null) ...[
                    Semantics(
                      liveRegion: true,
                      child: Text(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  AppButton(
                    label: 'Lưu mật khẩu',
                    isLoading: _busy,
                    onPressed: _submit,
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
