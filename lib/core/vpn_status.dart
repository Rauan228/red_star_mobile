/// VPN connection status enum
enum VpnStatus {
  disconnected,
  connecting,
  connected,
  disconnecting,
  error;

  /// Parse status string from native side
  static VpnStatus fromString(String status) {
    switch (status.toLowerCase()) {
      case 'connected':
        return VpnStatus.connected;
      case 'connecting':
        return VpnStatus.connecting;
      case 'disconnecting':
        return VpnStatus.disconnecting;
      case 'error':
        return VpnStatus.error;
      case 'disconnected':
      default:
        return VpnStatus.disconnected;
    }
  }

  /// Human-readable display label
  String get label {
    switch (this) {
      case VpnStatus.disconnected:
        return 'Отключено';
      case VpnStatus.connecting:
        return 'Подключение...';
      case VpnStatus.connected:
        return 'Подключено';
      case VpnStatus.disconnecting:
        return 'Отключение...';
      case VpnStatus.error:
        return 'Ошибка';
    }
  }

  bool get isConnected => this == VpnStatus.connected;
  bool get isDisconnected => this == VpnStatus.disconnected;
  bool get isTransitioning =>
      this == VpnStatus.connecting || this == VpnStatus.disconnecting;
}
