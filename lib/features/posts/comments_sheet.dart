import 'package:flutter/material.dart';

import 'comments_screen.dart';

/// A non-modal sheet keeps the exposed part of the post scrollable.
PersistentBottomSheetController showPostComments(
  BuildContext context, {
  required int postId,
}) {
  late PersistentBottomSheetController sheet;
  sheet = Scaffold.of(context).showBottomSheet(
    (_) => DraggableScrollableSheet(
      initialChildSize: .62,
      minChildSize: .28,
      maxChildSize: .88,
      expand: false,
      shouldCloseOnMinExtent: false,
      builder: (_, scroll) => CommentsScreen(
        postId: postId,
        embedded: true,
        scrollController: scroll,
        onClose: () => sheet.close(),
      ),
    ),
    showDragHandle: true,
    enableDrag: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    clipBehavior: Clip.antiAlias,
  );
  return sheet;
}
