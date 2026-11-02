import 'package:flutter_test/flutter_test.dart';

import 'package:love_mobi/features/linen/_linen_shared.dart';

/// The tag a lens hands us is not always the bare code: the same payload must
/// resolve to the same identifier here and in the web app
/// (`quotations-ui/src/features/linen/lib/linen-code.ts`).
void main() {
  group('parseLinenCode', () {
    test('accepts the code a LoveLaundry tag prints', () {
      expect(parseLinenCode('LL-7K4P92'), 'LL-7K4P92');
      expect(parseLinenCode('ll-7k4p92'), 'LL-7K4P92');
      expect(parseLinenCode('  LL-7K4P92\n'), 'LL-7K4P92');
    });

    test('accepts codes wrapped by a scanner or a wallet app', () {
      expect(parseLinenCode('"LL-7K4P92"'), 'LL-7K4P92');
      expect(parseLinenCode('[LL-7K4P92]'), 'LL-7K4P92');
      expect(parseLinenCode('\u0002LL-7K4P92\r'), 'LL-7K4P92');
    });

    test('extracts the code from a deep link or a re-printed URL tag', () {
      expect(
        parseLinenCode('https://manager.lovelaundry.lk/linen/scanner?code=LL-7K4P92'),
        'LL-7K4P92',
      );
      expect(
        parseLinenCode('https://lovelaundry.lk/track?tag=ll-7k4p92'),
        'LL-7K4P92',
      );
      expect(
        parseLinenCode('https://lovelaundry.lk/linen/LL-7K4P92'),
        'LL-7K4P92',
      );
      expect(
        parseLinenCode('https://lovelaundry.lk/linen/LL-7K4P92?ref=qr'),
        'LL-7K4P92',
      );
    });

    test('finds the code when a label carries more than the code', () {
      expect(
        parseLinenCode('LOVE LAUNDRY LL-7K4P92 KING BEDSHEET'),
        'LL-7K4P92',
      );
      expect(parseLinenCode('https://x.lk/#/LL-7K4P92'), 'LL-7K4P92');
      expect(parseLinenCode('Please scan LL-7K4P92.'), 'LL-7K4P92');
    });

    test('rejects text that is not a linen code', () {
      expect(parseLinenCode(''), isNull);
      expect(parseLinenCode('   '), isNull);
      expect(parseLinenCode('https://example.com'), isNull);
      expect(parseLinenCode('WIFI:S:HotelGuest;P:12345;;'), isNull);
      expect(parseLinenCode('A'), isNull);
    });
  });
}
