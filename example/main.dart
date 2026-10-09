import 'dart:io';

import 'package:shckit/shckit.dart';

/// Prints the contours of one SHC library.
Future<void> main(List<String> arguments) async {
  if (arguments.length != 1) {
    stderr.writeln('Usage: dart run example/main.dart <library.shc>');
    exitCode = 64;
    return;
  }
  final ShcFile library = ShcDecoder.decode(await File(arguments.single).readAsBytes());
  for (final ShcContour contour in library.contours) {
    final String points = contour.points.map((point) => '(${point.horizontal}, ${point.vertical}${point.continuous ? '' : ', corner'})').join(' ');
    stdout.writeln('${contour.name}: $points');
  }
  library.warnings.forEach(stderr.writeln);
}
