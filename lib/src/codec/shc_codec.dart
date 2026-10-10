import 'dart:convert';
import 'dart:typed_data';

import 'package:pscore/pscore.dart';
import 'package:shckit/src/model/shc_file.dart';
import 'package:shckit/src/model/shc_options.dart';

/// File signature of every contour library.
const String _signature = '8BFS';

/// Decodes Photoshop `8BFS` contour libraries.
final class ShcDecoder extends Converter<List<int>, ShcFile> {
  /// Options applied by [convert].
  final ShcDecodeOptions options;

  /// Creates a reusable decoder with fixed [options].
  const ShcDecoder({this.options = const ShcDecodeOptions()});

  @override
  ShcFile convert(List<int> input) => decode(input is Uint8List ? input : Uint8List.fromList(input), options: options);

  /// Decodes one complete in-memory SHC [bytes] buffer.
  static ShcFile decode(Uint8List bytes, {ShcDecodeOptions options = const ShcDecodeOptions()}) {
    if (bytes.length > options.maxFileBytes) {
      throw ShcFormatException(message: 'SHC file size ${bytes.length} exceeds the configured ${options.maxFileBytes} byte limit', source: bytes, offset: 0);
    }
    final List<ShcWarning> warnings = [];
    int? contourIndex;
    void issue(String message, int offset) {
      if (options.mode == ShcDecodeMode.strict) {
        throw ShcFormatException(message: message, source: bytes, offset: offset);
      }
      warnings.add(ShcWarning(message: message, offset: offset, contourIndex: contourIndex));
    }

    try {
      final PsBinaryReader reader = PsBinaryReader(bytes: bytes);
      final String signature = reader.readString(4);
      if (signature != _signature) {
        throw ShcFormatException(message: 'Invalid SHC signature "$signature"; expected "$_signature"', source: bytes, offset: 0);
      }
      final int version = reader.readUint16();
      if (version != 1) {
        issue('SHC version $version is not 1', 4);
      }
      final int count = reader.readUint32();
      if (count > options.maxContours) {
        throw ShcFormatException(message: 'SHC contour count $count exceeds the configured ${options.maxContours} limit', source: bytes, offset: 6);
      }
      final List<ShcContour> contours = [];
      for (int index = 0; index < count; index++) {
        contourIndex = index;
        final int recordOffset = reader.offset;
        final int recordVersion = reader.readUint32();
        if (recordVersion != 1 && recordVersion != 2) {
          throw ShcFormatException(message: 'Unsupported SHC contour version $recordVersion', source: bytes, offset: recordOffset);
        }
        final String name = _readName(reader, options, bytes);
        final int curveFormat = reader.readUint16();
        final int pointCount = reader.readUint16();
        if (pointCount > options.maxPoints) {
          throw ShcFormatException(message: 'SHC point count $pointCount exceeds the configured ${options.maxPoints} limit', source: bytes, offset: reader.offset - 2);
        }
        final List<({int vertical, int horizontal})> coordinates = [for (int point = 0; point < pointCount; point++) (vertical: reader.readUint16(), horizontal: reader.readUint16())];
        final List<bool> continuity = [for (int point = 0; point < pointCount; point++) recordVersion == 1 || reader.readUint8() != 0];
        final int minimumInput = reader.readUint32();
        final int maximumInput = reader.readUint32();
        if (pointCount < 2 || coordinates.any((point) => point.horizontal > 255 || point.vertical > 255)) {
          issue('Contour "$name" needs at least two points in the 0–255 range', recordOffset);
        }
        contours.add(
          ShcContour(
            version: recordVersion,
            name: name,
            curveFormat: curveFormat,
            points: [
              for (int point = 0; point < pointCount; point++) ShcPoint(horizontal: coordinates[point].horizontal, vertical: coordinates[point].vertical, continuous: continuity[point]),
            ],
            minimumInput: minimumInput,
            maximumInput: maximumInput,
          ),
        );
      }
      contourIndex = null;
      if (!reader.isAtEnd) {
        issue('${reader.remaining} unrecognized trailing bytes remain after the SHC contours', reader.offset);
      }
      return ShcFile(version: version, contours: contours, warnings: warnings);
    } on ShcFormatException {
      rethrow;
    } on PsFormatException catch (error) {
      throw ShcFormatException(message: error.message, source: bytes, offset: error.offset);
    } on RangeError catch (error) {
      throw ShcFormatException(message: 'Invalid SHC numeric range: $error', source: bytes);
    }
  }

  /// Reads a length-prefixed UTF-16 name, removing a terminal null.
  static String _readName(PsBinaryReader reader, ShcDecodeOptions options, Uint8List source) {
    final int length = reader.readUint32();
    if (length > options.maxNameCodeUnits) {
      throw ShcFormatException(message: 'SHC name length $length exceeds the configured ${options.maxNameCodeUnits} limit', source: source, offset: reader.offset - 4);
    }
    final List<int> codeUnits = [for (int index = 0; index < length; index++) reader.readUint16()];
    if (codeUnits.isNotEmpty && codeUnits.last == 0) {
      codeUnits.removeLast();
    }
    return String.fromCharCodes(codeUnits);
  }
}

/// Encodes Photoshop `8BFS` contour libraries.
final class ShcEncoder extends Converter<ShcFile, List<int>> {
  /// Creates a reusable encoder.
  const ShcEncoder();

  @override
  Uint8List convert(ShcFile input) => encode(input);

  /// Encodes [file] as a complete SHC library.
  static Uint8List encode(ShcFile file) {
    final PsBinaryWriter writer = PsBinaryWriter()
      ..writeString(_signature)
      ..writeUint16(file.version)
      ..writeUint32(file.contours.length);
    for (final ShcContour contour in file.contours) {
      if (contour.version != 1 && contour.version != 2) {
        throw ShcWriteException(message: 'SHC contour version ${contour.version} is not 1 or 2');
      }
      if (contour.points.length > 0xffff || contour.points.any((point) => point.horizontal < 0 || point.horizontal > 255 || point.vertical < 0 || point.vertical > 255)) {
        throw ShcWriteException(message: 'Contour "${contour.name}" has points outside the 0–255 range');
      }
      writer
        ..writeUint32(contour.version)
        ..writeUint32(contour.name.length + 1)
        ..writeUint16List([...contour.name.codeUnits, 0])
        ..writeUint16(contour.curveFormat)
        ..writeUint16(contour.points.length);
      for (final ShcPoint point in contour.points) {
        writer
          ..writeUint16(point.vertical)
          ..writeUint16(point.horizontal);
      }
      if (contour.version == 2) {
        for (final ShcPoint point in contour.points) {
          writer.writeUint8(point.continuous ? 1 : 0);
        }
      }
      writer
        ..writeUint32(contour.minimumInput)
        ..writeUint32(contour.maximumInput);
    }
    return writer.takeBytes();
  }
}

/// Converts SHC models to and from their binary representation.
final class ShcCodec extends Codec<ShcFile, List<int>> {
  /// Options applied while decoding.
  final ShcDecodeOptions decodeOptions;

  /// Creates a reusable codec.
  const ShcCodec({this.decodeOptions = const ShcDecodeOptions()});

  @override
  ShcDecoder get decoder => ShcDecoder(options: decodeOptions);

  @override
  ShcEncoder get encoder => const ShcEncoder();

  @override
  Uint8List encode(ShcFile input) => ShcEncoder.encode(input);
}
