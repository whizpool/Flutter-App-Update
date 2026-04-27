import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

// --- Android Play In-App Update (Play Core) ---

/// Status of a download/install.
///
/// For more information, see its corresponding page on
/// [Android Developers](https://developer.android.com/reference/com/google/android/play/core/install/model/InstallStatus.html).
enum InstallStatus {
  unknown,
  pending,
  downloading,
  installing,
  installed,
  failed,
  canceled,
  downloaded,
}

/// Availability of an update for the requested package.
///
/// For more information, see its corresponding page on
/// [Android Developers](https://developer.android.com/reference/com/google/android/play/core/install/model/UpdateAvailability.html).
enum UpdateAvailability {
  unknown,
  updateNotAvailable,
  updateAvailable,
  developerTriggeredUpdateInProgress,
}

enum AppUpdateResult {
  /// The user has accepted the update. For immediate updates, you might not
  /// receive this callback because the update should already be completed by
  /// Google Play by the time the control is given back to your app.
  success,

  /// The user has denied or cancelled the update.
  userDeniedUpdate,

  /// Some other error prevented either the user from providing consent or the
  /// update to proceed.
  inAppUpdateFailed,
}

/// Contains information about the availability and progress of an app
/// update.
///
/// For more information, see its corresponding page on
/// [Android Developers](https://developer.android.com/reference/com/google/android/play/core/appupdate/AppUpdateInfo).
class AppUpdateInfo {
  /// Whether an update is available for the app.
  ///
  /// This is a value from [UpdateAvailability].
  final UpdateAvailability updateAvailability;

  /// Whether an immediate update is allowed.
  final bool immediateUpdateAllowed;

  /// determine the reason why an update cannot be started
  final List<int>? immediateAllowedPreconditions;

  /// Whether a flexible update is allowed.
  final bool flexibleUpdateAllowed;

  /// determine the reason why an update cannot be started
  final List<int>? flexibleAllowedPreconditions;

  /// The version code of the update.
  ///
  /// If no updates are available, this is an arbitrary value.
  final int? availableVersionCode;

  /// The progress status of the update.
  ///
  /// This value is defined only if [updateAvailability] is
  /// [UpdateAvailability.developerTriggeredUpdateInProgress].
  ///
  /// This is a value from [InstallStatus].
  final InstallStatus installStatus;

  /// The package name for the app to be updated.
  final String packageName;

  /// The in-app update priority for this update, as defined by the developer
  /// in the Google Play Developer API.
  ///
  /// This value is defined only if [updateAvailability] is
  /// [UpdateAvailability.updateAvailable].
  final int updatePriority;

  /// The number of days since the Google Play Store app on the user's device
  /// has learnt about an available update.
  ///
  /// If update is not available, or if staleness information is unavailable,
  /// this is null.
  final int? clientVersionStalenessDays;

