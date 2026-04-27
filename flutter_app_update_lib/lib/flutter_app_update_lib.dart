
import 'flutter_app_update_lib_platform_interface.dart';
export 'src/app_update_lib.dart';

class FlutterAppUpdateLib {
  Future<String?> getPlatformVersion() {
    return FlutterAppUpdateLibPlatform.instance.getPlatformVersion();
  }
}
