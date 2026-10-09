import 'package:pscore/pscore.dart';

/// Controls whether recoverable SHC issues stop decoding.
enum ShcDecodeMode {
  /// Rejects unknown versions, out-of-range points, and trailing bytes.
  strict,

  /// Keeps such data and reports each issue as a warning.
  tolerant,
}

/// Resource limits applied while decoding an SHC library.
final class ShcDecodeOptions {
  /// Handling policy for recoverable defects.
  final ShcDecodeMode mode;

  /// Maximum accepted input size.
  final int maxFileBytes;

  /// Maximum number of contours declared by one library.
  final int maxContours;

  /// Maximum number of points in one contour.
  final int maxPoints;

  /// Maximum UTF-16 code-unit count accepted for one name.
  final int maxNameCodeUnits;

  /// Creates bounded decode options suitable for untrusted input.
  const ShcDecodeOptions({
    this.mode = ShcDecodeMode.tolerant,
    this.maxFileBytes = 16 * 1024 * 1024,
    this.maxContours = 100000,
    this.maxPoints = 256,
    this.maxNameCodeUnits = 4096,
  });
}

/// Describes a recoverable issue found while decoding.
final class ShcWarning extends PsWarning {
  /// Zero-based contour index associated with the issue, when known.
  final int? contourIndex;

  /// Creates a warning with optional source context.
  const ShcWarning({
    required super.message,
    super.offset,
    this.contourIndex,
  });

  @override
  String get typeName => 'ShcWarning';

  @override
  String get context {
    final int? index = contourIndex;
    return index == null ? '' : ' in contour ${index + 1}';
  }
}

/// Reports malformed, truncated, unsupported, or unsafe SHC input.
final class ShcFormatException extends PsFormatException {
  /// Creates an error at an optional absolute byte [offset].
  const ShcFormatException({
    required super.message,
    super.source,
    super.offset,
  });

  @override
  String get typeName => 'ShcFormatException';
}

/// Reports a contour that cannot be written to an SHC library.
final class ShcWriteException extends PsWriteException {
  /// Creates an encoding error with a user-facing [message].
  const ShcWriteException({
    required super.message,
  });

  @override
  String get typeName => 'ShcWriteException';
}
