# Adobe Photoshop SHC support

This document describes the contour-library layout implemented by ShcKit, its conversion to PsCore layer-style descriptors, and the boundaries of validation and reconstruction.

## Container layout

All integers are unsigned and big-endian. A standalone `.shc` library starts with:

| Field | Size | Meaning |
| --- | ---: | --- |
| Signature | 4 bytes | `8BFS` |
| Library version | 2 bytes | Normally 1 |
| Contour count | 4 bytes | Number of consecutive contour records |

`ShcFile` retains the library version and contours in source order. An empty library is accepted. An unexpected library version produces a warning in tolerant mode; its records are still parsed using the supported record layouts.

## Contour records

Each contour has the following fields:

| Field | Size | Meaning |
| --- | ---: | --- |
| Record version | 4 bytes | 1 or 2 |
| Name | 4 + 2n bytes | UTF-16 code-unit count, then the code units |
| Point count | 2 bytes | Number of control points |
| Coordinates | 4 bytes per point | Vertical (output), then horizontal (input), normally 0–255 |
| Continuity | 1 byte per point | Version 2 only: nonzero for smooth, zero for a corner |
| Minimum input | 4 bytes | Normally 0 |
| Maximum input | 4 bytes | Normally 255 |

All coordinate pairs come before the continuity array. Version 1 omits that array and treats every point as smooth. The decoder preserves point order and input-range bounds without sorting or normalizing them.

Unknown record versions fail in both decoding modes because records have no outer byte length that would allow an unfamiliar layout to be skipped safely.

### Names

Adobe's specification defines its Unicode strings as a code-unit count followed by a terminating null. ShcKit writes the null and counts it, as Photoshop's Action Descriptors do, and removes a terminal null when reading.

The count measures UTF-16 code units, including surrogate pairs as two units. The decoder also accepts a name without a terminal null; re-encoding appends one.

## Layer-style descriptor conversion

Layer styles store the same curve as a `ShpC` descriptor whose `Crv ` list holds `CrPt` points with `Hrzn`, `Vrtc`, and an optional `Cnty` flag. `ShcContour.fromContour` and `toContour` bridge this representation through PsCore's `PsContour`.

Importing a descriptor:

- copies its name, using an empty string when the name is absent;
- rounds coordinates to integer values and clamps them to 0–255;
- uses zero for a missing coordinate and smooth continuity for a missing flag;
- creates a version 2 record with the default 0–255 input bounds.

Exporting a record creates a descriptor from its name and points. Version 1 records omit continuity flags; version 2 records write them explicitly. SHC input bounds and unrelated source-descriptor fields are not carried through this conversion.

## Compatibility modes and limits

`ShcDecodeMode.tolerant` is the default. It reports the following issues through `ShcFile.warnings`:

- a library version other than 1;
- a contour with fewer than two points;
- a point coordinate above 255;
- bytes remaining after all declared contours.

`ShcWarning` records the byte offset and an optional zero-based contour index. Strict mode rejects the first compatibility issue with `ShcFormatException`.

Invalid signatures, unsupported record versions, truncated fields, and exceeded resource limits throw in both modes. No partially decoded library is returned after such a failure. The default limits are:

| Option | Default | Applies to |
| --- | ---: | --- |
| `maxFileBytes` | 16 MiB | Complete input buffer |
| `maxContours` | 100,000 | Declared library count |
| `maxPoints` | 256 | Each contour |
| `maxNameCodeUnits` | 4,096 | Each serialized name, including a terminal null when present |

Strict decoding does not enforce coordinate ordering or validate the stored input-range bounds.

## Encoding and preservation

`ShcEncoder` regenerates the signature, contour count, names, points, continuity flags, and input bounds from the model. It retains the supplied library and record versions, but only record versions 1 and 2 are supported.

The encoder rejects more than 65,535 points in a contour or coordinates outside 0–255 with `ShcWriteException`. It does not enforce the decoder's two-point minimum or configured resource limits, and has no separate strict or permissive mode. Version 1 output omits continuity flags even if the model contains corner points.

Reconstruction is semantic: names receive a terminal null and version 2 continuity bytes are normalized to 0 or 1. Unknown trailing bytes are reported during decoding but discarded; warning objects are not serialized. Tolerant decoding therefore does not guarantee that every accepted input can be reconstructed byte for byte.

## Integration guidance

Use `ShcFile.contours` to browse named presets and `ShcContour.toContour()` to pass a selected curve to a PsCore-based layer-style model. `ShcContour.fromContour()` exports a style contour to an SHC library when the rounding and clamping behavior is appropriate.

`ShcCodec` implements `Codec<ShcFile, List<int>>`; `ShcEncoder` and `ShcDecoder` are also reusable converters. All APIs operate on a complete in-memory library. A host editor supplies curve evaluation and effect rendering.

## Current boundaries

ShcKit does not interpolate, evaluate, or render contours. Descriptor conversion preserves the supported name and point fields rather than arbitrary descriptor data.

No public `.shc` file was available to validate against; the layout follows Adobe's specification.

## References

- [Adobe Photoshop File Formats Specification](https://www.adobe.com/devnet-apps/photoshop/fileformatashtml/)
