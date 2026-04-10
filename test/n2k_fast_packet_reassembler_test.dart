import 'package:ble_application/n2k/models/n2k_frame.dart';
import 'package:ble_application/n2k/n2k_fast_packet_reassembler.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reassembles multi-frame fast-packet payloads', () {
    final reassembler = N2kFastPacketReassembler();

    final first = N2kFrame(
      canId: 0x09f01423,
      dlc: 8,
      flags: 0x05,
      data: const <int>[0x00, 0x08, 0x41, 0x42, 0x43, 0x44, 0x45, 0x46],
    );
    final second = N2kFrame(
      canId: 0x09f01423,
      dlc: 3,
      flags: 0x05,
      data: const <int>[0x01, 0x47, 0x48, 0, 0, 0, 0, 0],
    );

    expect(reassembler.consume(first), isNull);
    final message = reassembler.consume(second);

    expect(message, isNotNull);
    expect(message!.payload, <int>[65, 66, 67, 68, 69, 70, 71, 72]);
  });
}