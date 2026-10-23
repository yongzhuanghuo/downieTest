import 'package:downie_test/core/sites/bilibili/bilibili_wbi.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('WBI signature matches known vector', () {
    final wbi = BilibiliWbi(
      imgUrl:
          'https://i0.hdslb.com/bfs/wbi/7cd084941338484aae1ad9425b84077c.png',
      subUrl:
          'https://i0.hdslb.com/bfs/wbi/4932caff0ff746eab6f01bf08b70ac45.png',
    );
    final query = wbi.sign({'bvid': 'BV1GJ411x7h7'}, wts: 1700000000);
    expect(
      query,
      'bvid=BV1GJ411x7h7&wts=1700000000&w_rid=01e6313af30738e69bb94b1a664cd43b',
    );
  });
}
