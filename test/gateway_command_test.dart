import 'package:ble_application/models/gateway_command.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('request_device_list command is plain text', () {
    final command = GatewayCommand.requestDeviceList();

    expect(command.toCommandLine(), 'request_device_list\n');
  });

  test('other commands use cmd prefix text form', () {
    final command = GatewayCommand.requestDeviceDetails(45);

    expect(command.toCommandLine(), 'cmd:request_device_details src=45\n');
  });
}