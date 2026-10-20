import 'package:flutter/material.dart';

class AppTextField extends StatelessWidget {
  const AppTextField({
    super.key,
    required this.label,
    this.controller,
    this.validator,
    this.keyboardType,
    this.obscureText = false,
    this.enabled = true,
    this.maxLines = 1,
    this.textInputAction,
    this.onFieldSubmitted,
    this.autofillHints,
  });
  final String label;
  final TextEditingController? controller;
  final FormFieldValidator<String>? validator;
  final TextInputType? keyboardType;
  final bool obscureText;
  final bool enabled;
  final int maxLines;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onFieldSubmitted;
  final Iterable<String>? autofillHints;
  @override
  Widget build(BuildContext context) => TextFormField(
    controller: controller,
    decoration: InputDecoration(labelText: label),
    validator: validator,
    keyboardType: keyboardType,
    obscureText: obscureText,
    enabled: enabled,
    maxLines: obscureText ? 1 : maxLines,
    textInputAction: textInputAction,
    onFieldSubmitted: onFieldSubmitted,
    autofillHints: autofillHints,
    autocorrect: !obscureText,
    enableSuggestions: !obscureText,
  );
}
