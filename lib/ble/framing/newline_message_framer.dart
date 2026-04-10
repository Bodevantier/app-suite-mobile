import 'dart:convert';

class NewlineMessageFramer {
  final List<int> _buffer = <int>[];

  List<String> addChunk(List<int> bytes) {
    if (bytes.isEmpty) {
      return const <String>[];
    }

    _buffer.addAll(bytes);
    final messages = <String>[];

    while (true) {
      final newlineIndex = _buffer.indexOf(10);
      if (newlineIndex < 0) {
        break;
      }

      final lineBytes = _buffer.sublist(0, newlineIndex);
      _buffer.removeRange(0, newlineIndex + 1);

      if (lineBytes.isNotEmpty && lineBytes.last == 13) {
        lineBytes.removeLast();
      }

      final line = utf8.decode(lineBytes, allowMalformed: true).trim();
      if (line.isNotEmpty) {
        messages.add(line);
      }
    }

    return messages;
  }

  String get pendingText {
    return utf8.decode(_buffer, allowMalformed: true);
  }

  void clear() {
    _buffer.clear();
  }
}