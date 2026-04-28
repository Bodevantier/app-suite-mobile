import 'models/n2k_fast_packet_message.dart';
import 'models/n2k_frame.dart';

class N2kFastPacketReassembler {
  final Map<String, _FastPacketSession> _sessions = <String, _FastPacketSession>{};

  void reset() {
    _sessions.clear();
  }

  N2kFastPacketMessage? consume(N2kFrame frame) {
    if (frame.dlc < 2) {
      return null;
    }

    final sequenceId = (frame.data[0] >> 5) & 0x07;
    final frameIndex = frame.data[0] & 0x1f;
    final key = '${frame.sourceAddress}:${frame.pgn}:$sequenceId';

    if (frameIndex == 0) {
      final expectedLength = frame.data[1];
      if (expectedLength <= 0 || expectedLength > 223) {
        _sessions.remove(key);
        return null;
      }

      final session = _FastPacketSession(expectedLength: expectedLength);
      session.nextFrameIndex = 1;
      final initialPayload = frame.data.sublist(2, frame.dlc);
      session.bytes.addAll(initialPayload.take(expectedLength));
      _sessions[key] = session;
      if (session.bytes.length >= expectedLength) {
        _sessions.remove(key);
        return N2kFastPacketMessage(
          pgn: frame.pgn,
          source: frame.sourceAddress,
          payload: List<int>.unmodifiable(session.bytes.take(expectedLength)),
        );
      }
      return null;
    }

    final session = _sessions[key];
    if (session == null || session.nextFrameIndex != frameIndex) {
      _sessions.remove(key);
      return null;
    }

    session.nextFrameIndex++;
    final remaining = session.expectedLength - session.bytes.length;
    session.bytes.addAll(frame.data.sublist(1, frame.dlc).take(remaining));

    if (session.bytes.length >= session.expectedLength) {
      _sessions.remove(key);
      return N2kFastPacketMessage(
        pgn: frame.pgn,
        source: frame.sourceAddress,
        payload: List<int>.unmodifiable(session.bytes.take(session.expectedLength)),
      );
    }

    return null;
  }
}

class _FastPacketSession {
  _FastPacketSession({required this.expectedLength});

  final int expectedLength;
  final List<int> bytes = <int>[];
  int nextFrameIndex = 0;
}