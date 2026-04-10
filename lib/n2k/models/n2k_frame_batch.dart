import 'n2k_frame.dart';

class N2kFrameBatch {
  const N2kFrameBatch({
    required this.version,
    required this.packetType,
    required this.sequence,
    required this.packetFlags,
    required this.frames,
  });

  final int version;
  final int packetType;
  final int sequence;
  final int packetFlags;
  final List<N2kFrame> frames;
}