import 'package:flutter/material.dart';

import '../../../app/app_scope.dart';
import '../../../core/widgets/app_network_image.dart';
import '../../../core/widgets/app_states.dart';
import '../controllers/chat_detail_controller.dart';
import '../data/chat_repository.dart';
import 'widgets/chat_input_bar.dart';
import 'widgets/chat_message_bubble.dart';

class ChatDetailScreen extends StatefulWidget {
  const ChatDetailScreen({
    super.key,
    this.conversationId,
    this.partnerName,
    this.partnerAvatarUrl,
    this.isBlocked = false,
  });

  final String? conversationId;
  final String? partnerName;
  final String? partnerAvatarUrl;
  final bool isBlocked;

  @override
  State<ChatDetailScreen> createState() => _ChatDetailScreenState();
}

class _ChatDetailScreenState extends State<ChatDetailScreen> {
  ChatDetailController? _controller;
  final _scrollController = ScrollController();
  bool _initialized = false;

  late String _convId;
  late String _pName;
  String? _pAvatar;
  bool _isBlocked = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _initialized = true;

      final args = ModalRoute.of(context)?.settings.arguments;
      if (args is Map<String, dynamic>) {
        _convId = widget.conversationId ?? args['conversationId']?.toString() ?? '';
        _pName = widget.partnerName ?? args['partnerName'] as String? ?? 'Bạn học';
        _pAvatar = widget.partnerAvatarUrl ?? args['partnerAvatarUrl'] as String?;
        _isBlocked = widget.isBlocked || (args['isBlocked'] == true);
      } else {
        _convId = widget.conversationId ?? '';
        _pName = widget.partnerName ?? 'Bạn học';
        _pAvatar = widget.partnerAvatarUrl;
        _isBlocked = widget.isBlocked;
      }

      final deps = AppScope.of(context);
      final userId = deps.session.tokens?.userId ?? 'anonymous';

      final repository = ChatRepository(
        api: deps.api,
        cache: deps.cache,
        mediaUploadService: deps.media,
      );

      _controller = ChatDetailController(
        repository: repository,
        draftStore: deps.drafts,
        userId: userId,
        currentUserName: 'Tôi',
        conversationId: _convId,
        partnerName: _pName,
        partnerAvatarUrl: _pAvatar,
      )..initialize();

      _scrollController.addListener(_onScroll);
    }
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      _controller?.loadEarlierMessages();
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _controller?.dispose();
    super.dispose();
  }

  void _pickAndSendImage(BuildContext context) {
    final textController = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Gửi hình ảnh'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Chọn ảnh từ thư viện thiết bị hoặc nhập đường dẫn tệp ảnh (tối đa 4MB):',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: textController,
              decoration: const InputDecoration(
                hintText: 'C:\\path\\to\\image.png hoặc /sdcard/image.jpg',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () {
              final path = textController.text.trim();
              if (path.isNotEmpty) {
                Navigator.of(ctx).pop();
                _controller?.sendImageMessage(path);
              }
            },
            child: const Text('Gửi ảnh'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null) {
      return const Scaffold(
        body: SafeArea(child: AppLoadingState(message: 'Đang mở hội thoại…')),
      );
    }

    final theme = Theme.of(context);

    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        return Scaffold(
          appBar: AppBar(
            titleSpacing: 0,
            title: Row(
              children: [
                AppAvatar(
                  imageUrl: _pAvatar,
                  name: _pName,
                  size: 36,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _pName,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (controller.isPartnerTyping)
                        Text(
                          'Đang soạn tin…',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.primary,
                            fontStyle: FontStyle.italic,
                          ),
                        )
                      else
                        Text(
                          'Trực tuyến',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: Colors.green,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          body: Column(
            children: [
              // Khu vực danh sách tin nhắn
              Expanded(child: _buildMessagesArea(context, controller)),

              // Chỉ báo Typing ở góc dưới nếu đối phương đang soạn
              if (controller.isPartnerTyping)
                Container(
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: Row(
                    children: [
                      AppAvatar(
                        imageUrl: _pAvatar,
                        name: _pName,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '$_pName đang soạn tin nhắn…',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.outline,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                  ),
                ),

              // Nếu đang bị chặn thì hiện banner cảnh báo, ngược lại hiện thanh chat input
              if (_isBlocked)
                Container(
                  width: double.infinity,
                  color: Colors.amber.shade100,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: Row(
                    children: [
                      const Icon(Icons.block, color: Colors.red, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Bạn không thể gửi tin nhắn cho người này do đã bị chặn.',
                          style: TextStyle(
                            color: Colors.red.shade900,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              else
                ChatInputBar(
                  initialText: controller.draftText,
                  onTextChanged: controller.onTextChanged,
                  onSendText: controller.sendTextMessage,
                  onPickImage: () => _pickAndSendImage(context),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMessagesArea(
    BuildContext context,
    ChatDetailController controller,
  ) {
    if (controller.isLoading && controller.messages.isEmpty) {
      return const AppLoadingState(message: 'Đang tải tin nhắn…');
    }

    if (controller.errorMessage != null && controller.messages.isEmpty) {
      return AppErrorState(
        message: controller.errorMessage!,
        onRetry: () => controller.fetchFirstPage(),
      );
    }

    if (controller.messages.isEmpty) {
      return const AppEmptyState(
        icon: Icons.chat_bubble_outline_rounded,
        title: 'Chưa có tin nhắn',
        message: 'Hãy gửi lời chào để bắt đầu cuộc trò chuyện!',
      );
    }

    return ListView.builder(
      controller: _scrollController,
      reverse: true,
      itemCount: controller.messages.length + (controller.hasNext ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == controller.messages.length) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }

        final message = controller.messages[index];
        return ChatMessageBubble(
          message: message,
          currentUserId: controller.partnerName == _pName ? 'my_id' : '',
          onRetry: () => controller.retryFailedMessage(message),
        );
      },
    );
  }
}
