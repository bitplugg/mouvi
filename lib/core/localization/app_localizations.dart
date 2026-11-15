import 'package:flutter/material.dart';

class AppLocalizations {
  AppLocalizations(this.locale);

  final Locale locale;

  static const List<Locale> supportedLocales = [Locale('ru'), Locale('en')];

  static const Map<String, Map<String, String>> _strings = {
    'en': {
      'appTitle': 'Mouvi',
      'home': 'Home',
      'servers': 'Servers',
      'settings': 'Settings',
      'connect': 'Connect',
      'disconnect': 'Disconnect',
      'connecting': 'Connecting',
      'connected': 'Connected',
      'disconnected': 'Disconnected',
      'addServer': 'Add server',
      'importConfig': 'Import config',
      'pasteConfig': 'Paste config',
      'save': 'Save',
      'cancel': 'Cancel',
      'language': 'Language',
      'russian': 'Русский',
      'english': 'English',
      'appearance': 'Appearance',
      'theme': 'Theme',
      'themeSystem': 'System',
      'themeLight': 'Light',
      'themeDark': 'Dark',
      'protection': 'Protection',
      'notifications': 'Notifications',
      'killSwitch': 'Kill switch',
      'splitTunneling': 'Split tunneling',
      'dnsProtection': 'DNS protection',
      'noServersTitle': 'No servers yet',
      'noServersHint': 'Add a config to start',
      'uptime': 'Uptime',
      'configAdded': 'Config added',
      'serverName': 'Server name',
      'protocolWireguard': 'WireGuard / AmneziaWG',
      'protocolOpenvpn': 'OpenVPN',
      'protocolShadowsocks': 'Shadowsocks',
      'protocolVless': 'VLESS',
      'protocolTrojan': 'Trojan',
      'protocolUnknown': 'Unknown',
    },
    'ru': {
      'appTitle': 'Mouvi',
      'home': 'Главная',
      'servers': 'Серверы',
      'settings': 'Настройки',
      'connect': 'Подключить',
      'disconnect': 'Отключить',
      'connecting': 'Подключение',
      'connected': 'Подключено',
      'disconnected': 'Отключено',
      'addServer': 'Добавить сервер',
      'importConfig': 'Импортировать конфиг',
      'pasteConfig': 'Вставить конфиг',
      'save': 'Сохранить',
      'cancel': 'Отмена',
      'language': 'Язык',
      'russian': 'Русский',
      'english': 'English',
      'appearance': 'Оформление',
      'theme': 'Тема',
      'themeSystem': 'Системная',
      'themeLight': 'Светлая',
      'themeDark': 'Тёмная',
      'protection': 'Защита',
      'notifications': 'Уведомления',
      'killSwitch': 'Блокировка',
      'splitTunneling': 'Split tunneling',
      'dnsProtection': 'Защита DNS',
      'noServersTitle': 'Серверов пока нет',
      'noServersHint': 'Добавьте конфиг, чтобы начать',
      'uptime': 'Время работы',
      'configAdded': 'Конфиг добавлен',
      'serverName': 'Имя сервера',
      'protocolWireguard': 'WireGuard / AmneziaWG',
      'protocolOpenvpn': 'OpenVPN',
      'protocolShadowsocks': 'Shadowsocks',
      'protocolVless': 'VLESS',
      'protocolTrojan': 'Trojan',
      'protocolUnknown': 'Неизвестно',
    },
  };

  String t(String key) {
    final localizedStrings = _strings[locale.languageCode];
    if (localizedStrings != null && localizedStrings.containsKey(key)) {
      return localizedStrings[key] ?? key;
    }
    return _strings['en']?[key] ?? key;
  }
}
