import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'flutter_app_update_lib_method_channel.dart';

abstract class FlutterAppUpdateLibPlatform extends PlatformInterface {
  /// Constructs a FlutterAppUpdateLibPlatform.
  FlutterAppUpdateLibPlatform() : super(token: _token);

  static final Object _token = Object();

  static FlutterAppUpdateLibPlatform _instance = MethodChannelFlutterAppUpdateLib();

  /// The default instance of [FlutterAppUpdateLibPlatform] to use.
  ///
  /// Defaults to [MethodChannelFlutterAppUpdateLib].
  static FlutterAppUpdateLibPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [FlutterAppUpdateLibPlatform] when
  /// they register themselves.
  static set instance(FlutterAppUpdateLibPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<String?> getPlatformVersion() {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }
}
