enum BleGatewayEventType {
  requestSent,
  begin,
  deviceProgress,
  complete,
  timeout,
  unknown,
}

class BleGatewayEvent {
  const BleGatewayEvent({
    required this.type,
    required this.rawLine,
    required this.occurredAt,
    this.requestId,
    this.count,
    this.index,
    this.total,
    this.src,
  });

  final BleGatewayEventType type;
  final String rawLine;
  final DateTime occurredAt;
  final int? requestId;
  final int? count;
  final int? index;
  final int? total;
  final int? src;
}