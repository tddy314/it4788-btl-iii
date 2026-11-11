import 'package:flutter/material.dart';

import '../../utils/chat_emote_converter.dart';

class ChatInputBar extends StatefulWidget {
  const ChatInputBar({
    super.key,
    required this.initialText,
    required this.onTextChanged,
    required this.onSendText,
    required this.onPickImage,
  });

  final String initialText;
  final ValueChanged<String> onTextChanged;
  final ValueChanged<String> onSendText;
  final VoidCallback onPickImage;

  @override
  State<ChatInputBar> createState() => _ChatInputBarState();
}

class _ChatInputBarState extends State<ChatInputBar> {
  late final TextEditingController _controller;
  bool _canSend = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialText);
    _canSend = _controller.text.trim().isNotEmpty;
    _controller.addListener(_onTextChanged);
  }

  void _onTextChanged() {
    final text = _controller.text;
    final canSend = text.trim().isNotEmpty;
    if (_canSend != canSend) {
      setState(() {
        _canSend = canSend;
      });
    }
    widget.onTextChanged(text);
  }

  void _handleSend() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    widget.onSendText(text);
    _controller.clear();
  }

  void _insertEmote(String emoteKey) {
    final current = _controller.text;
    final selection = _controller.selection;
    if (selection.isValid && selection.start >= 0) {
      final newText = current.replaceRange(
        selection.start,
        selection.end,
        emoteKey,
      );
      _controller.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(
          offset: selection.start + emoteKey.length,
        ),
      );
    } else {
      _controller.text = '$current$emoteKey ';
      _controller.selection = TextSelection.collapsed(
        offset: _controller.text.length,
      );
    }
  }

  void _showEmotePicker(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Biểu tượng cảm xúc (Ký tự đặc biệt)',
                  style: Theme.of(context).textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 10,
                  children: ChatEmoteConverter.emoteMap.entries.map((entry) {
                    return ActionChip(
                      avatar: Text(
                        entry.value,
                        style: const TextStyle(fontSize: 18),
                      ),
                      label: Text(
                        entry.key,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      onPressed: () {
                        _insertEmote(entry.key);
                        Navigator.of(context).pop();
                      },
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
        );
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

            // Ô nhập nội dung
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: TextField(
                  controller: _controller,
                  maxLines: 4,
                  minLines: 1,
                  textCapitalization: TextCapitalization.sentences,
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

            const SizedBox(width: 4),

            // Nút gửi
            IconButton(
              tooltip: 'Gửi',
              icon: Icon(
                Icons.send_rounded,
                color: _canSend
                    ? theme.colorScheme.primary
                    : theme.colorScheme.outline.withValues(alpha: 0.5),
              ),
              onPressed: _canSend ? _handleSend : null,
            ),
          ],
        ),
      ),
    );
  }
}
