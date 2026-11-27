import 'package:flutter/material.dart';

import 'dart:async';

import 'package:image_picker/image_picker.dart';

import '../../../app/app_scope.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/widgets/app_network_image.dart';
import '../../../core/widgets/app_states.dart';
import '../controllers/chat_detail_controller.dart';
import '../data/chat_repository.dart';
import '../data/chat_attachment_store.dart';
import '../models/chat_message.dart';
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

class _ChatDetailScreenState extends State<ChatDetailScreen>
    with WidgetsBindingObserver {
  ChatDetailController? _controller;
  ChatRepository? _repository;
  bool _invalidArguments = false;
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
        _convId =
            widget.conversationId ?? args['conversationId']?.toString() ?? '';
        _pName =
            widget.partnerName ?? args['partnerName'] as String? ?? 'Bạn học';
        _pAvatar =
            widget.partnerAvatarUrl ?? args['partnerAvatarUrl'] as String?;
        _isBlocked = widget.isBlocked || (args['isBlocked'] == true);
      } else {
        _convId = widget.conversationId ?? '';
        _pName = widget.partnerName ?? 'Bạn học';
        _pAvatar = widget.partnerAvatarUrl;
        _isBlocked = widget.isBlocked;
      }

      if (!RegExp(r'^[1-9][0-9]*$').hasMatch(_convId)) {
        _invalidArguments = true;
        return;
      }
      WidgetsBinding.instance.addObserver(this);
      final deps = AppScope.of(context);
      final userId = deps.session.tokens?.userId ?? 'anonymous';

      final repository = ChatRepository(
        api: deps.api,
        cache: deps.cache,
        mediaUploadService: deps.mediaUpload,
        privateStore: deps.drafts,
        wsUrl: Uri.parse(deps.config.normalizedBaseUrl)
            .resolve('ws')
            .replace(scheme: 'wss')
            .toString(),
      );
      _repository = repository;

      _controller = ChatDetailController(
        repository: repository,
        draftStore: deps.drafts,
        userId: userId,
        currentUserName: 'Tôi',
        conversationId: _convId,
        partnerName: _pName,
        partnerAvatarUrl: _pAvatar,
        isCurrent: () => repository.isActive,
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
    WidgetsBinding.instance.removeObserver(this);
    _scrollController.dispose();
    _controller?.dispose();
    _repository?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_controller?.reconnect());
    if (state == AppLifecycleState.paused) _controller?.pause();
  }

  Future<void> _pickAndSendImage() async {
    if (_controller?.canCompose != true) return;
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_rounded),
              title: const Text('Chọn từ thư viện ảnh'),
              onTap: () => Navigator.of(ctx).pop(ImageSource.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt_rounded),
              title: const Text('Chụp ảnh từ máy ảnh'),
              onTap: () => Navigator.of(ctx).pop(ImageSource.camera),
            ),
          ],
        ),
      ),
    );

    if (source == null || !mounted) return;

    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: source,
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 85,
      );
      if (picked != null && mounted) {
        final path = await ChatAttachmentStore.keep(
          picked.path,
          _controller!.userId,
          preserve: _controller!.messages
              .expand((m) => m.mediaUrls)
              .where((path) => !path.startsWith('https://'))
              .toSet(),
        );
        if (mounted) await _controller?.sendImageMessage(path);
      }
    } on AppFailure catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Không thể truy cập hình ảnh trên thiết bị.'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_invalidArguments) {
      return const Scaffold(
        body: SafeArea(
          child: AppErrorState(message: 'Hội thoại không hợp lệ.'),
        ),
      );
    }
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
                AppAvatar(imageUrl: _pAvatar, name: _pName, size: 36),
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
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          body: Column(
            children: [
              if (controller.errorMessage != null &&
                  controller.messages.isNotEmpty)
                MaterialBanner(
                  content: Text(controller.errorMessage!),
                  actions: [
                    TextButton(
                      onPressed: controller.isLoading
                          ? null
                          : controller.reconnect,
                      child: const Text('Thử lại'),
                    ),
                  ],
                ),
              if (controller.isDeleting) const LinearProgressIndicator(),
              // Khu vực danh sách tin nhắn
              Expanded(child: _buildMessagesArea(context, controller)),

              // Chỉ báo Typing ở góc dưới nếu đối phương đang soạn
              if (controller.isPartnerTyping)
                Container(
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 4,
                  ),
                  child: Row(
                    children: [
                      AppAvatar(imageUrl: _pAvatar, name: _pName, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '$_pName đang soạn tin nhắn…',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.outline,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

              // Nếu đang bị chặn thì hiện banner cảnh báo, ngược lại hiện thanh chat input
              if (_isBlocked || controller.accessDenied)
                Container(
                  width: double.infinity,
                  color: theme.colorScheme.errorContainer,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.block,
                        color: theme.colorScheme.onErrorContainer,
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _isBlocked
                              ? 'Bạn không thể gửi tin nhắn cho người này do đã bị chặn.'
                              : controller.errorMessage ?? 'Bạn không có quyền gửi tin nhắn trong cuộc trò chuyện này.',
                          style: TextStyle(
                            color: theme.colorScheme.onErrorContainer,
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
                  enabled: controller.canCompose,
                  initialText: controller.draftText,
                  onTextChanged: controller.onTextChanged,
                  onSendText: controller.sendTextMessage,
                  onPickImage: _pickAndSendImage,
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
          return Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(
              child: TextButton(
                onPressed: controller.isLoadingEarlier
                    ? null
                    : controller.loadEarlierMessages,
                child: Text(
                  controller.isLoadingEarlier ? 'Đang tải…' : 'Tải tin nhắn cũ',
                ),
              ),
            ),
          );
        }

        final message = controller.messages[index];
        return GestureDetector(
          onLongPress: message.messageId.isEmpty || controller.isDeleting
              ? null
              : () => _showMessageActions(message),
          child: ChatMessageBubble(
            message: message,
            currentUserId: controller.userId,
            onRetry: () => controller.retryFailedMessage(message),
          ),
        );
      },
    );
  }

  Future<void> _showMessageActions(ChatMessage message) async {
    final controller = _controller;
    if (controller == null || controller.isDeleting) return;
    final scope = await showModalBottomSheet<MessageDeleteScope>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('Xóa ở phía tôi'),
              onTap: () => Navigator.pop(context, MessageDeleteScope.me),
            ),
            if (message.isMine(controller.userId))
              ListTile(
                leading: const Icon(Icons.undo),
                title: const Text('Thu hồi với mọi người'),
                onTap: () =>
                    Navigator.pop(context, MessageDeleteScope.everyone),
              ),
          ],
        ),
      ),
    );
    if (!mounted || scope == null) return;
    final everyone = scope == MessageDeleteScope.everyone;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(everyone ? 'Thu hồi tin nhắn?' : 'Xóa tin nhắn?'),
        content: Text(
          everyone
              ? 'Tin nhắn sẽ được thu hồi với mọi người trong cuộc trò chuyện.'
              : 'Tin nhắn chỉ bị xóa ở phía bạn. Người còn lại vẫn có thể xem.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(everyone ? 'Thu hồi' : 'Xóa'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    final success = await controller.deleteMessage(message, scope);
    if (!mounted || !success) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          everyone ? 'Đã thu hồi tin nhắn.' : 'Đã xóa tin nhắn ở phía bạn.',
        ),
      ),
    );
  }
}
