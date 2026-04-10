class N2kFrame {
  const N2kFrame({
    required this.canId,
    required this.dlc,
    required this.flags,
    required this.data,
  });

  final int canId;
  final int dlc;
  final int flags;
  final List<int> data;

  int get sourceAddress => canId & 0xff;

  int get pgn {
    final dataPage = (canId >> 24) & 0x01;
    final pduFormat = (canId >> 16) & 0xff;
    var pduSpecific = (canId >> 8) & 0xff;

    if (pduFormat < 240) {
      pduSpecific = 0;
    }

    return (dataPage << 16) | (pduFormat << 8) | pduSpecific;
  }
}