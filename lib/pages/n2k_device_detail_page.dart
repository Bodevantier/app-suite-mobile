import 'package:flutter/material.dart';

import '../ble/controllers/ble_gateway_controller.dart';
import '../models/gateway_command.dart';
import '../models/n2k_device_info.dart';

class N2kDeviceDetailPage extends StatelessWidget {
  const N2kDeviceDetailPage({
    super.key,
    required this.device,
    required this.controller,
    this.primaryActionLabel,
    this.onPrimaryAction,
  });

  final N2kDeviceInfo device;
  final BleGatewayController controller;
  final String? primaryActionLabel;
  final VoidCallback? onPrimaryAction;

  @override
  Widget build(BuildContext context) {
    final commandExamples = <GatewayCommand>[
      GatewayCommand.requestDeviceDetails(device.sourceAddress),
      GatewayCommand.requestSupportedPgns(device.sourceAddress),
      GatewayCommand.sendN2kCommand(
        sourceAddress: device.sourceAddress,
        payload: const <String, dynamic>{'action': 'placeholder'},
      ),
    ];
    final extraMetadataEntries = device.extraData.entries.toList(
      growable: false,
    )..sort((a, b) => a.key.compareTo(b.key));

    return Scaffold(
      appBar: AppBar(title: Text(device.displayName)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _DetailSection(
            title: 'Device Metadata',
            children: [
              _DetailRow(label: 'Name', value: device.displayName),
              _DetailRow(label: 'Raw gateway name', value: device.deviceName),
              _DetailRow(
                label: 'Source address',
                value: '${device.sourceAddress}',
              ),
              _DetailRow(
                label: 'Manufacturer',
                value: device.displayManufacturer,
              ),
              _DetailRow(label: 'Model', value: device.displayModel),
              _DetailRow(label: 'Category', value: device.displayCategory),
              _DetailRow(
                label: 'Live wind source',
                value: device.hasLiveWindData ? 'true' : 'false',
              ),
              _DetailRow(
                label: 'Status',
                value: device.isOnline ? 'Online' : 'Offline',
              ),
              _DetailRow(
                label: 'Last seen',
                value: _formatLastSeen(device.lastSeen),
              ),
              _DetailRow(
                label: 'Identity hint',
                value: device.identityRootCauseHint,
              ),
              _DetailRow(
                label: 'Software version',
                value: device.displaySoftwareVersion,
              ),
              _DetailRow(
                label: 'Hardware version',
                value: device.displayHardwareVersion,
              ),
              _DetailRow(
                label: 'Serial number',
                value: device.displaySerialNumber,
              ),
              if (device.deviceClass != null)
                _DetailRow(
                  label: 'Device class',
                  value: '${device.deviceClass}',
                ),
              if (device.deviceFunction != null)
                _DetailRow(
                  label: 'Device function',
                  value: '${device.deviceFunction}',
                ),
              if (device.nameValue != null)
                _DetailRow(
                  label: 'NAME (hex)',
                  value: device.nameValue!,
                ),
              ...extraMetadataEntries.map(
                (entry) => _DetailRow(
                  label: _formatMetadataLabel(entry.key),
                  value: _formatMetadataValue(entry.value),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _DetailSection(
            title: 'Future Commands',
            children: [
              Text('Latest status: ${controller.statusLine}'),
              const SizedBox(height: 8),
              ...commandExamples.map(
                (command) => Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    title: Text(command.command),
                    subtitle: Text(command.toCommandLine().trim()),
                  ),
                ),
              ),
            ],
          ),
          if (primaryActionLabel != null && onPrimaryAction != null) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: onPrimaryAction,
                child: Text(primaryActionLabel!),
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _formatLastSeen(DateTime? value) {
    if (value == null) {
      return 'unknown';
    }
    return value.toLocal().toString();
  }

  String _formatMetadataLabel(String key) {
    return key
        .replaceAllMapped(
          RegExp(r'(?<!^)([A-Z])'),
          (match) => ' ${match.group(1)}',
        )
        .replaceAll('_', ' ')
        .split(' ')
        .where((part) => part.isNotEmpty)
        .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
        .join(' ');
  }

  String _formatMetadataValue(Object? value) {
    if (value == null) {
      return 'unknown';
    }
    if (value is String) {
      final trimmed = value.trim();
      return trimmed.isEmpty ? 'unknown' : trimmed;
    }
    if (value is List) {
      if (value.isEmpty) {
        return 'unknown';
      }
      return value.join(', ');
    }
    return value.toString();
  }
}

class _DetailSection extends StatelessWidget {
  const _DetailSection({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}
