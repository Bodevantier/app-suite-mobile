import 'package:ble_application/n2k/n2k_binary_packet_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses a binary frame batch packet', () {
    final parser = N2kBinaryPacketParser();
    final bytes = <int>[
      1, 1, 7, 0, 1, 0, 0, 0,
      0x23, 0x02, 0xfd, 0x09,
      8,
      0x05,
      0x00, 0x00, 0x08, 0x34, 0x12, 0x00, 0x00, 0x00,
    ];

    final packet = parser.parse(bytes);

    expect(packet, isNotNull);
    expect(packet!.sequence, 7);
    expect(packet.frames, hasLength(1));
    expect(packet.frames.first.canId, 0x09fd0223);
    expect(packet.frames.first.pgn, 130306);
  });
}