import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/app_text_field.dart';
import 'auth_controller.dart';
import 'auth_validation.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.auth});
  final AuthController auth;
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _visible = false;
  void _submit() {
    if (!widget.auth.busy && _form.currentState!.validate()) {
      FocusScope.of(context).unfocus();
      widget.auth.login(_email.text, _password.text);
    }
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: ListenableBuilder(
        listenable: widget.auth,
        builder: (context, _) => LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: AutofillGroup(
                  child: Form(
                    key: _form,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SizedBox(height: 48),
                        Text(
                          'SQB',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.displayLarge
                              ?.copyWith(
                                color: AppColors.primary,
                                fontWeight: FontWeight.w800,
                              ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Cộng đồng học tập',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 40),
                        Text(
                          'Đăng nhập',
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Sử dụng tài khoản được giảng viên cấp để tham gia.',
                        ),
                        const SizedBox(height: 24),
                        AppTextField(
                          label: 'Email',
                          controller: _email,
                          keyboardType: TextInputType.emailAddress,
                          textInputAction: TextInputAction.next,
                          autofillHints: const [AutofillHints.username],
                          validator: AuthValidation.email,
                          enabled: !widget.auth.busy,
                        ),
                        const SizedBox(height: 16),
                        AppTextField(
                          label: 'Mật khẩu',
                          controller: _password,
                          obscureText: !_visible,
                          textInputAction: TextInputAction.done,
                          autofillHints: const [AutofillHints.password],
                          validator: AuthValidation.password,
                          enabled: !widget.auth.busy,
                          onFieldSubmitted: (_) => _submit(),
                        ),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton.icon(
                            onPressed: widget.auth.busy
                                ? null
                                : () => setState(() => _visible = !_visible),
                            icon: Icon(
                              _visible
                                  ? Icons.visibility_off_outlined
                                  : Icons.visibility_outlined,
                            ),
                            label: Text(
                              _visible ? 'Ẩn mật khẩu' : 'Hiện mật khẩu',
                            ),
                          ),
                        ),
                        if (widget.auth.message != null) ...[
                          Semantics(
                            liveRegion: true,
                            child: Text(
                              widget.auth.message!,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],
                        AppButton(
                          label: 'Đăng nhập',
                          isLoading: widget.auth.busy,
                          onPressed: _submit,
                        ),
                        const SizedBox(height: 24),
                        const Text(
                          'Nếu quên mật khẩu hoặc chưa có tài khoản, vui lòng liên hệ giảng viên.',
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
