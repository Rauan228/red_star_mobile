import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/constants.dart';
import '../core/vpn_status.dart';
import '../providers/vpn_provider.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  final _urlController = TextEditingController(
    text: AppConstants.defaultSubscriptionUrl,
  );
  bool _showUrlInput = false;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _urlController.dispose();
    super.dispose();
  }

  void _onStatusChanged(VpnStatus status) {
    if (status == VpnStatus.connected) {
      _pulseController.repeat(reverse: true);
    } else {
      _pulseController.stop();
      _pulseController.reset();
    }
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours.toString().padLeft(2, '0');
    final minutes = (duration.inMinutes % 60).toString().padLeft(2, '0');
    final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
    return '$hours:$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final vpnState = ref.watch(vpnProvider);

    // Listen for status changes to control animation
    ref.listen<VpnState>(vpnProvider, (previous, next) {
      if (previous?.status != next.status) {
        _onStatusChanged(next.status);
      }
    });

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF0A0E21),
              Color(0xFF141832),
              Color(0xFF0A0E21),
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              _buildHeader(),
              Expanded(
                child: Center(
                  child: _buildMainContent(vpnState),
                ),
              ),
              _buildFooter(vpnState),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Row(
        children: [
          // Logo icon
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFE53935), Color(0xFFFF5252)],
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.star_rounded,
              color: Colors.white,
              size: 24,
            ),
          ),
          const SizedBox(width: 12),
          const Text(
            'Red Star VPN',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          const Spacer(),
          // Settings / URL toggle
          IconButton(
            onPressed: () {
              setState(() {
                _showUrlInput = !_showUrlInput;
              });
            },
            icon: Icon(
              _showUrlInput ? Icons.close : Icons.settings,
              color: Colors.white54,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMainContent(VpnState vpnState) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // URL input (toggled by settings)
        if (_showUrlInput) _buildUrlInput(),

        // Status text
        _buildStatusIndicator(vpnState.status),
        const SizedBox(height: 12),

        // Connection duration
        if (vpnState.status.isConnected && vpnState.connectedDuration != null)
          Text(
            _formatDuration(vpnState.connectedDuration!),
            style: const TextStyle(
              fontSize: 36,
              fontWeight: FontWeight.w300,
              color: Colors.white70,
              letterSpacing: 4,
            ),
          ),

        const SizedBox(height: 48),

        // Connect button
        _buildConnectButton(vpnState),

        const SizedBox(height: 32),

        // Error message
        if (vpnState.errorMessage != null) _buildErrorCard(vpnState.errorMessage!),
      ],
    );
  }

  Widget _buildUrlInput() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF1A1F36),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white10),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: TextField(
          controller: _urlController,
          style: const TextStyle(color: Colors.white70, fontSize: 13),
          decoration: const InputDecoration(
            hintText: 'https://domain.com/sub/TOKEN',
            hintStyle: TextStyle(color: Colors.white24),
            border: InputBorder.none,
            prefixIcon: Icon(Icons.link, color: Colors.white24, size: 20),
            contentPadding: EdgeInsets.symmetric(vertical: 12),
          ),
        ),
      ),
    );
  }

  Widget _buildStatusIndicator(VpnStatus status) {
    Color statusColor;
    IconData statusIcon;

    switch (status) {
      case VpnStatus.connected:
        statusColor = const Color(0xFF4CAF50);
        statusIcon = Icons.shield_rounded;
        break;
      case VpnStatus.connecting:
      case VpnStatus.disconnecting:
        statusColor = const Color(0xFFFFA726);
        statusIcon = Icons.shield_outlined;
        break;
      case VpnStatus.error:
        statusColor = const Color(0xFFE53935);
        statusIcon = Icons.error_outline_rounded;
        break;
      case VpnStatus.disconnected:
        statusColor = Colors.white38;
        statusIcon = Icons.shield_outlined;
        break;
    }

    return Column(
      children: [
        Icon(
          statusIcon,
          size: 48,
          color: statusColor,
        ),
        const SizedBox(height: 12),
        Text(
          status.label,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: statusColor,
            letterSpacing: 1.2,
          ),
        ),
      ],
    );
  }

  Widget _buildConnectButton(VpnState vpnState) {
    final isConnected = vpnState.status.isConnected;
    final isTransitioning = vpnState.status.isTransitioning;

    return GestureDetector(
      onTap: isTransitioning
          ? null
          : () {
              final url = _urlController.text.trim();
              ref.read(vpnProvider.notifier).toggle(
                    subscriptionUrl: url.isNotEmpty ? url : null,
                  );
            },
      child: AnimatedBuilder(
        animation: _pulseAnimation,
        builder: (context, child) {
          final scale = isConnected ? _pulseAnimation.value : 1.0;
          return Transform.scale(
            scale: scale,
            child: child,
          );
        },
        child: Container(
          width: 160,
          height: 160,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: isConnected
                  ? [const Color(0xFF4CAF50), const Color(0xFF2E7D32)]
                  : isTransitioning
                      ? [const Color(0xFFFFA726), const Color(0xFFF57C00)]
                      : [const Color(0xFFE53935), const Color(0xFFB71C1C)],
            ),
            boxShadow: [
              BoxShadow(
                color: (isConnected
                        ? const Color(0xFF4CAF50)
                        : isTransitioning
                            ? const Color(0xFFFFA726)
                            : const Color(0xFFE53935))
                    .withOpacity(0.4),
                blurRadius: 30,
                spreadRadius: 5,
              ),
            ],
          ),
          child: Center(
            child: isTransitioning
                ? const SizedBox(
                    width: 40,
                    height: 40,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 3,
                    ),
                  )
                : Icon(
                    isConnected ? Icons.stop_rounded : Icons.power_settings_new,
                    size: 64,
                    color: Colors.white,
                  ),
          ),
        ),
      ),
    );
  }

  Widget _buildErrorCard(String errorMessage) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFFE53935).withOpacity(0.1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: const Color(0xFFE53935).withOpacity(0.3),
          ),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.error_outline,
              color: Color(0xFFE53935),
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                errorMessage,
                style: const TextStyle(
                  color: Color(0xFFEF9A9A),
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFooter(VpnState vpnState) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          if (vpnState.serverInfo != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1F36),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white10),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.dns_outlined,
                    size: 16,
                    color: Colors.white38,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    vpnState.serverInfo!,
                    style: const TextStyle(
                      color: Colors.white54,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 12),
          Text(
            'Red Star VPN • MVP',
            style: TextStyle(
              color: Colors.white.withOpacity(0.2),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

/// AnimatedBuilder — a simple wrapper so we can use AnimatedBuilder
/// with named parameters more cleanly. This is a standard Flutter
/// pattern already available as AnimatedBuilder in the framework.
