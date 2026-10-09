import 'package:pscore/pscore.dart';
import 'package:shckit/src/model/shc_options.dart';

/// One control point of a contour, in Photoshop's 0–255 grid.
final class ShcPoint {
  /// Input coordinate, along the effect's falloff.
  final int horizontal;

  /// Output coordinate.
  final int vertical;

  /// Whether the curve passes smoothly through this point instead of forming a corner.
  final bool continuous;

  /// Creates a contour point.
  const ShcPoint({
    required this.horizontal,
    required this.vertical,
    this.continuous = true,
  });
}

/// One named contour of an SHC library.
final class ShcContour {
  /// Record version: 1 has no corner information, 2 stores one flag per point.
  final int version;

  /// Contour name.
  final String name;

  /// Control points in source order.
  final List<ShcPoint> points;

  /// Lower bound of the input range, normally 0.
  final int minimumInput;

  /// Upper bound of the input range, normally 255.
  final int maximumInput;

  /// Creates a contour record.
  ShcContour({
    this.version = 2,
    required this.name,
    required List<ShcPoint> points,
    this.minimumInput = 0,
    this.maximumInput = 255,
  }) : points = List<ShcPoint>.unmodifiable(points);

  /// Creates a record from a layer-style [contour] descriptor.
  ///
  /// Coordinates are rounded to the 0–255 grid. A point without a continuity
  /// flag is treated as smooth, as Photoshop does.
  factory ShcContour.fromContour(PsContour contour) => ShcContour(
    name: contour.name ?? '',
    points: [
      for (final PsContourPoint point in contour.points)
        ShcPoint(
          horizontal: (point.horizontal?.value ?? 0).round().clamp(0, 255),
          vertical: (point.vertical?.value ?? 0).round().clamp(0, 255),
          continuous: point.continuous ?? true,
        ),
    ],
  );

  /// Returns this record as a layer-style contour descriptor.
  PsContour toContour() => PsContour.create(
    name: name,
    points: [
      for (final ShcPoint point in points) PsContourPoint.create(horizontal: point.horizontal.toDouble(), vertical: point.vertical.toDouble(), continuous: version >= 2 ? point.continuous : null),
    ],
  );
}

/// Complete decoded contents of one Photoshop `.shc` contour library.
final class ShcFile {
  /// Library version, normally 1.
  final int version;

  /// Contours in source order.
  final List<ShcContour> contours;

  /// Recoverable issues encountered while decoding.
  final List<ShcWarning> warnings;

  /// Creates an immutable contour library.
  ShcFile({
    this.version = 1,
    required List<ShcContour> contours,
    List<ShcWarning> warnings = const [],
  }) : contours = List<ShcContour>.unmodifiable(contours),
       warnings = List<ShcWarning>.unmodifiable(warnings);
}
