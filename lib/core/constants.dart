/// App-wide constants for Red Star VPN MVP
class AppConstants {
  AppConstants._();

  /// App display name
  static const String appName = 'Red Star VPN';

  /// Default subscription URL from Marzban
  /// Replace this with your actual Marzban subscription URL for testing.
  /// Format: https://your-domain.com/sub/USER_TOKEN
  static const String defaultSubscriptionUrl = 'https://dev-marz-instance.progon.pro/sub/dGVzdF84ODI3Nzk1NTJfbW1jZGg5bHIsMTc3MjY0OTA1Nwd8AMtfFo75#Subscription';

  /// Timeout for HTTP requests (seconds)
  static const int httpTimeoutSeconds = 15;

  /// Platform channel name for VPN bridge
  static const String vpnMethodChannel = 'com.redstarvpn.app/vpn';
  static const String vpnEventChannel = 'com.redstarvpn.app/vpn_status';

  /// IP check URL to verify VPN is working
  static const String ipCheckUrl = 'https://api.ipify.org?format=json';
}
