import '../../core/storage/draft_store.dart';
import 'post_models.dart';

/// Android's picker result is global to the installation. Store its owner
/// separately from the account-scoped draft, so a late result cannot enter B's
/// draft after A logged out. Only routing metadata lives in the owner record.
class PickerRecovery {
  PickerRecovery(this.drafts);
  final DraftStore drafts;
  static const _ownerKey = '__post_picker_owner__';
  Future<String> begin(String user, Post? original) async {
    final nonce = DateTime.now().microsecondsSinceEpoch.toString();
    await drafts.save(
      userId: user,
      name: 'post-picker-context',
      data: {'original': original?.toJson(), 'nonce': nonce},
    );
    await drafts.save(
      userId: _ownerKey,
      name: 'active',
      data: {'user': user, 'nonce': nonce},
    );
    return nonce;
  }

  Future<Map<String, dynamic>?> pending(String user) async {
    final owner = await drafts.read(userId: _ownerKey, name: 'active');
    if (owner?['user'] != user) return null;
    final context = await drafts.read(
      userId: user,
      name: 'post-picker-context',
    );
    if (context?['nonce'] != owner?['nonce']) return null;
    return context;
  }

  Future<void> finish(String user, String nonce) async {
    final owner = await drafts.read(userId: _ownerKey, name: 'active');
    if (owner?['user'] != user || owner?['nonce'] != nonce) return;
    await drafts.remove(userId: _ownerKey, name: 'active');
    await drafts.remove(userId: user, name: 'post-picker-context');
  }
}
