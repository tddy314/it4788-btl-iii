class ChatEmoteConverter {
  static const Map<String, String> emoteMap = {
    // Chim cánh cụt & Cá mập huyền thoại Facebook
    '<(")': '🐧',
    '(^^^)': '🦈',

    // Cười & Vui vẻ
    ':)))': '🤣',
    ':))': '😆',
    ':-)': '😊',
    ':)': '😊',
    ':D': '😃',
    ':-D': '😃',
    ';)': '😉',
    ';-)': '😉',
    ':v': '✌️',

    // Tình cảm & Yêu thương
    '<3': '❤️',
    '</3': '💔',
    ':*': '😘',
    ':-*': '😘',

    // Trêu đùa & Ngầu
    ':P': '😛',
    ':-P': '😛',
    ':p': '😛',
    ':-p': '😛',
    'B)': '😎',
    'B-)': '😎',
    '(y)': '👍',

    // Buồn bã & Khóc
    ':(': '🙁',
    ':-(': '🙁',
    ':(((': '😭',
    ':((': '😭',
    ":'(": '😢',
    ":'-(": '😢',
    'T_T': '😭',
    'T.T': '😭',

    // Bất ngờ & Bối rối
    ':O': '😮',
    ':-O': '😮',
    ':o': '😮',
    ':-o': '😮',
    ':/': '😕',
    ':-/': '😕',
    ':\\': '😕',
    ':-\\': '😕',
    '-_-': '😑',

    // Tức giận & Biểu tượng đặc biệt
    '>:(': '😡',
    '>:-(': '😡',
    'x(': '😡',
    'X(': '😡',
    'O:)': '😇',
    'O:-)': '😇',
    '3:)': '😈',
    '>:)': '😈',
  };

  /// Chuyển đổi các ký tự đặc biệt thành emoji tương ứng trong chuỗi văn bản
  static String convertEmotes(String text) {
    if (text.isEmpty) return text;
    var result = text;
    // Sắp xếp các key có độ dài lớn hơn trước (vd :))) trước :)) trước :) để không bị thay thế nhầm)
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
