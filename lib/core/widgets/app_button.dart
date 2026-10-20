import 'package:flutter/material.dart';

class AppButton extends StatelessWidget {
  const AppButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.isLoading = false,
    this.icon,
  });
  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;
  final IconData? icon;
  @override
  Widget build(BuildContext context) => FilledButton(
    onPressed: isLoading ? null : onPressed,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (isLoading) ...[
          const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 8),
        ] else if (icon != null) ...[
          Icon(icon),
          const SizedBox(width: 8),
        ],
        Flexible(child: Text(label, textAlign: TextAlign.center)),
      ],
    ),
  );
}
