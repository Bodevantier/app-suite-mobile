import 'dart:convert';

class GatewayProtocolFixtures {
  static const List<String> eventLines = <String>[
    'device_list request sent id=12',
    'device_list begin id=12 count=3',
    'device_list device 1/3 src=45',
    'device_list device 2/3 src=18',
    'device_list complete id=12 devices=3',
  ];

  static const List<String> snapshotTextLines = <String>[
    'device_list snapshot id=12 complete=1 expected=3 received=3 malformed=1 completed=4 dropped=0 unknown=2 parse=1',
    'device src=49 gateway=1 online=1 hasAddressClaim=1 name=SDolve NMEA2000 Bluetooth model=ESP32_SPI_N2K_BLE manufacturer=SDolve category=gateway',
    'device src=45 online=1 hasAddressClaim=1 hasProductInfo=1 hasConfigurationInfo=1 product=2001 mfg=275 name=WS310 model=Wind Sensor Mk2 manufacturer=Airmar serial=SN-45 sw=1.2.3 install1=Masthead Wind install2=Port tx=1 rx=1 deviceClass=25 deviceFunction=130 nameValue=1122334455667788',
    'device src=18 online=0 hasAddressClaim=1 hasProductInfo=1 product=310 mfg=128 name=AP200 model=Autopilot Mk2 manufacturer=HelmWorks tx=0 rx=1 deviceClass=40 deviceFunction=150 nameValue=AABBCCDDEEFF0011',
  ];

  static List<List<int>> get chunkedTextNotificationChunks {
    final bytes = utf8.encode('${snapshotTextLines.join('\n')}\n');
    return <List<int>>[
      bytes.sublist(0, 48),
      bytes.sublist(48, 132),
      bytes.sublist(132, 244),
      bytes.sublist(244),
    ];
  }
}