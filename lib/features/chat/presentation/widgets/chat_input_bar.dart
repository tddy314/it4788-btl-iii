import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'emoji_picker_sheet.dart';
import 'gif_picker_sheet.dart';

class ChatInputBar extends StatefulWidget {
  const ChatInputBar({
    super.key,
    required this.initialText,
    required this.onTextChanged,
    required this.onSendText,
    required this.onPickImage,
    required this.onSendGif,
  });

  final String initialText;
  final ValueChanged<String> onTextChanged;
  final ValueChanged<String> onSendText;
  final VoidCallback onPickImage;
  final ValueChanged<String> onSendGif;

  @override
  State<ChatInputBar> createState() => _ChatInputBarState();
}

class _ChatInputBarState extends State<ChatInputBar> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialText);
    _controller.addListener(_onTextChanged);
  }

  void _onTextChanged() {
    widget.onTextChanged(_controller.text);
  }

  void _handleSend() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    widget.onSendText(text);
    _controller.clear();
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

  void _showGifPicker(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return GifPickerSheet(onGifSelected: widget.onSendGif);
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

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          top: BorderSide(color: theme.colorScheme.outlineVariant, width: 0.5),
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

            // Nút chọn GIF động
            IconButton(
              tooltip: 'Gửi GIF',
              icon: Icon(
                Icons.gif_box_outlined,
                color: theme.colorScheme.primary,
                size: 26,
              ),
              onPressed: () => _showGifPicker(context),
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
    );
  }
}
