import 'models/n2k_frame.dart';
import 'models/n2k_frame_batch.dart';

class N2kBinaryPacketParser {
  static const int packetVersion = 1;
  static const int packetTypeFrameBatch = 1;
  static const int headerLength = 6;
  static const int frameLength = 14;

  N2kFrameBatch? parse(List<int> bytes) {
    if (bytes.length < headerLength) {
      return null;
    }

    final version = bytes[0];
    final packetType = bytes[1];
    final sequence = _readUint16Le(bytes, 2);
    final frameCount = bytes[4];
    final packetFlags = bytes[5];
    final expectedLength = headerLength + (frameCount * frameLength);

    if (version != packetVersion || packetType != packetTypeFrameBatch) {
      return null;
    }
    if (bytes.length != expectedLength) {
      return null;
    }

    final frames = <N2kFrame>[];
    var offset = headerLength;
    for (var i = 0; i < frameCount; i++) {
      final canId = _readUint32Le(bytes, offset);
      final dlc = bytes[offset + 4];
      final flags = bytes[offset + 5];
      final data = bytes.sublist(offset + 6, offset + 14);
      frames.add(N2kFrame(canId: canId, dlc: dlc, flags: flags, data: data));
      offset += frameLength;
    }

    return N2kFrameBatch(
      version: version,
      packetType: packetType,
      sequence: sequence,
      packetFlags: packetFlags,
      frames: List<N2kFrame>.unmodifiable(frames),
    );
  }

  int _readUint16Le(List<int> bytes, int offset) {
    return bytes[offset] | (bytes[offset + 1] << 8);
  }

  int _readUint32Le(List<int> bytes, int offset) {
    return bytes[offset] |
        (bytes[offset + 1] << 8) |
        (bytes[offset + 2] << 16) |
        (bytes[offset + 3] << 24);
  }
}