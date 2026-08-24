import 'package:bittora/services/content_moderation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('allows ordinary event notices', () {
    expect(ContentModeration.validate('新刊あります'), isNull);
    expect(ContentModeration.validate('西ホールです'), isNull);
  });

  test('does not broadly ban ordinary words or adult vocabulary', () {
    expect(ContentModeration.validate('セックスについての本です'), isNull);
    expect(ContentModeration.validate('fuckという英単語の説明です'), isNull);
  });

  test('rejects clear Japanese threats or severe harassment', () {
    expect(ContentModeration.validate('死ね'), isNotNull);
    expect(ContentModeration.validate('殺すぞ'), isNotNull);
    expect(ContentModeration.validate('自殺しろ'), isNotNull);
  });

  test('rejects clear English threats or severe harassment', () {
    expect(ContentModeration.validate('FUCK YOU'), isNotNull);
    expect(ContentModeration.validate('kill yourself'), isNotNull);
  });
}
