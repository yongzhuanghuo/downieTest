import 'package:downie_test/core/storage/import_links.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses Downie CSV with title and path', () {
    final links = parseStructuredLinks(
      'url,title,path\n'
      'https://example.com/a,"标题, 带逗号",/tmp/videos\n'
      'https://example.com/b,B,"/tmp/other"\n',
    );
    expect(links, isNotNull);
    expect(links, hasLength(2));
    expect(links!.first.url, 'https://example.com/a');
    expect(links.first.title, '标题, 带逗号');
    expect(links.first.path, '/tmp/videos');
    expect(links.last.title, 'B');
  });

  test('accepts uppercase headers and ignores missing path column', () {
    final links = parseStructuredLinks(
      'URL,TITLE\nhttps://example.com/a,A\n',
    );
    expect(links, hasLength(1));
    expect(links!.single.path, '');
  });

  test('ignores CSV without URL and title headers', () {
    expect(
      parseStructuredLinks('name,link\nA,https://example.com/a\n'),
      isNull,
    );
    expect(parseStructuredLinks('just some text'), isNull);
  });

  test('parses Downie XML with CDATA and path', () {
    final links = parseStructuredLinks('''
<?xml version="1.0" encoding="UTF-8"?>
<downloads>
  <download>
    <url>https://example.com/a?x=1&amp;y=2</url>
    <title><![CDATA[标题 & 更多]]></title>
    <path>/tmp/videos</path>
  </download>
  <download>
    <url>https://example.com/b</url>
    <title>B</title>
  </download>
</downloads>
''');
    expect(links, hasLength(2));
    expect(links!.first.url, 'https://example.com/a?x=1&y=2');
    expect(links.first.title, '标题 & 更多');
    expect(links.first.path, '/tmp/videos');
    expect(links.last.path, '');
  });

  test('returns null for XML without download entries', () {
    expect(
      parseStructuredLinks('<downloads><other/></downloads>'),
      isNull,
    );
  });
}
