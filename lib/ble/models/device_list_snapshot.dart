import '../../models/n2k_device_info.dart';

class DeviceListSnapshot {
  const DeviceListSnapshot({
    required this.type,
    required this.devices,
    required this.rawMessage,
    this.snapshotRequestId,
    this.snapshotInProgress = false,
    this.snapshotComplete = false,
    this.snapshotExpected,
    this.snapshotReceived,
    this.requestPending = false,
    this.pendingRequestId,
    this.malformedDeviceListMessages = 0,
    this.completedSnapshots = 0,
    this.droppedSnapshots = 0,
    this.unknownPacketTypes = 0,
    this.spiParseErrors = 0,
  });

  final String type;
  final int? snapshotRequestId;
  final bool snapshotInProgress;
  final bool snapshotComplete;
  final int? snapshotExpected;
  final int? snapshotReceived;
  final bool requestPending;
  final int? pendingRequestId;
  final int malformedDeviceListMessages;
  final int completedSnapshots;
  final int droppedSnapshots;
  final int unknownPacketTypes;
  final int spiParseErrors;
  final List<N2kDeviceInfo> devices;
  final String rawMessage;

  DeviceListSnapshot copyWith({
    String? type,
    int? snapshotRequestId,
    bool? snapshotInProgress,
    bool? snapshotComplete,
    int? snapshotExpected,
    int? snapshotReceived,
    bool? requestPending,
    int? pendingRequestId,
    int? malformedDeviceListMessages,
    int? completedSnapshots,
    int? droppedSnapshots,
    int? unknownPacketTypes,
    int? spiParseErrors,
    List<N2kDeviceInfo>? devices,
    String? rawMessage,
  }) {
    return DeviceListSnapshot(
      type: type ?? this.type,
      snapshotRequestId: snapshotRequestId ?? this.snapshotRequestId,
      snapshotInProgress: snapshotInProgress ?? this.snapshotInProgress,
      snapshotComplete: snapshotComplete ?? this.snapshotComplete,
      snapshotExpected: snapshotExpected ?? this.snapshotExpected,
      snapshotReceived: snapshotReceived ?? this.snapshotReceived,
      requestPending: requestPending ?? this.requestPending,
      pendingRequestId: pendingRequestId ?? this.pendingRequestId,
      malformedDeviceListMessages:
          malformedDeviceListMessages ?? this.malformedDeviceListMessages,
      completedSnapshots: completedSnapshots ?? this.completedSnapshots,
      droppedSnapshots: droppedSnapshots ?? this.droppedSnapshots,
      unknownPacketTypes: unknownPacketTypes ?? this.unknownPacketTypes,
      spiParseErrors: spiParseErrors ?? this.spiParseErrors,
      devices: devices ?? this.devices,
      rawMessage: rawMessage ?? this.rawMessage,
    );
  }
}