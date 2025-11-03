// Flutter web plugin registrant file.
//
// Generated file. Do not edit.
//

// @dart = 2.13
// ignore_for_file: type=lint

import 'package:app_links_web/app_links_web.dart';
import 'package:camera_web/camera_web.dart';
import 'package:connectivity_plus/src/connectivity_plus_web.dart';
import 'package:desktop_drop/desktop_drop_web.dart';
import 'package:device_info_plus/src/device_info_plus_web.dart';
import 'package:file_picker/_internal/file_picker_web.dart';
import 'package:file_selector_web/file_selector_web.dart';
import 'package:image_picker_for_web/image_picker_for_web.dart';
import 'package:mobile_scanner/mobile_scanner_web_plugin.dart';
import 'package:printing/printing_web.dart';
import 'package:shared_preferences_web/shared_preferences_web.dart';
import 'package:super_native_extensions/super_native_extensions_web.dart';
import 'package:url_launcher_web/url_launcher_web.dart';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';

void registerPlugins([final Registrar? pluginRegistrar]) {
  final Registrar registrar = pluginRegistrar ?? webPluginRegistrar;
  AppLinksPluginWeb.registerWith(registrar);
  CameraPlugin.registerWith(registrar);
  ConnectivityPlusWebPlugin.registerWith(registrar);
  DesktopDropWeb.registerWith(registrar);
  DeviceInfoPlusWebPlugin.registerWith(registrar);
  FilePickerWeb.registerWith(registrar);
  FileSelectorWeb.registerWith(registrar);
  ImagePickerPlugin.registerWith(registrar);
  MobileScannerWebPlugin.registerWith(registrar);
  PrintingPlugin.registerWith(registrar);
  SharedPreferencesPlugin.registerWith(registrar);
  SuperNativeExtensionsWeb.registerWith(registrar);
  UrlLauncherPlugin.registerWith(registrar);
  registrar.registerMessageHandler();
}
