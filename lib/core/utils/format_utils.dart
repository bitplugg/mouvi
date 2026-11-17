import 'package:mouvi/core/models/vpn_config.dart';

/// Форматирование байт в человекочитаемый вид (двоичные единицы).
String formatBytes(int bytes) {
  if (bytes <= 0) {
    return '0 B';
  }
  const units = <String>['B', 'KB', 'MB', 'GB', 'TB'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit += 1;
  }
  if (unit == 0) {
    return '${value.round()} B';
  }
  final text = value >= 100
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(1);
  return '$text ${units[unit]}';
}

/// Возраст последнего рукопожатия.
///
/// Возвращает пару «число + единица», чтобы UI локализовал подпись сам.
/// `null` означает, что рукопожатия ещё не было.
({int value, String unit})? handshakeAge(DateTime now, int lastHandshakeMs) {
  if (lastHandshakeMs <= 0) {
    return null;
  }
  final time = DateTime.fromMillisecondsSinceEpoch(lastHandshakeMs);
  var seconds = now.difference(time).inSeconds;
  if (seconds < 0) {
    seconds = 0;
  }
  if (seconds < 60) {
    return (value: seconds, unit: 'seconds');
  }
  final minutes = seconds ~/ 60;
  if (minutes < 60) {
    return (value: minutes, unit: 'minutes');
  }
  final hours = minutes ~/ 60;
  if (hours < 24) {
    return (value: hours, unit: 'hours');
  }
  return (value: hours ~/ 24, unit: 'days');
}

/// Безопасное имя файла для экспорта конфигурации.
String exportFileName(String name, VpnProtocolType protocol) {
  final sanitized = name
      .trim()
      .replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_')
      .replaceAll(RegExp(r'^[._]+|[._]+$'), '');
  final base = sanitized.isEmpty ? 'mouvi-config' : sanitized;
  final extension = switch (protocol) {
    VpnProtocolType.wireguard || VpnProtocolType.amneziawg => 'conf',
    VpnProtocolType.openvpn => 'ovpn',
    VpnProtocolType.shadowsocks => 'json',
    _ => 'txt',
  };
  if (base.toLowerCase().endsWith('.$extension')) {
    return base;
  }
  return '$base.$extension';
}
