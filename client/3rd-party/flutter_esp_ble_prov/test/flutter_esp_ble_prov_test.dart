import 'package:flutter_esp_ble_prov/flutter_esp_ble_prov.dart';
import 'package:flutter_esp_ble_prov/src/flutter_esp_ble_prov_method_channel.dart';
import 'package:flutter_esp_ble_prov/src/flutter_esp_ble_prov_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockFlutterEspBleProvPlatform
    with MockPlatformInterfaceMixin
    implements FlutterEspBleProvPlatform {
  @override
  Future<String?> getPlatformVersion() => Future.value('42');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  final FlutterEspBleProvPlatform initialPlatform =
      FlutterEspBleProvPlatform.instance;

  test('$MethodChannelFlutterEspBleProv is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelFlutterEspBleProv>());
  });

  test('default security level is compatible with legacy ESP firmware', () {
    expect(FlutterEspBleProv().defaultSecurity, SecurityLevel.unsecure);
  });

  test('getPlatformVersion', () async {
    FlutterEspBleProv flutterEspBleProvPlugin = FlutterEspBleProv();
    MockFlutterEspBleProvPlatform fakePlatform =
        MockFlutterEspBleProvPlatform();
    FlutterEspBleProvPlatform.instance = fakePlatform;

    expect(await flutterEspBleProvPlugin.getPlatformVersion(), '42');
  });
}
