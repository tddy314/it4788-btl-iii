import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'emoji_picker_sheet.dart';

class ChatInputBar extends StatefulWidget {
  const ChatInputBar({
    super.key,
    required this.initialText,
    required this.onTextChanged,
    required this.onSendText,
    required this.onPickImage,
    this.enabled = true,
  });

  final String initialText;
  final ValueChanged<String> onTextChanged;
  final Future<bool> Function(String) onSendText;
  final bool enabled;
  final VoidCallback onPickImage;

  @override
  State<ChatInputBar> createState() => _ChatInputBarState();
}

class _ChatInputBarState extends State<ChatInputBar> {
  late final TextEditingController _controller;
  bool _sending = false, _suppress = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialText);
    _controller.addListener(_onTextChanged);
  }

  void _onTextChanged() {
    if (!_suppress) widget.onTextChanged(_controller.text);
  }

  Future<void> _handleSend() async {
    final text = _controller.text;
    if (text.trim().isEmpty || !widget.enabled || _sending) return;
    setState(() => _sending = true);
    try {
      final accepted = await widget.onSendText(text);
      if (mounted && accepted && _controller.text == text) {
        _suppress = true;
        _controller.clear();
        _suppress = false;
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  void didUpdateWidget(covariant ChatInputBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.enabled && widget.enabled && _controller.text.isEmpty) {
      _suppress = true;
      _controller.text = widget.initialText;
      _suppress = false;
    }
  }

  void _insertEmote(String emote) {
    final current = _controller.text;
    final selection = _controller.selection;
    if (selection.isValid && selection.start >= 0) {
      final newText = current.replaceRange(
        selection.start,
        selection.end,
        emote,
      );
      _controller.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(
          offset: selection.start + emote.length,
        ),
      );
    } else {
      _controller.text = '$current$emote ';
      _controller.selection = TextSelection.collapsed(
        offset: _controller.text.length,
      );
    }
  }

  void _showEmotePicker(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return EmojiPickerSheet(onEmojiSelected: _insertEmote);
      },
    );
  }

  @override
  void dispose() {
    _controller.removeListener(_onTextChanged);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AbsorbPointer(
      absorbing: !widget.enabled || _sending,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          border: Border(
            top: BorderSide(
              color: theme.colorScheme.outlineVariant,
              width: 0.5,
            ),
          ),
        ),
        child: SafeArea(
          child: Row(
            children: [
              // Nút đính kèm ảnh
              IconButton(
                tooltip: 'Đính kèm ảnh',
                icon: Icon(
                  Icons.image_outlined,
                  color: theme.colorScheme.primary,
                ),
                onPressed: widget.onPickImage,
              ),

              // Nút chọn emote (Ký tự đặc biệt theo yêu cầu Slide 28)
              IconButton(
                tooltip: 'Biểu tượng cảm xúc',
                icon: Icon(
                  Icons.emoji_emotions_outlined,
                  color: theme.colorScheme.primary,
                ),
                onPressed: () => _showEmotePicker(context),
              ),

              // Ô nhập nội dung
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Focus(
                    onKeyEvent: (node, event) {
                      if (event is KeyDownEvent &&
                          event.logicalKey == LogicalKeyboardKey.enter &&
                          !HardwareKeyboard.instance.isShiftPressed) {
                        _handleSend();
                        return KeyEventResult.handled;
                      }
                      return KeyEventResult.ignored;
                    },
                    child: TextField(
                      controller: _controller,
                      maxLines: 4,
                      minLines: 1,
                      keyboardType: TextInputType.text,
                      textInputAction: TextInputAction.send,
                      textCapitalization: TextCapitalization.none,
                      decoration: const InputDecoration(
                        hintText: 'Nhập tin nhắn…',
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(vertical: 10),
                      ),
                      onSubmitted: (_) => _handleSend(),
                    ),
                  ),
                ),
              ),

              const SizedBox(width: 4),

              // Nút gửi
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: _controller,
                builder: (context, value, _) {
                  final canSend = value.text.trim().isNotEmpty;
                  return IconButton(
                    tooltip: 'Gửi',
                    icon: Icon(
                      Icons.send_rounded,
                      color: canSend
                          ? theme.colorScheme.primary
                          : theme.colorScheme.outline.withValues(alpha: 0.5),
                    ),
                    onPressed: canSend ? _handleSend : null,
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
