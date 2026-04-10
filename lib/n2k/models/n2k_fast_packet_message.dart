class N2kFastPacketMessage {
  const N2kFastPacketMessage({
    required this.pgn,
    required this.source,
    required this.payload,
  });

  final int pgn;
  final int source;
  final List<int> payload;
}