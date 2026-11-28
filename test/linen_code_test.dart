import 'package:flutter_test/flutter_test.dart';
import 'package:love_mobi/features/linen/_linen_shared.dart';

/// Printed tags carry checksummed structured IDs: `BSG-A0001XL` means bedsheet,
/// hotel code G, series A / number 0001, with two check letters. Only this
/// format is valid; the older random `LL-XXXXXX` and numeric-only tags are not.
void main() {
  const tag = 'BSG-A0001XL';
  const towelTag = 'TWH-A0020YU';

  group('checkLetters', () {
    test('matches the weighted mod-676 check letters used by the APIs', () {
      expect(checkLetters('BSG-A0001'), 'XL');
      expect(checkLetters('TWH-A0020'), 'YU');
      expect(checkLetters('TWAB-A0001'), 'RV');
      expect(
          isValidStructuredId('BSG-A0001${checkLetters('BSG-A0001')}'), isTrue);
      expect(isValidStructuredId('BSG-A0001${checkLetters('BSG-A0002')}'),
          isFalse);
    });
  });

  group('parseLinenCode', () {
    test('accepts checksummed structured bare codes', () {
      expect(parseLinenCode('  bsg-a0001xl '), tag);
      expect(parseLinenCode(tag), tag);
      expect(parseLinenCode(towelTag), towelTag);
      expect(parseLinenCode('TWAB-A0001RV'), 'TWAB-A0001RV');
    });

    test('accepts structured codes inside links and label text', () {
      expect(
        parseLinenCode('https://lovelaundry.lk/i/$tag'),
        tag,
      );
      expect(
        parseLinenCode('https://lovelaundry.lk/scan?code=${tag.toLowerCase()}'),
        tag,
      );
      expect(
        parseLinenCode('LOVE LAUNDRY $tag KING BEDSHEET'),
        tag,
      );
    });

    test('rejects legacy tags, old numeric IDs and wrong check letters', () {
      for (final bad in ['LL-7K4P92', 'BSG-00001', 'BSG-A0001XY']) {
        expect(isValidStructuredId(bad), isFalse);
        expect(parseLinenCode(bad), isNull);
        expect(parseLinenCode('https://lovelaundry.lk/i/$bad'), isNull);
      }
    });

    test('rejects unrelated text', () {
      expect(parseLinenCode('https://example.com/home'), isNull);
      expect(parseLinenCode('not a linen tag'), isNull);
    });
  });
}
