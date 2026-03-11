import 'dart:async';
import 'package:flutter/services.dart';
import '../core/constants.dart';
import '../core/vpn_status.dart';

/// Service that communicates with native Android VPN layer
/// via Platform Channels (MethodChannel + EventChannel).
class VpnPlatformService {
  static final VpnPlatformService _instance = VpnPlatformService._internal();
  factory VpnPlatformService() => _instance;
  VpnPlatformService._internal();

  final MethodChannel _methodChannel =
      const MethodChannel(AppConstants.vpnMethodChannel);
  final EventChannel _eventChannel =
      const EventChannel(AppConstants.vpnEventChannel);

  /// Stream of VPN status updates from native side
  Stream<VpnStatus> get statusStream {
    return _eventChannel.receiveBroadcastStream().map((event) {
      if (event is String) {
        return VpnStatus.fromString(event);
      }
      return VpnStatus.disconnected;
    });
  }

  /// Start VPN connection with sing-box config JSON
  /// [configJson] - sing-box configuration in JSON format
  Future<bool> startVpn(String configJson) async {
    try {
      final result = await _methodChannel.invokeMethod<bool>(
        'startVpn',
        {'config': configJson},
      );
      return result ?? false;
    } on PlatformException catch (e) {
      print('Failed to start VPN: ${e.message}');
      rethrow;
    }
  }

  /// Stop VPN connection
  Future<bool> stopVpn() async {
    try {
      final result = await _methodChannel.invokeMethod<bool>('stopVpn');
      return result ?? false;
    } on PlatformException catch (e) {
      print('Failed to stop VPN: ${e.message}');
      rethrow;
    }
  }

  /// Get current VPN status
  Future<VpnStatus> getStatus() async {
    try {
      final result = await _methodChannel.invokeMethod<String>('getStatus');
      return VpnStatus.fromString(result ?? 'disconnected');
    } on PlatformException catch (e) {
      print('Failed to get VPN status: ${e.message}');
      return VpnStatus.error;
    }
  }

  /// Request VPN permission from user (triggers system dialog)
  Future<bool> requestVpnPermission() async {
    try {
      final result =
          await _methodChannel.invokeMethod<bool>('requestVpnPermission');
      return result ?? false;
    } on PlatformException catch (e) {
      print('Failed to request VPN permission: ${e.message}');
      return false;
    }
  }
}
