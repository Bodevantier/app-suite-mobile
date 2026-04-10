import 'package:ble_application/ble/framing/newline_message_framer.dart';
import 'package:ble_application/ble/repositories/ble_gateway_repository.dart';
import 'package:ble_application/ble/testing/gateway_protocol_fixtures.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reassembles chunked snapshot fixture into repository state', () {
    final framer = NewlineMessageFramer();
    final repository = BleGatewayRepository();

    for (final line in GatewayProtocolFixtures.eventLines) {
      repository.handleIncomingLine(line, source: 'fixture');
    }

    for (final chunk in GatewayProtocolFixtures.chunkedTextNotificationChunks) {
      final lines = framer.addChunk(chunk);
      for (final line in lines) {
        repository.handleIncomingLine(line, source: 'fixture');
      }
    }

    expect(repository.latestSnapshot, isNotNull);
    expect(repository.latestSnapshot!.snapshotRequestId, 12);
    expect(repository.latestSnapshot!.snapshotComplete, isTrue);
    expect(repository.devices, hasLength(3));
    expect(repository.devices.any((device) => device.sourceAddress == 49), isTrue);
    expect(repository.devices.any((device) => device.sourceAddress == 45), isTrue);
    expect(repository.requestPending, isFalse);
    expect(repository.snapshotInProgress, isFalse);
  });
}