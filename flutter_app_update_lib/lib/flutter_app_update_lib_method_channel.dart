import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'flutter_app_update_lib_platform_interface.dart';

/// An implementation of [FlutterAppUpdateLibPlatform] that uses method channels.
class MethodChannelFlutterAppUpdateLib extends FlutterAppUpdateLibPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('flutter_app_update_lib');

  @override
  Future<String?> getPlatformVersion() async {
    final version = await methodChannel.invokeMethod<String>(
      'getPlatformVersion',
    );
    return version;
  }
}
