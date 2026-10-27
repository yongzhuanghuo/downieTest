import 'package:downie_test/core/storage/adult_filter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('matches listed hosts and subdomains', () {
    expect(isAdultUrl('https://www.pornhub.com/view_video.php?viewkey=1'), isTrue);
    expect(isAdultUrl('https://m.xvideos.com/video1'), isTrue);
    expect(isAdultUrl('https://chaturbate.com/room'), isTrue);
    expect(isAdultUrl('https://www.onlyfans.com/user'), isTrue);
  });

  test('does not match unrelated or lookalike hosts', () {
    expect(isAdultUrl('https://www.youtube.com/watch?v=1'), isFalse);
    expect(isAdultUrl('https://notpornhub.com/video'), isFalse);
    expect(isAdultUrl('https://pornhub.com.example.com/video'), isFalse);
    expect(isAdultUrl('not a url'), isFalse);
    expect(isAdultUrl(''), isFalse);
  });
}
