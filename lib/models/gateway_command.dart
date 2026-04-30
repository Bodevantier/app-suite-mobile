class GatewayCommand {
  const GatewayCommand({
    required this.command,
    this.deviceSourceAddress,
    this.payload = const <String, dynamic>{},
  });

  final String command;
  final int? deviceSourceAddress;
  final Map<String, dynamic> payload;

  factory GatewayCommand.requestDeviceList() {
    return const GatewayCommand(command: 'request_device_list');
  }

  /// Tell the gateway to drop its cached entry for [sourceAddress] so the
  /// device disappears from subsequent device_list snapshots. The wire
  /// format is the legacy short form `forget_device src=N\n` (parsed by
  /// the ESP32 BLE command handler).
  factory GatewayCommand.forgetDevice(int sourceAddress) {
    return GatewayCommand(
      command: 'forget_device',
      deviceSourceAddress: sourceAddress,
    );
  }

  factory GatewayCommand.requestDeviceDetails(int sourceAddress) {
    return GatewayCommand(
      command: 'request_device_details',
      deviceSourceAddress: sourceAddress,
    );
  }

  factory GatewayCommand.requestSupportedPgns(int sourceAddress) {
    return GatewayCommand(
      command: 'request_supported_pgns',
      deviceSourceAddress: sourceAddress,
    );
  }

  factory GatewayCommand.sendN2kCommand({
    required int sourceAddress,
    required Map<String, dynamic> payload,
  }) {
    return GatewayCommand(
      command: 'send_n2k_command',
      deviceSourceAddress: sourceAddress,
      payload: payload,
    );
  }

  String toCommandLine() {
    if (command == 'request_device_list' &&
        deviceSourceAddress == null &&
        payload.isEmpty) {
      return 'request_device_list\n';
    }

    // Short, ESP32-friendly form for forget_device so it doesn't need the
    // full "cmd:" prefix parser path on the bridge.
    if (command == 'forget_device' &&
        deviceSourceAddress != null &&
        payload.isEmpty) {
      return 'forget_device src=$deviceSourceAddress\n';
    }

    final buffer = StringBuffer('cmd:$command');
    if (deviceSourceAddress != null) {
      buffer.write(' src=$deviceSourceAddress');
    }
    payload.forEach((key, value) {
      buffer.write(' $key=$value');
    });
    buffer.write('\n');
    return buffer.toString();
  }
}
