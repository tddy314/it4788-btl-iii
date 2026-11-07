class ChatEmoteConverter {
  static const Map<String, String> emoteMap = {
    ':))': '😆',
    ':-)': '😊',
    ':)': '😊',
    ':(': '🙁',
    ':-(': '🙁',
    ':D': '😃',
    ':-D': '😃',
    ';)': '😉',
    ';-)': '😉',
    ':P': '😛',
    ':-P': '😛',
    ':p': '😛',
    ':-p': '😛',
    ':O': '😮',
    ':-O': '😮',
    ':o': '😮',
    ':-o': '😮',
    '<3': '❤️',
    '</3': '💔',
    '(y)': '👍',
    'B)': '😎',
    'B-)': '😎',
  };

  /// Chuyển đổi các ký tự đặc biệt thành emoji tương ứng trong chuỗi văn bản
  static String convertEmotes(String text) {
    if (text.isEmpty) return text;
    var result = text;
    // Sắp xếp các key có độ dài lớn hơn trước (vd :)) trước :) để không bị thay thế nhầm)
    final sortedKeys = emoteMap.keys.toList()
      ..sort((a, b) => b.length.compareTo(a.length));

    for (final key in sortedKeys) {
      if (result.contains(key)) {
        result = result.replaceAll(key, emoteMap[key]!);
      }
    }
    return result;
  }
}
