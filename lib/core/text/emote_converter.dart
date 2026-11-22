/// Shared text behavior required for posts, comments and direct messages.
abstract final class EmoteConverter {
  static const emoteMap = <String, String>{
    '<(")': '🐧',
    '(^^^)': '🦈',
    ':)))': '🤣',
    ':))': '😆',
    ':-)': '😊',
    ':)': '😊',
    ':D': '😃',
    ':-D': '😃',
    ';)': '😉',
    ';-)': '😉',
    ':v': '✌️',
    '<3': '❤️',
    '</3': '💔',
    ':*': '😘',
    ':-*': '😘',
    ':P': '😛',
    ':-P': '😛',
    ':p': '😛',
    ':-p': '😛',
    'B)': '😎',
    'B-)': '😎',
    '(y)': '👍',
    ':(': '🙁',
    ':-(': '🙁',
    ':(((': '😭',
    ':((': '😭',
    ":'(": '😢',
    ":'-(": '😢',
    'T_T': '😭',
    'T.T': '😭',
    ':O': '😮',
    ':-O': '😮',
    ':o': '😮',
    ':-o': '😮',
    ':/': '😕',
    ':-/': '😕',
    ':\\': '😕',
    ':-\\': '😕',
    '-_-': '😑',
    '>:(': '😡',
    '>:-(': '😡',
    'x(': '😡',
    'X(': '😡',
    'O:)': '😇',
    'O:-)': '😇',
    '3:)': '😈',
    '>:)': '😈',
  };
  static final _pattern = RegExp(
    r'https?://\S+|' +
        (emoteMap.keys.toList()..sort((a, b) => b.length.compareTo(a.length)))
            .map(RegExp.escape)
            .join('|'),
  );
  static String convert(String text) =>
      text.replaceAllMapped(_pattern, (m) => emoteMap[m[0]] ?? m[0]!);
}
