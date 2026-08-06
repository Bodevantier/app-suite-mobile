// Low-level NMEA 2000 wire-format helpers used to synthesize believable CAN
// frames for demo mode. These build the exact same byte layout the real
// gateway sends over BLE, so the frames can be fed straight into
// [N2kBinaryPacketParser] via `BleController.onBinaryPacket` — no page or
// decoder code needs to know the data isn't real hardware.

import '../n2k/models/n2k_frame.dart';

/// Builds a 29-bit NMEA 2000 CAN identifier for [pgn] originating from
/// [source]. Mirrors the decomposition in [N2kFrame.pgn] in reverse.
int buildCanId({required int pgn, required int source, int priority = 3}) {
  final dataPage = (pgn >> 16) & 0x01;
  final pduFormat = (pgn >> 8) & 0xff;
  // PDU1 (addressable, pduFormat < 240): destination goes in pduSpecific —
  // irrelevant to the decoder (which zeroes it for pduFormat < 240), so
  // broadcast (0xff) is fine. PDU2 (pduFormat >= 240): pduSpecific is the
  // PGN's own group-extension byte.
  final pduSpecific = pduFormat < 240 ? 0xff : (pgn & 0xff);
  return (priority << 26) | (dataPage << 24) | (pduFormat << 16) | (pduSpecific << 8) | source;
}

List<int> _le(int value, int byteCount) {
  return [for (var i = 0; i < byteCount; i++) (value >> (8 * i)) & 0xff];
}

List<int> le16(int value) => _le(value, 2);
List<int> le32(int value) => _le(value, 4);
List<int> le64(int value) => _le(value, 8);

/// A single-frame (non-fast-packet) N2K PGN, padded to 8 data bytes with
/// 0xFF as real senders do for unused/reserved fields.
N2kFrame singleFrame({
  required int pgn,
  required int source,
  required List<int> data,
  int priority = 3,
}) {
  final padded = List<int>.filled(8, 0xff);
  for (var i = 0; i < data.length && i < 8; i++) {
    padded[i] = data[i] & 0xff;
  }
  return N2kFrame(
    canId: buildCanId(pgn: pgn, source: source, priority: priority),
    dlc: data.length > 8 ? 8 : data.length,
    flags: 0,
    data: padded,
  );
}

/// Splits [payload] into NMEA 2000 fast-packet frames: first frame carries
/// 6 payload bytes (after a 2-byte seq/length header), each following frame
/// carries 7 (after a 1-byte seq/index header) — matches
/// [N2kFastPacketReassembler]'s expectations exactly.
List<N2kFrame> fastPacketFrames({
  required int pgn,
  required int source,
  required List<int> payload,
  int priority = 6,
  int sequenceId = 0,
}) {
  final canId = buildCanId(pgn: pgn, source: source, priority: priority);
  final seqBits = (sequenceId & 0x07) << 5;
  final frames = <N2kFrame>[];

  final firstLen = payload.length < 6 ? payload.length : 6;
  final first = List<int>.filled(8, 0xff);
  first[0] = seqBits;
  first[1] = payload.length & 0xff;
  for (var i = 0; i < firstLen; i++) {
    first[2 + i] = payload[i] & 0xff;
  }
  frames.add(N2kFrame(canId: canId, dlc: 8, flags: 0, data: first));

  var offset = firstLen;
  var frameIndex = 1;
  while (offset < payload.length) {
    final chunkLen = (payload.length - offset) < 7 ? (payload.length - offset) : 7;
    final data = List<int>.filled(8, 0xff);
    data[0] = seqBits | (frameIndex & 0x1f);
    for (var i = 0; i < chunkLen; i++) {
      data[1 + i] = payload[offset + i] & 0xff;
    }
    frames.add(N2kFrame(canId: canId, dlc: 8, flags: 0, data: data));
    offset += chunkLen;
    frameIndex++;
  }
  return frames;
}

/// Packs [frames] into the outer binary-notification wire format that
/// [N2kBinaryPacketParser] expects: a 6-byte header followed by 14 bytes
/// per frame (4-byte CAN id LE, dlc, flags, 8 data bytes).
List<int> packFrameBatch(List<N2kFrame> frames, {int sequence = 0}) {
  final bytes = <int>[
    1, // version
    1, // packetTypeFrameBatch
    sequence & 0xff,
    (sequence >> 8) & 0xff,
    frames.length & 0xff,
    0, // packet flags
  ];
  for (final f in frames) {
    bytes.addAll(le32(f.canId));
    bytes.add(f.dlc & 0xff);
    bytes.add(f.flags & 0xff);
    for (var i = 0; i < 8; i++) {
      bytes.add(i < f.data.length ? (f.data[i] & 0xff) : 0xff);
    }
  }
  return bytes;
}

/// Builds a 64-bit NMEA 2000 NAME (used by PGN 60928 Address Claim) from its
/// component bit-fields. See N2kDeviceTracker._consumeAddressClaim for the
/// matching decode.
int buildDeviceName({
  required int uniqueNumber,
  required int manufacturerCode,
  required int deviceFunction,
  required int deviceClass,
  int deviceInstanceLower = 0,
  int deviceInstanceUpper = 0,
  int systemInstance = 0,
  int industryGroup = 4, // 4 = Marine
}) {
  var name = 0;
  name |= uniqueNumber & 0x1fffff; // bits 0-20
  name |= (manufacturerCode & 0x7ff) << 21; // bits 21-31
  name |= (deviceInstanceLower & 0x7) << 32; // bits 32-34
  name |= (deviceInstanceUpper & 0x1f) << 35; // bits 35-39
  name |= (deviceFunction & 0xff) << 40; // bits 40-47
  name |= (deviceClass & 0x7f) << 49; // bits 49-55
  name |= (systemInstance & 0x7) << 56; // bits 56-58
  name |= (industryGroup & 0xf) << 59; // bits 59-62
  name |= 1 << 63; // arbitrary-address-capable
  return name;
}

/// Fixed-width ASCII field padded with spaces (the decoder trims trailing
/// whitespace and treats 0x00/0xFF as an early terminator, so space padding
/// round-trips cleanly).
List<int> asciiField(String text, int length) {
  final bytes = List<int>.filled(length, 0x20);
  final chars = text.codeUnits;
  for (var i = 0; i < length && i < chars.length; i++) {
    bytes[i] = chars[i] & 0xff;
  }
  return bytes;
}

/// NMEA 2000 "variable length string" field: [length byte][type=1][ascii].
/// `length` counts itself and the type byte, matching
/// N2kDeviceTracker._readVarString.
List<int> varStringField(String text) {
  final chars = text.codeUnits;
  return <int>[(chars.length + 2) & 0xff, 0x01, ...chars];
}
