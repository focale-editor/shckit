import 'dart:convert';
import 'dart:typed_data';

import 'package:checks/checks.dart';
import 'package:shckit/shckit.dart';
import 'package:test/test.dart';

/// Exercises SHC decoding, encoding, and conversion to layer-style contours.
void main() {
  final ShcFile library = ShcFile(
    contours: [
      ShcContour(
        name: 'Cone',
        points: const [
          ShcPoint(horizontal: 0, vertical: 0, continuous: false),
          ShcPoint(horizontal: 128, vertical: 255, continuous: false),
          ShcPoint(horizontal: 255, vertical: 0, continuous: false),
        ],
      ),
      ShcContour(
        version: 1,
        name: 'Linéaire',
        points: const [
          ShcPoint(horizontal: 0, vertical: 0),
          ShcPoint(horizontal: 255, vertical: 255),
        ],
      ),
    ],
  );

  group('codec', () {
    test('writes the documented layout and reads it back identically', () {
      final Uint8List bytes = ShcEncoder.encode(library);
      final ShcFile decoded = ShcDecoder.decode(bytes, options: const ShcDecodeOptions(mode: ShcDecodeMode.strict));

      check(ascii.decode(bytes.sublist(0, 4))).equals('8BFS');
      // Header, then version 2: version, name (4 + 5 × 2), count, 3 points, 3 flags, range.
      check(bytes.sublist(10, 14)).deepEquals([0, 0, 0, 2]);
      check(bytes.sublist(28, 30)).deepEquals([0, 3]);
      check(bytes.sublist(34, 38)).deepEquals([0, 255, 0, 128]);
      check(decoded.contours.map((contour) => contour.name).toList()).deepEquals(['Cone', 'Linéaire']);
      check(decoded.contours.first.points.every((point) => !point.continuous)).isTrue();
      check(decoded.contours.last.version).equals(1);
      check(decoded.contours.last.points.every((point) => point.continuous)).isTrue();
      check(const ShcCodec().encode(decoded)).deepEquals(bytes);
    });

    test('converts to and from layer-style contour descriptors', () {
      final PsContour contour = library.contours.first.toContour();
      final ShcContour back = ShcContour.fromContour(contour);

      check(contour.descriptor.classId).equals('ShpC');
      check(contour.name).equals('Cone');
      check(contour.points[1].horizontal?.value).equals(128);
      check(contour.points[1].continuous).equals(false);
      check(library.contours.last.toContour().points.first.continuous).isNull();
      check(back.points.map((point) => (point.horizontal, point.vertical, point.continuous)).toList()).deepEquals([(0, 0, false), (128, 255, false), (255, 0, false)]);
      check(ShcContour.fromContour(PsContour.linear()).points.first.continuous).isTrue();
    });
  });

  group('validation', () {
    test('reports contours with too few points and trailing bytes unless strict', () {
      final Uint8List bytes = Uint8List.fromList([
        ...ShcEncoder.encode(
          ShcFile(
            contours: [
              ShcContour(name: 'Odd', points: const [ShcPoint(horizontal: 0, vertical: 0)]),
            ],
          ),
        ),
        7,
      ]);

      final ShcFile file = ShcDecoder.decode(bytes);

      check(file.warnings).length.equals(2);
      check(() => ShcDecoder.decode(bytes, options: const ShcDecodeOptions(mode: ShcDecodeMode.strict))).throws<ShcFormatException>();
    });

    test('rejects broken input and unwritable contours', () {
      check(() => ShcDecoder.decode(Uint8List.fromList(ascii.encode('8BPT\u0000\u0001')))).throws<ShcFormatException>();
      check(() => ShcDecoder.decode(Uint8List.fromList([...ascii.encode('8BFS'), 0, 1, 0, 0, 0, 1, 0, 0, 0, 9]))).throws<ShcFormatException>();
      check(() => ShcDecoder.decode(Uint8List.fromList([...ascii.encode('8BFS'), 0, 1, 0, 0, 0, 1]))).throws<ShcFormatException>();
      check(
        () => ShcEncoder.encode(
          ShcFile(
            contours: [
              ShcContour(name: 'Bad', points: const [ShcPoint(horizontal: 256, vertical: 0)]),
            ],
          ),
        ),
      ).throws<ShcWriteException>();
    });
  });
}
