import 'package:ble_application/ble/repositories/ble_gateway_repository.dart';
import 'package:ble_application/ble/testing/gateway_protocol_fixtures.dart';
import 'package:ble_application/models/n2k_device_info.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('deduplicates devices by source address with latest entry winning', () {
    final devices = <N2kDeviceInfo>[
      const N2kDeviceInfo(
        src: 45,
        name: 'Old name',
        model: 'A',
        manufacturer: 'M1',
        category: 'wind',
        online: true,
      ),
      const N2kDeviceInfo(
        src: 45,
        name: 'New name',
        model: 'B',
        manufacturer: 'M2',
        category: 'wind',
        online: false,
      ),
      const N2kDeviceInfo(
        src: 18,
        name: 'Pilot',
        model: 'AP200',
        manufacturer: 'HelmWorks',
        category: 'steering',
        online: true,
      ),
    ];

    final deduped = dedupeDevicesBySrc(devices);

    expect(deduped, hasLength(2));
    expect(
      deduped.firstWhere((device) => device.sourceAddress == 45).displayName,
      'New name',
    );
  });

  test('hides gateway device from setup when real N2K nodes exist', () {
    final devices = <N2kDeviceInfo>[
      const N2kDeviceInfo(
        src: 49,
        name: 'SDolve NMEA2000 Bluetooth',
        model: 'ESP32_SPI_N2K_BLE',
        manufacturer: 'SDolve',
        category: 'gateway',
        online: true,
      ),
      const N2kDeviceInfo(
        src: 23,
        name: 'SDolve Wind',
        model: '1.0.0.0',
        manufacturer: 'XSense Marine',
        category: 'wind',
        online: true,
      ),
    ];

    final visible = filterSetupVisibleDevices(devices);

    expect(visible, hasLength(1));
    expect(visible.single.sourceAddress, 23);
  });

  test('shows gateway device in setup when it is the only node', () {
    final devices = <N2kDeviceInfo>[
      const N2kDeviceInfo(
        src: 49,
        name: 'SDolve NMEA2000 Bluetooth',
        model: 'ESP32_SPI_N2K_BLE',
        manufacturer: 'SDolve',
        category: 'gateway',
        online: true,
      ),
    ];

    final visible = filterSetupVisibleDevices(devices);

    expect(visible, hasLength(1));
    expect(visible.single.sourceAddress, 49);
  });

  test('keeps last valid snapshot when malformed input arrives', () {
    final repository = BleGatewayRepository();

    for (final line in GatewayProtocolFixtures.snapshotTextLines) {
      repository.handleIncomingLine(line, source: 'fixture');
    }
    repository.handleIncomingLine(
      'device_list snapshot id=',
      source: 'fixture',
    );

    expect(repository.latestSnapshot, isNotNull);
    expect(repository.devices, hasLength(3));
    expect(repository.lastError, 'Malformed device_list snapshot ignored.');
  });

  test('clears transient progress on disconnect but keeps cached snapshot', () {
    final repository = BleGatewayRepository();

    repository.handleIncomingLine(
      'device_list begin id=12 count=3',
      source: 'fixture',
    );
    for (final line in GatewayProtocolFixtures.snapshotTextLines) {
      repository.handleIncomingLine(line, source: 'fixture');
    }

    repository.handleDisconnected();

    expect(repository.snapshotInProgress, isFalse);
    expect(repository.requestPending, isFalse);
    expect(repository.latestSnapshot, isNotNull);
    expect(repository.devices, hasLength(3));
  });

  test('builds snapshot from mixed event and snapshot/device lines', () {
    final repository = BleGatewayRepository();

    repository.handleIncomingLine(
      'device_list request sent id=12',
      source: 'fixture',
    );
    repository.handleIncomingLine(
      'device_list begin id=12 count=3',
      source: 'fixture',
    );
    repository.handleIncomingLine(
      GatewayProtocolFixtures.snapshotTextLines[0],
      source: 'fixture',
    );
    repository.handleIncomingLine(
      GatewayProtocolFixtures.snapshotTextLines[1],
      source: 'fixture',
    );
    repository.handleIncomingLine(
      GatewayProtocolFixtures.snapshotTextLines[2],
      source: 'fixture',
    );
    repository.handleIncomingLine(
      GatewayProtocolFixtures.snapshotTextLines[3],
      source: 'fixture',
    );
    repository.handleIncomingLine(
      'device_list complete id=12 devices=3',
      source: 'fixture',
    );

    expect(repository.currentRequestId, 12);
    expect(repository.progressExpected, 3);
    expect(repository.progressReceived, 3);
    expect(repository.snapshotInProgress, isFalse);
    expect(repository.requestPending, isFalse);
    expect(repository.devices, hasLength(3));
    expect(
      repository.devices.any((device) => device.sourceAddress == 49),
      isTrue,
    );
  });

  test('keeps cached devices when a new request is queued', () {
    final repository = BleGatewayRepository();

    for (final line in GatewayProtocolFixtures.snapshotTextLines) {
      repository.handleIncomingLine(line, source: 'fixture');
    }

    expect(repository.devices, hasLength(3));

    repository.markRequestQueued();

    expect(repository.devices, hasLength(3));
    expect(repository.latestSnapshot, isNull);
    expect(repository.snapshotInProgress, isTrue);
    expect(repository.requestPending, isTrue);
    expect(repository.lastStatusLine, 'Sending request_device_list...');
  });

  test('keeps snapshot status line concise while devices stream in', () {
    final repository = BleGatewayRepository();

    repository.handleIncomingLine(
      GatewayProtocolFixtures.snapshotTextLines[0],
      source: 'fixture',
    );
    repository.handleIncomingLine(
      GatewayProtocolFixtures.snapshotTextLines[1],
      source: 'fixture',
    );

    expect(repository.lastStatusLine, 'Snapshot complete (3/3)');
    expect(repository.lastStatusLine.length, lessThan(40));
  });
}
