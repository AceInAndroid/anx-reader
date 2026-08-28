import 'package:anx_reader/service/ai/reading_structure_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const parser = ReadingStructureParser();

  test('recognizes volume and case headings for long fiction', () {
    final structure = parser.parse(const [
      ReadingStructureChapter(href: 'cover', title: '版权信息'),
      ReadingStructureChapter(href: 'v1', title: '第一册 尸语者'),
      ReadingStructureChapter(href: 'c1', title: '第一案 初次解剖'),
      ReadingStructureChapter(href: 'c1-body', title: '初次解剖'),
      ReadingStructureChapter(href: 'c2', title: '第二案 沉睡之妻'),
    ]);
    expect(structure.hasHierarchy, isTrue);
    expect(structure.units[2].volumeId, 'volume-1');
    expect(structure.units[2].arcId, 'volume-1-arc-1');
    expect(structure.units[3].arcId, 'volume-1-arc-1');
    expect(structure.units[4].arcId, 'volume-1-arc-2');
  });

  test('falls back to chapter units when headings are unavailable', () {
    final structure = parser.parse(const [
      ReadingStructureChapter(href: 'a', title: 'Introduction'),
      ReadingStructureChapter(href: 'b', title: 'Chapter One'),
    ]);
    expect(structure.usedFallback, isTrue);
    expect(structure.units, hasLength(2));
    expect(structure.units.first.sceneId, 'scene-a');
  });

  test('scopes chapters to independent works inside a collection EPUB', () {
    final structure = parser.parse(const [
      ReadingStructureChapter(
        href: 'Text/part0050.xhtml',
        title: '白夜行',
        hasChildren: true,
      ),
      ReadingStructureChapter(
        href: 'Text/part0053.xhtml',
        title: '第一章',
        tocDepth: 1,
      ),
      ReadingStructureChapter(
        href: 'Text/part0054.xhtml',
        title: '第二章',
        tocDepth: 1,
      ),
      ReadingStructureChapter(
        href: 'Text/part0066.xhtml',
        title: '解忧杂货店',
        hasChildren: true,
      ),
      ReadingStructureChapter(
        href: 'Text/part0069.xhtml',
        title: '第一章 回答在牛奶箱里',
        tocDepth: 1,
      ),
    ]);

    final whiteNight = structure.units[1].workId;
    final generalStore = structure.units[4].workId;
    expect(whiteNight, 'work-text-part0050-xhtml');
    expect(structure.units[2].workId, whiteNight);
    expect(structure.units[1].workTitle, '白夜行');
    expect(generalStore, 'work-text-part0066-xhtml');
    expect(generalStore, isNot(whiteNight));
    // Ordinary chapters inside a work are scenes, not fake case boundaries.
    expect(structure.units[1].arcId, isNull);
    expect(structure.units[4].arcId, isNull);
  });
}
