import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app_update_lib/flutter_app_update_lib.dart';
import 'package:flutter_app_update_lib/flutter_app_update_lib_platform_interface.dart';
import 'package:flutter_app_update_lib/flutter_app_update_lib_method_channel.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockFlutterAppUpdateLibPlatform
    with MockPlatformInterfaceMixin
    implements FlutterAppUpdateLibPlatform {
  @override
  Future<String?> getPlatformVersion() => Future.value('42');
}

void main() {
  final FlutterAppUpdateLibPlatform initialPlatform = FlutterAppUpdateLibPlatform.instance;

  test('$MethodChannelFlutterAppUpdateLib is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelFlutterAppUpdateLib>());
  });

  test('getPlatformVersion', () async {
    FlutterAppUpdateLib flutterAppUpdateLibPlugin = FlutterAppUpdateLib();
    MockFlutterAppUpdateLibPlatform fakePlatform = MockFlutterAppUpdateLibPlatform();
    FlutterAppUpdateLibPlatform.instance = fakePlatform;

    expect(await flutterAppUpdateLibPlugin.getPlatformVersion(), '42');
  });
}
