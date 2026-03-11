import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/constants.dart';
import '../core/vpn_status.dart';
import '../services/vpn_service.dart';
import '../services/subscription_service.dart';

/// VPN connection state
class VpnState {
  final VpnStatus status;
  final String? errorMessage;
  final String? serverInfo;
  final String? configSource;
  final Duration? connectedDuration;

  const VpnState({
    this.status = VpnStatus.disconnected,
    this.errorMessage,
    this.serverInfo,
    this.configSource,
    this.connectedDuration,
  });

  VpnState copyWith({
    VpnStatus? status,
    String? errorMessage,
    String? serverInfo,
    String? configSource,
    Duration? connectedDuration,
    bool clearError = false,
  }) {
    return VpnState(
      status: status ?? this.status,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      serverInfo: serverInfo ?? this.serverInfo,
      configSource: configSource ?? this.configSource,
      connectedDuration: connectedDuration ?? this.connectedDuration,
    );
  }
}

/// VPN state notifier — orchestrates connect/disconnect flow
class VpnNotifier extends StateNotifier<VpnState> {
  final VpnPlatformService _vpnService;
  final SubscriptionService _subscriptionService;
  StreamSubscription? _statusSubscription;
  Timer? _durationTimer;
  DateTime? _connectedAt;

  VpnNotifier(this._vpnService, this._subscriptionService)
      : super(const VpnState()) {
    _listenToStatusUpdates();
  }

  void _listenToStatusUpdates() {
    _statusSubscription = _vpnService.statusStream.listen(
      (status) {
        if (status == VpnStatus.connected && !state.status.isConnected) {
          _connectedAt = DateTime.now();
          _startDurationTimer();
        }
        if (status == VpnStatus.disconnected) {
          _stopDurationTimer();
          _connectedAt = null;
        }
        state = state.copyWith(status: status, clearError: true);
      },
      onError: (error) {
        state = state.copyWith(
          status: VpnStatus.error,
          errorMessage: 'Ошибка соединения: $error',
        );
      },
    );
  }

  void _startDurationTimer() {
    _durationTimer?.cancel();
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_connectedAt != null) {
        state = state.copyWith(
          connectedDuration: DateTime.now().difference(_connectedAt!),
        );
      }
    });
  }

  void _stopDurationTimer() {
    _durationTimer?.cancel();
    _durationTimer = null;
    state = state.copyWith(
      connectedDuration: Duration.zero,
    );
  }

  /// Connect to VPN using subscription URL
  Future<void> connect({String? subscriptionUrl}) async {
    if (state.status == VpnStatus.connecting ||
        state.status == VpnStatus.connected) {
      return;
    }

    state = state.copyWith(
      status: VpnStatus.connecting,
      clearError: true,
    );

    try {
      final url = subscriptionUrl ?? AppConstants.defaultSubscriptionUrl;

      if (url.isEmpty) {
        throw SubscriptionException(
          'Не указана ссылка подписки. Введите URL в поле ввода.',
        );
      }

      // Step 1: Fetch configs from subscription URL
      state = state.copyWith(
        configSource: url,
      );

      final configs = await _subscriptionService.fetchConfigs(url);

      // Step 2: Generate sing-box config JSON
      final configJson = _subscriptionService.generateSingBoxConfig(configs);

      // Extract server info from first VLESS config
      final vlessUri = configs.firstWhere(
        (c) => c.startsWith('vless://'),
        orElse: () => '',
      );
      if (vlessUri.isNotEmpty) {
        final hashIdx = vlessUri.lastIndexOf('#');
        final remark = hashIdx >= 0
            ? Uri.decodeComponent(vlessUri.substring(hashIdx + 1))
            : 'VPN Server';
        state = state.copyWith(serverInfo: remark);
      }

      // Step 3: Start VPN via native bridge
      final started = await _vpnService.startVpn(configJson);

      if (!started) {
        state = state.copyWith(
          status: VpnStatus.error,
          errorMessage: 'Не удалось запустить VPN. Проверьте разрешения.',
        );
      }
    } on SubscriptionException catch (e) {
      state = state.copyWith(
        status: VpnStatus.error,
        errorMessage: e.message,
      );
    } catch (e) {
      state = state.copyWith(
        status: VpnStatus.error,
        errorMessage: 'Неизвестная ошибка: $e',
      );
    }
  }

  /// Disconnect from VPN
  Future<void> disconnect() async {
    if (state.status == VpnStatus.disconnected ||
        state.status == VpnStatus.disconnecting) {
      return;
    }

    state = state.copyWith(status: VpnStatus.disconnecting);

    try {
      await _vpnService.stopVpn();
      // Status will be updated via event stream
    } catch (e) {
      state = state.copyWith(
        status: VpnStatus.error,
        errorMessage: 'Ошибка при отключении: $e',
      );
    }
  }

  /// Toggle connection
  Future<void> toggle({String? subscriptionUrl}) async {
    if (state.status.isConnected) {
      await disconnect();
    } else if (state.status.isDisconnected || state.status == VpnStatus.error) {
      await connect(subscriptionUrl: subscriptionUrl);
    }
  }

  @override
  void dispose() {
    _statusSubscription?.cancel();
    _durationTimer?.cancel();
    super.dispose();
  }
}

/// Providers

final vpnPlatformServiceProvider = Provider<VpnPlatformService>((ref) {
  return VpnPlatformService();
});

final subscriptionServiceProvider = Provider<SubscriptionService>((ref) {
  return SubscriptionService();
});

final vpnProvider = StateNotifierProvider<VpnNotifier, VpnState>((ref) {
  final vpnService = ref.watch(vpnPlatformServiceProvider);
  final subscriptionService = ref.watch(subscriptionServiceProvider);
  return VpnNotifier(vpnService, subscriptionService);
});
