import 'package:ble_application/ble/framing/newline_message_framer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reassembles fragmented newline-delimited messages', () {
    final framer = NewlineMessageFramer();

    expect(framer.addChunk('device_list begin'.codeUnits), isEmpty);
    expect(framer.addChunk(' id=12 count=7\npartial'.codeUnits), <String>[
      'device_list begin id=12 count=7',
    ]);
    expect(framer.pendingText, 'partial');
    expect(framer.addChunk(' line\n'.codeUnits), <String>['partial line']);
    expect(framer.pendingText, isEmpty);
  });

  test('ignores empty lines and trims carriage returns', () {
    final framer = NewlineMessageFramer();

    final messages = framer.addChunk('one\r\n\n two \n'.codeUnits);

    expect(messages, <String>['one', 'two']);
  });
}