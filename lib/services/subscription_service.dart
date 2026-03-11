import 'dart:convert';
import 'package:http/http.dart' as http;
import '../core/constants.dart';

/// Service to fetch and parse Marzban subscription URL
/// and convert configs to sing-box JSON format.
class SubscriptionService {
  /// Fetch subscription configs from Marzban subscription URL.
  /// Marzban returns base64-encoded config lines.
  /// Returns list of raw config URIs (e.g., vless://..., vmess://...).
  Future<List<String>> fetchConfigs(String subscriptionUrl) async {
    print('DEBUG: Fetching configs from: $subscriptionUrl');
    try {
      final response = await http.get(
        Uri.parse(subscriptionUrl),
        headers: {
          'User-Agent': 'RedStarVPN/1.0',
          'Accept': '*/*',
        },
      ).timeout(
        const Duration(seconds: AppConstants.httpTimeoutSeconds),
      );

      if (response.statusCode != 200) {
        print('DEBUG: HTTP Error ${response.statusCode}: ${response.body}');
        throw SubscriptionException(
          'Ошибка при загрузке конфигов: HTTP ${response.statusCode}',
        );
      }

      final body = response.body.trim();

      // Marzban subscription returns base64-encoded config lines
      String decoded;
      try {
        decoded = utf8.decode(base64Decode(body));
      } catch (_) {
        // Might not be base64, try raw text
        decoded = body;
      }

      final configs = decoded
          .split('\n')
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty)
          .toList();

      if (configs.isEmpty) {
        throw SubscriptionException('Не найдено конфигов в подписке');
      }

      return configs;
    } on SubscriptionException {
      rethrow;
    } catch (e) {
      throw SubscriptionException('Ошибка подключения: $e');
    }
  }

  /// Convert a VLESS URI to sing-box outbound JSON config.
  /// Format: vless://UUID@HOST:PORT?params#REMARK
  Map<String, dynamic> parseVlessUri(String uri) {
    if (!uri.startsWith('vless://')) {
      throw SubscriptionException('Неподдерживаемый протокол: ${uri.split("://").first}');
    }

    final withoutScheme = uri.substring('vless://'.length);

    // Split remark (#...)
    final hashIndex = withoutScheme.lastIndexOf('#');
    final mainPart =
        hashIndex >= 0 ? withoutScheme.substring(0, hashIndex) : withoutScheme;

    // Split params (?...)
    final questionIndex = mainPart.indexOf('?');
    final params = questionIndex >= 0
        ? Uri.splitQueryString(mainPart.substring(questionIndex + 1))
        : <String, String>{};
    final authHost =
        questionIndex >= 0 ? mainPart.substring(0, questionIndex) : mainPart;

    // Parse uuid@host:port
    final atIndex = authHost.indexOf('@');
    if (atIndex < 0) {
      throw SubscriptionException('Неверный формат VLESS URI');
    }

    final uuid = authHost.substring(0, atIndex);
    final hostPort = authHost.substring(atIndex + 1);

    String host;
    int port;

    // Handle IPv6 addresses [::1]:443
    if (hostPort.startsWith('[')) {
      final closeBracket = hostPort.indexOf(']');
      host = hostPort.substring(1, closeBracket);
      final portStr = hostPort.substring(closeBracket + 2);
      port = int.tryParse(portStr) ?? 443;
    } else {
      final colonIndex = hostPort.lastIndexOf(':');
      host = hostPort.substring(0, colonIndex);
      port = int.tryParse(hostPort.substring(colonIndex + 1)) ?? 443;
    }

    final security = params['security'] ?? 'none';
    final type = params['type'] ?? 'tcp';
    final flow = params['flow'] ?? '';
    final sni = params['sni'] ?? host;
    final fp = params['fp'] ?? 'chrome';
    final alpn = params['alpn'] ?? '';
    final pbk = params['pbk'] ?? '';
    final sid = params['sid'] ?? '';

    // Build sing-box outbound config
    final outbound = <String, dynamic>{
      'type': 'vless',
      'tag': 'proxy',
      'server': host,
      'server_port': port,
      'uuid': uuid,
    };

    // Add flow (e.g., xtls-rprx-vision)
    if (flow.isNotEmpty) {
      outbound['flow'] = flow;
    }

    // Transport settings
    if (type != 'tcp' || type == 'ws' || type == 'grpc' || type == 'h2') {
      outbound['transport'] = {
        'type': type,
        if (params['path'] != null) 'path': params['path'],
        if (params['host'] != null) 'headers': {'Host': params['host']},
        if (type == 'grpc' && params['serviceName'] != null)
          'service_name': params['serviceName'],
      };
    }

    // TLS settings
    if (security == 'tls' || security == 'reality') {
      final tls = <String, dynamic>{
        'enabled': true,
        'server_name': sni,
      };

      if (alpn.isNotEmpty) {
        tls['alpn'] = alpn.split(',');
      }

      if (security == 'reality') {
        tls['reality'] = {
          'enabled': true,
          'public_key': pbk,
          if (sid.isNotEmpty) 'short_id': sid,
        };
      }

      final utls = <String, dynamic>{
        'enabled': true,
        'fingerprint': fp,
      };
      tls['utls'] = utls;

      outbound['tls'] = tls;
    }

    return outbound;
  }

  /// Generate a complete sing-box config JSON from a list of config URIs.
  /// Takes the first available VLESS config.
  String generateSingBoxConfig(List<String> configUris) {
    // Find first VLESS config
    final vlessUri = configUris.firstWhere(
      (uri) => uri.startsWith('vless://'),
      orElse: () => '',
    );

    if (vlessUri.isEmpty) {
      throw SubscriptionException(
          'Не найден VLESS конфиг в подписке. Доступные протоколы: '
          '${configUris.map((u) => u.split("://").first).toSet().join(", ")}');
    }

    final outbound = parseVlessUri(vlessUri);

    final config = {
      'log': {
        'level': 'info',
        'timestamp': true,
      },
      'dns': {
        'servers': [
          {
            'tag': 'proxy-dns',
            'address': 'https://1.1.1.1/dns-query',
            'detour': 'proxy',
          },
          {
            'tag': 'direct-dns',
            'address': 'https://1.1.1.1/dns-query',
            'detour': 'direct',
          },
        ],
        'rules': [
          {
            'outbound': ['any'],
            'server': 'direct-dns',
          },
        ],
        'strategy': 'prefer_ipv4',
      },
      'inbounds': [
        {
          'type': 'tun',
          'tag': 'tun-in',
          'interface_name': 'tun0',
          'inet4_address': '172.19.0.1/30',
          'auto_route': true,
          'strict_route': true,
          'stack': 'system',
          'sniff': true,
          'sniff_override_destination': true,
        },
      ],
      'outbounds': [
        outbound,
        {
          'type': 'direct',
          'tag': 'direct',
        },
        {
          'type': 'dns',
          'tag': 'dns-out',
        },
        {
          'type': 'block',
          'tag': 'block',
        },
      ],
      'route': {
        'rules': [
          {
            'protocol': 'dns',
            'outbound': 'dns-out',
          },
          {
            'geoip': ['private'],
            'outbound': 'direct',
          },
        ],
        'auto_detect_interface': true,
        'final': 'proxy',
      },
    };

    return jsonEncode(config);
  }
}

/// Custom exception for subscription errors
class SubscriptionException implements Exception {
  final String message;
  SubscriptionException(this.message);

  @override
  String toString() => message;
}
