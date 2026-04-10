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