  AppUpdateInfo({
    required this.updateAvailability,
    required this.immediateUpdateAllowed,
    required this.immediateAllowedPreconditions,
    required this.flexibleUpdateAllowed,
    required this.flexibleAllowedPreconditions,
    required this.availableVersionCode,
    required this.installStatus,
    required this.packageName,
    required this.clientVersionStalenessDays,
    required this.updatePriority,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppUpdateInfo &&
          runtimeType == other.runtimeType &&
          updateAvailability == other.updateAvailability &&
          immediateUpdateAllowed == other.immediateUpdateAllowed &&
          immediateAllowedPreconditions == other.immediateAllowedPreconditions &&
          flexibleUpdateAllowed == other.flexibleUpdateAllowed &&
          flexibleAllowedPreconditions == other.flexibleAllowedPreconditions &&
          availableVersionCode == other.availableVersionCode &&
          installStatus == other.installStatus &&
          packageName == other.packageName &&
          clientVersionStalenessDays == other.clientVersionStalenessDays &&
          updatePriority == other.updatePriority;

  @override
  int get hashCode =>
      updateAvailability.hashCode ^
      immediateUpdateAllowed.hashCode ^
      immediateAllowedPreconditions.hashCode ^
      flexibleUpdateAllowed.hashCode ^
      flexibleAllowedPreconditions.hashCode ^
      availableVersionCode.hashCode ^
      installStatus.hashCode ^
      packageName.hashCode ^
      clientVersionStalenessDays.hashCode ^
      updatePriority.hashCode;

  @override
  String toString() =>
      'InAppUpdateState{updateAvailability: $updateAvailability, '
      'immediateUpdateAllowed: $immediateUpdateAllowed, '
      'immediateAllowedPreconditions: $immediateAllowedPreconditions, '
      'flexibleUpdateAllowed: $flexibleUpdateAllowed, '
      'flexibleAllowedPreconditions: $flexibleAllowedPreconditions, '
      'availableVersionCode: $availableVersionCode, '
      'installStatus: $installStatus, '
      'packageName: $packageName, '
      'clientVersionStalenessDays: $clientVersionStalenessDays, '
      'updatePriority: $updatePriority}';
}

// --- Store version / dialog (iOS App Store & optional Android HTML) ---

abstract class VersionSource {
  Future<VersionStatus?> checkVersion(PackageInfo packageInfo);
}

class VersionStatus {
  VersionStatus({
    required this.localVersion,
    required this.storeVersion,
    required this.originalStoreVersion,
    required this.appStoreLink,
    this.releaseNotes,
  });

  final String localVersion;
  final String storeVersion;
  final String originalStoreVersion;
  final String appStoreLink;
  final String? releaseNotes;

  bool get canUpdate => _compareVersions(localVersion, storeVersion) < 0;

  static int _compareVersions(String current, String store) {
    final a = current.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final b = store.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final len = a.length > b.length ? a.length : b.length;
    for (var i = 0; i < len; i++) {
      final av = i < a.length ? a[i] : 0;
      final bv = i < b.length ? b[i] : 0;
      if (av != bv) return av.compareTo(bv);
    }
    return 0;
  }
}

enum LaunchModeVersion { normal, external }
enum AndroidUpdateFlow { immediate, flexible, immediateThenFlexible, none }

// --- Unified API ---

enum AppUpdatePlatform { android, ios, unsupported }

class AppUpdateCheckResult {
  const AppUpdateCheckResult({
    required this.platform,
    required this.hasUpdate,
    this.androidInfo,
    this.iosVersionStatus,
  });

  final AppUpdatePlatform platform;
  final bool hasUpdate;
  final AppUpdateInfo? androidInfo;
  final VersionStatus? iosVersionStatus;
}

/// Handles Android Play in-app updates and iOS App Store version checks
/// (plus optional store dialogs).
class AppUpdateLib {
  const AppUpdateLib({
    this.iOSAppStoreCountry,
    this.androidPlayStoreCountry,
    this.forceAppVersion,
    this.androidHtmlReleaseNotes = false,
    this.versionSource,
  });

  final String? iOSAppStoreCountry;
  final String? androidPlayStoreCountry;

  /// When set, [storeVersion] from the store is overridden (e.g. for testing).
  final String? forceAppVersion;

  final bool androidHtmlReleaseNotes;

  final VersionSource? versionSource;

  static const MethodChannel _androidChannel =
      MethodChannel('de.ffuf.in_app_update/methods');
  static const EventChannel _androidInstallListener =
      EventChannel('de.ffuf.in_app_update/stateEvents');

  static UpdateAvailability _mapUpdateAvailability(dynamic value) {
    switch (value) {
      case 1:
        return UpdateAvailability.updateNotAvailable;
      case 2:
        return UpdateAvailability.updateAvailable;
      case 3:
        return UpdateAvailability.developerTriggeredUpdateInProgress;
      default:
        return UpdateAvailability.unknown;
    }
  }

  static InstallStatus _mapInstallStatus(dynamic value) {
    switch (value) {
      case 1:
        return InstallStatus.pending;
      case 2:
        return InstallStatus.downloading;
      case 3:
        return InstallStatus.installing;
      case 4:
        return InstallStatus.installed;
      case 5:
        return InstallStatus.failed;
      case 6:
        return InstallStatus.canceled;
      case 11:
        return InstallStatus.downloaded;
      default:
        return InstallStatus.unknown;
    }
  }

  /// Android: call before starting an update. Returns Play [AppUpdateInfo].
  static Future<AppUpdateInfo> checkAndroidInAppUpdate() async {
    final result = await _androidChannel.invokeMethod('checkForUpdate');

    return AppUpdateInfo(
      updateAvailability: _mapUpdateAvailability(result['updateAvailability']),
      immediateUpdateAllowed: result['immediateAllowed'],
      immediateAllowedPreconditions: result['immediateAllowedPreconditions']
          ?.map<int>((e) => e as int)
          .toList(),
      flexibleUpdateAllowed: result['flexibleAllowed'],
      flexibleAllowedPreconditions: result['flexibleAllowedPreconditions']
          ?.map<int>((e) => e as int)
          .toList(),
      availableVersionCode: result['availableVersionCode'],
      installStatus: _mapInstallStatus(result['installStatus']),
      packageName: result['packageName'],
      clientVersionStalenessDays: result['clientVersionStalenessDays'],
      updatePriority: result['updatePriority'],
    );
  }

  static Stream<InstallStatus> get androidInstallUpdateListener {
    return _androidInstallListener.receiveBroadcastStream().cast<int>().map((int value) {
      switch (value) {
        case 0:
          return InstallStatus.unknown;
        case 1:
          return InstallStatus.pending;
        case 2:
          return InstallStatus.downloading;
        case 3:
          return InstallStatus.installing;
        case 4:
          return InstallStatus.installed;
        case 5:
          return InstallStatus.failed;
        case 6:
          return InstallStatus.canceled;
        case 11:
          return InstallStatus.downloaded;
        default:
          return InstallStatus.unknown;
      }
    });
  }

  /// Android: full-screen immediate update via Play.
  static Future<AppUpdateResult> performAndroidImmediateUpdate() async {
    try {
      await _androidChannel.invokeMethod('performImmediateUpdate');
      return AppUpdateResult.success;
    } on PlatformException catch (e) {
      if (e.code == 'USER_DENIED_UPDATE') {
        return AppUpdateResult.userDeniedUpdate;
      } else if (e.code == 'IN_APP_UPDATE_FAILED') {
        return AppUpdateResult.inAppUpdateFailed;
      }

      rethrow;
    }
  }

  /// Android: start flexible update download.
  static Future<AppUpdateResult> startAndroidFlexibleUpdate() async {
    try {
      await _androidChannel.invokeMethod('startFlexibleUpdate');
      return AppUpdateResult.success;
    } on PlatformException catch (e) {
      if (e.code == 'USER_DENIED_UPDATE') {
        return AppUpdateResult.userDeniedUpdate;
      } else if (e.code == 'IN_APP_UPDATE_FAILED') {
        return AppUpdateResult.inAppUpdateFailed;
      }

      rethrow;
    }
  }

  /// Android: install after [startAndroidFlexibleUpdate] completes.
  static Future<void> completeAndroidFlexibleUpdate() async {
    return await _androidChannel.invokeMethod('completeFlexibleUpdate');
  }

  /// Single entry for iOS and Android update checks.
  /// Set [showIosDialog] to true to display the update popup on iOS.
  Future<AppUpdateCheckResult> checkForUpdate({
    BuildContext? context,
    bool showIosDialog = false,
    bool showAndroidNativePopup = true,
    AndroidUpdateFlow androidUpdateFlow = AndroidUpdateFlow.flexible,
  }) async {
    debugPrint('[AppUpdateLib] checkForUpdate() started');

    if (Platform.isAndroid) {
      debugPrint('[AppUpdateLib][Android] Platform detected');
      try {
        final info = await checkAndroidInAppUpdate();
        final hasUpdate = info.updateAvailability == UpdateAvailability.updateAvailable;
        final canTriggerNativeFlow =
            info.updateAvailability == UpdateAvailability.updateAvailable ||
                info.updateAvailability ==
                    UpdateAvailability.developerTriggeredUpdateInProgress;
        debugPrint(
          '[AppUpdateLib][Android] updateAvailability=${info.updateAvailability} '
          'immediateAllowed=${info.immediateUpdateAllowed} '
          'flexibleAllowed=${info.flexibleUpdateAllowed} '
          'availableVersionCode=${info.availableVersionCode}',
        );

        if (showAndroidNativePopup &&
            canTriggerNativeFlow &&
            androidUpdateFlow != AndroidUpdateFlow.none) {
          AppUpdateResult? updateResult;
          if ((androidUpdateFlow == AndroidUpdateFlow.immediate ||
                  androidUpdateFlow == AndroidUpdateFlow.immediateThenFlexible) &&
              info.immediateUpdateAllowed) {
            debugPrint('[AppUpdateLib][Android] Starting immediate native update flow');
            updateResult = await performAndroidImmediateUpdate();
            debugPrint('[AppUpdateLib][Android] Immediate update result: $updateResult');
          }

          if (updateResult != AppUpdateResult.success &&
              (androidUpdateFlow == AndroidUpdateFlow.flexible ||
                  androidUpdateFlow == AndroidUpdateFlow.immediateThenFlexible) &&
              info.flexibleUpdateAllowed) {
            debugPrint('[AppUpdateLib][Android] Starting flexible native update flow');
            updateResult = await startAndroidFlexibleUpdate();
            debugPrint('[AppUpdateLib][Android] Flexible update result: $updateResult');
          }

          if (updateResult == null) {
            debugPrint(
              '[AppUpdateLib][Android] Native flow not started. '
              'immediateAllowed=${info.immediateUpdateAllowed}, '
              'flexibleAllowed=${info.flexibleUpdateAllowed}, '
              'requestedFlow=$androidUpdateFlow',
            );
          }
        } else {
          debugPrint(
            '[AppUpdateLib][Android] Native popup skipped. '
            'showAndroidNativePopup=$showAndroidNativePopup, '
            'canTriggerNativeFlow=$canTriggerNativeFlow, '
            'androidUpdateFlow=$androidUpdateFlow, '
            'updateAvailability=${info.updateAvailability}',
          );
        }

        return AppUpdateCheckResult(
          platform: AppUpdatePlatform.android,
          hasUpdate: hasUpdate,
          androidInfo: info,
        );
      } on MissingPluginException catch (e, st) {
        debugPrint('[AppUpdateLib][Android] Missing plugin: $e');
        if (showAndroidNativePopup) {
          debugPrint(
            '[AppUpdateLib][Android] Native-only mode enabled. Skipping Flutter dialog fallback.',
          );
          return const AppUpdateCheckResult(
            platform: AppUpdatePlatform.android,
            hasUpdate: false,
          );
        }
        debugPrint('[AppUpdateLib][Android] Falling back to pure Flutter store-version dialog.');
        debugPrint('[AppUpdateLib][Android] StackTrace: $st');
        return await _checkAndroidStoreVersionFallback(
          context: context,
          showDialog: showAndroidNativePopup,
        );
      } on PlatformException catch (e, st) {
        debugPrint(
          '[AppUpdateLib][Android] PlatformException code=${e.code} message=${e.message}',
        );
        debugPrint('[AppUpdateLib][Android] StackTrace: $st');
        if (showAndroidNativePopup) {
          debugPrint(
            '[AppUpdateLib][Android] Native-only mode enabled. Skipping Flutter dialog fallback.',
          );
          return const AppUpdateCheckResult(
            platform: AppUpdatePlatform.android,
            hasUpdate: false,
          );
        }
        return await _checkAndroidStoreVersionFallback(
          context: context,
          showDialog: showAndroidNativePopup,
        );
      } catch (e, st) {
        debugPrint('[AppUpdateLib][Android] Unexpected error: $e');
        debugPrint('[AppUpdateLib][Android] StackTrace: $st');
        if (showAndroidNativePopup) {
          debugPrint(
            '[AppUpdateLib][Android] Native-only mode enabled. Skipping Flutter dialog fallback.',
          );
          return const AppUpdateCheckResult(
            platform: AppUpdatePlatform.android,
            hasUpdate: false,
          );
        }
        return await _checkAndroidStoreVersionFallback(
          context: context,
          showDialog: showAndroidNativePopup,
        );
      }
    }

    if (Platform.isIOS) {
      debugPrint('[AppUpdateLib][iOS] Platform detected');
      debugPrint(
        'iOSAppStoreCountry=$iOSAppStoreCountry, '
        'androidPlayStoreCountry=$androidPlayStoreCountry',
      );

      try {
        debugPrint('[AppUpdateLib][iOS] Calling getVersionStatus()');
        final status = await getVersionStatus();
        debugPrint('[AppUpdateLib][iOS] getVersionStatus() completed');

        if (status == null) {
          debugPrint(
            '[AppUpdateLib][iOS] VersionStatus is null. '
            'Store lookup failed or app not found in App Store.',
          );
          return const AppUpdateCheckResult(
            platform: AppUpdatePlatform.ios,
            hasUpdate: false,
          );
        }

        debugPrint(
          '[AppUpdateLib][iOS] localVersion=${status.localVersion}, '
          'storeVersion=${status.storeVersion}, '
          'originalStoreVersion=${status.originalStoreVersion}',
        );
        debugPrint(
          '[AppUpdateLib][iOS] appStoreLink=${status.appStoreLink}, '
          'hasUpdate=${status.canUpdate}',
        );

        if (showIosDialog && status.canUpdate && context != null) {
          debugPrint('[AppUpdateLib][iOS] Showing update dialog');
          await showUpdateDialog(
            context: context,
            versionStatus: status,
          );
        }

        return AppUpdateCheckResult(
          platform: AppUpdatePlatform.ios,
          hasUpdate: status.canUpdate,
          iosVersionStatus: status,
        );
      } catch (e, st) {
        debugPrint('[AppUpdateLib][iOS] Error during version check: $e');
        debugPrint('[AppUpdateLib][iOS] StackTrace: $st');
        return const AppUpdateCheckResult(
          platform: AppUpdatePlatform.ios,
          hasUpdate: false,
        );
      }
    }

    debugPrint('[AppUpdateLib] Unsupported platform: ${Platform.operatingSystem}');
    return const AppUpdateCheckResult(
      platform: AppUpdatePlatform.unsupported,
      hasUpdate: false,
    );
  }

  Future<AppUpdateCheckResult> _checkAndroidStoreVersionFallback({
    required BuildContext? context,
    required bool showDialog,
  }) async {
    try {
      final status = await getVersionStatus();
      if (status == null) {
        debugPrint('[AppUpdateLib][Android] Fallback store lookup returned null');
        return const AppUpdateCheckResult(
          platform: AppUpdatePlatform.android,
          hasUpdate: false,
        );
      }

      debugPrint(
        '[AppUpdateLib][Android] Fallback localVersion=${status.localVersion}, '
        'storeVersion=${status.storeVersion}, hasUpdate=${status.canUpdate}',
      );

      if (showDialog && status.canUpdate && context != null && context.mounted) {
        await showUpdateDialog(
          context: context,
          versionStatus: status,
        );
      }

      return AppUpdateCheckResult(
        platform: AppUpdatePlatform.android,
        hasUpdate: status.canUpdate,
      );
    } catch (e, st) {
      debugPrint('[AppUpdateLib][Android] Fallback failed: $e');
      debugPrint('[AppUpdateLib][Android] Fallback stackTrace: $st');
      return const AppUpdateCheckResult(
        platform: AppUpdatePlatform.android,
        hasUpdate: false,
      );
    }
  }

  /// Checks the store and shows a platform alert if an update exists.
  Future<void> showAlertIfNecessary({
    required BuildContext context,
    LaunchModeVersion launchModeVersion = LaunchModeVersion.normal,
  }) async {
    final VersionStatus? versionStatus = await getVersionStatus();

    if (versionStatus != null && versionStatus.canUpdate) {
      if (context.mounted) {
        await showUpdateDialog(
          context: context,
          versionStatus: versionStatus,
          launchModeVersion: launchModeVersion,
        );
      }
    }
  }

  /// Store version status (iOS via iTunes lookup, Android via Play HTML when
  /// not using a custom [versionSource]).
  Future<VersionStatus?> getVersionStatus() async {
    final packageInfo = await PackageInfo.fromPlatform();

    if (versionSource != null) {
      return versionSource!.checkVersion(packageInfo);
    }

    if (Platform.isIOS) {
      return _getiOSStoreVersion(packageInfo);
    } else if (Platform.isAndroid) {
      return _getAndroidStoreVersion(packageInfo);
    } else {
      debugPrint(
        'The target platform "${Platform.operatingSystem}" is not yet supported by this package.',
      );
      return null;
    }
  }

  String _getCleanVersion(String version) =>
      RegExp(r'\d+(\.\d+)?(\.\d+)?').stringMatch(version) ?? '0.0.0';

  Future<VersionStatus?> _getiOSStoreVersion(PackageInfo packageInfo) async {
    final id = packageInfo.packageName;

    final Map<String, dynamic> parameters = {};

    if (id.contains('.')) {
      parameters['bundleId'] = id;
    } else {
      parameters['id'] = id;
    }

    parameters['timestamp'] = DateTime.now().millisecondsSinceEpoch.toString();

    if (iOSAppStoreCountry != null) {
      parameters.addAll({"country": iOSAppStoreCountry!});
    }
    final uri = Uri.https("itunes.apple.com", "/lookup", parameters);
    http.Response response;
    try {
      response = await http.get(uri);
    } catch (e) {
      debugPrint('Failed to query iOS App Store\n$e');
      return null;
    }

    if (response.statusCode != 200) {
      debugPrint('Failed to query iOS App Store');
      return null;
    }
    final jsonObj = json.decode(response.body);
    final List results = jsonObj['results'];
    if (results.isEmpty) {
      debugPrint('Can\'t find an app in the App Store with the id: $id');
      return null;
    }
    return VersionStatus(
      localVersion: _getCleanVersion(packageInfo.version),
      storeVersion: _getCleanVersion(forceAppVersion ?? jsonObj['results'][0]['version']),
      originalStoreVersion: forceAppVersion ?? jsonObj['results'][0]['version'],
      appStoreLink: jsonObj['results'][0]['trackViewUrl'],
      releaseNotes: jsonObj['results'][0]['releaseNotes'],
    );
  }

  Future<VersionStatus?> _getAndroidStoreVersion(PackageInfo packageInfo) async {
    final id = packageInfo.packageName;

    final uri = Uri.https("play.google.com", "/store/apps/details", {
      "id": id.toString(),
      "hl": androidPlayStoreCountry ?? "en_US",
      "timestamp": DateTime.now().millisecondsSinceEpoch.toString(),
    });
    http.Response response;
    try {
      response = await http.get(uri);
    } catch (e) {
      debugPrint('Failed to query Google Play Store\n$e');
      return null;
    }

    if (response.statusCode != 200) {
      throw Exception("Invalid response code: ${response.statusCode}");
    }
    final regexp = RegExp(r'\[\[\[\"(\d+\.\d+(\.[a-z]+)?(\.([^"]|\\")*)?)\"\]\]');
    final storeVersion = regexp.firstMatch(response.body)?.group(1);

    final regexpRelease = RegExp(r'\[(null,)\[(null,)\"((\.[a-z]+)?(([^"]|\\")*)?)\"\]\]');

    final expRemoveSc = RegExp(
      r"\\u003c[A-Za-z]{1,10}\\u003e",
      multiLine: true,
      caseSensitive: true,
    );

    final expRemoveQuote = RegExp(r"\\u0026quot;", multiLine: true, caseSensitive: true);

    final releaseNotes = regexpRelease.firstMatch(response.body)?.group(3);

    return VersionStatus(
      localVersion: _getCleanVersion(packageInfo.version),
      storeVersion: _getCleanVersion(forceAppVersion ?? storeVersion ?? ""),
      originalStoreVersion: forceAppVersion ?? storeVersion ?? "",
      appStoreLink: uri.toString(),
      releaseNotes: androidHtmlReleaseNotes
          ? _parseUnicodeToString(releaseNotes)
          : releaseNotes?.replaceAll(expRemoveSc, '').replaceAll(expRemoveQuote, '"'),
    );
  }

  void _updateActionFunc({
    required String appStoreLink,
    required bool allowDismissal,
    required BuildContext context,
    LaunchMode launchMode = LaunchMode.platformDefault,
  }) {
    launchAppStore(appStoreLink, launchMode: launchMode);
    if (allowDismissal) {
      Navigator.of(context, rootNavigator: true).pop();
    }
  }

  Future<void> showUpdateDialog({
    required BuildContext context,
    required VersionStatus versionStatus,
    String dialogTitle = 'Update Available',
    String? dialogText,
    String updateButtonText = 'Update',
    bool allowDismissal = true,
    String dismissButtonText = 'Maybe Later',
    VoidCallback? dismissAction,
    LaunchModeVersion launchModeVersion = LaunchModeVersion.normal,
  }) async {
    final dialogTitleWidget = Text(dialogTitle);
    final dialogTextWidget = Text(
      dialogText ??
          'You can now update this app from ${versionStatus.localVersion} to ${versionStatus.storeVersion}',
    );

    final launchMode = launchModeVersion == LaunchModeVersion.external
        ? LaunchMode.externalApplication
        : LaunchMode.platformDefault;

    final updateButtonTextWidget = Text(updateButtonText);

    final List<Widget> actions = [
      Platform.isAndroid
          ? TextButton(
              onPressed: () => _updateActionFunc(
                allowDismissal: allowDismissal,
                context: context,
                appStoreLink: versionStatus.appStoreLink,
                launchMode: launchMode,
              ),
              child: updateButtonTextWidget,
            )
          : CupertinoDialogAction(
              onPressed: () => _updateActionFunc(
                allowDismissal: allowDismissal,
                context: context,
                appStoreLink: versionStatus.appStoreLink,
                launchMode: launchMode,
              ),
              child: updateButtonTextWidget,
            ),
    ];

    if (allowDismissal) {
      final dismissButtonTextWidget = Text(dismissButtonText);
      dismissAction = dismissAction ?? () => Navigator.of(context, rootNavigator: true).pop();
      actions.add(
        Platform.isAndroid
            ? TextButton(onPressed: dismissAction, child: dismissButtonTextWidget)
            : CupertinoDialogAction(onPressed: dismissAction, child: dismissButtonTextWidget),
      );
    }

    await showDialog(
      context: context,
      barrierDismissible: allowDismissal,
      builder: (BuildContext context) {
        return PopScope(
          canPop: allowDismissal,
          child: Platform.isAndroid
              ? AlertDialog(title: dialogTitleWidget, content: dialogTextWidget, actions: actions)
              : CupertinoAlertDialog(
                  title: dialogTitleWidget,
                  content: dialogTextWidget,
                  actions: actions,
                ),
        );
      },
    );
  }

  Future<void> launchAppStore(
    String appStoreLink, {
    LaunchMode launchMode = LaunchMode.platformDefault,
  }) async {
    if (await canLaunchUrl(Uri.parse(appStoreLink))) {
      await launchUrl(Uri.parse(appStoreLink), mode: launchMode);
    } else {
      throw 'Could not launch appStoreLink';
    }
  }

  String? _parseUnicodeToString(String? release) {
    try {
      if (release == null || release.isEmpty) return release;

      final re = RegExp(
        r'(%(?<asciiValue>[0-9A-Fa-f]{2}))'
        r'|(\\u(?<codePoint>[0-9A-Fa-f]{4}))'
        r'|.',
      );

      final matches = re.allMatches(release);
      final codePoints = <int>[];
      for (final match in matches) {
        final codePoint = match.namedGroup('asciiValue') ?? match.namedGroup('codePoint');
        if (codePoint != null) {
          codePoints.add(int.parse(codePoint, radix: 16));
        } else {
          codePoints.addAll(match.group(0)!.runes);
        }
      }
      final decoded = String.fromCharCodes(codePoints);
      return decoded;
    } catch (e) {
      return release;
    }
  }
}
