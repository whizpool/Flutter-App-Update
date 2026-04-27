# flutter_app_update_lib

A Flutter plugin to handle in-app updates for both Android and iOS using platform-specific approaches.

# Getting Started

This project is a starting point for a Flutter  
[plug-in package](https://flutter.dev/to/develop-plugins),  
a specialized package that includes platform-specific implementation code for  
Android and/or iOS.

For help getting started with Flutter development, view the  
[online documentation](https://docs.flutter.dev), which offers tutorials,  
samples, guidance on mobile development, and a full API reference.

# Features

## Android
- Uses native Android methods to check for app updates
- Displays the official Play Store update dialog
- Provides smooth in-app update experience

## iOS
- Displays a custom update dialog within the app
- Redirects users to the App Store for updating

# Usage

## Initialization

```dart
final appUpdateLib = AppUpdateLib(
  iOSAppStoreCountry: 'us',
  androidPlayStoreCountry: 'en_US',
);
```

## Check for Update

```dart
await appUpdateLib.checkForUpdate(
  context: context,
  showIosDialog: true,
);
```

# Platform Behavior

## Android
- Uses native Android in-app update API
- Shows official Play Store update dialog

## iOS
- No native in-app update API available
- Custom dialog is shown within the app
- Redirects to App Store

# Notes

- Android requires Play Store deployment
- iOS depends on App Store availability
- Test on real devices for proper behavior  
