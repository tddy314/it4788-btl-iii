import '../../../core/text/emote_converter.dart';

/// Compatibility API for existing chat widgets/tests.
abstract final class ChatEmoteConverter {
  static const emoteMap = EmoteConverter.emoteMap;
  static String convertEmotes(String text) => EmoteConverter.convert(text);
}
