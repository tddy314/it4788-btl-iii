import 'package:flutter_test/flutter_test.dart';
import 'package:it4788_btl/core/text/emote_converter.dart';

void main() {
  test('Emotes are replaced without corrupting links or Vietnamese text', () {
    expect(
      EmoteConverter.convert('Chào :)) https://example.com/a/:) <3'),
      'Chào 😆 https://example.com/a/:) ❤️',
    );
    expect(EmoteConverter.convert('<(") (^^^) :((('), '🐧 🦈 😭');
  });
}
