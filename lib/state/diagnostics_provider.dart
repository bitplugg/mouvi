import 'package:flutter_riverpod/flutter_riverpod.dart';

class DiagnosticEvent {
  const DiagnosticEvent({
    required this.time,
    required this.level,
    required this.message,
    this.details,
  });

  final DateTime time;
  final String level; // info, warn, error
  final String message;
  final String? details;

  String format() {
    final ts = time.toIso8601String();
    final base = '[$ts] [$level] $message';
    if (details == null || details!.isEmpty) {
      return base;
    }
    return '$base — $details';
  }
}

class DiagnosticsNotifier extends Notifier<List<DiagnosticEvent>> {
  static const int _maxEvents = 300;

  @override
  List<DiagnosticEvent> build() => const <DiagnosticEvent>[];

  void log(String level, String message, {String? details}) {
    final event = DiagnosticEvent(
      time: DateTime.now(),
      level: level,
      message: message,
      details: details,
    );
    final next = <DiagnosticEvent>[...state, event];
    if (next.length > _maxEvents) {
      next.removeRange(0, next.length - _maxEvents);
    }
    state = List<DiagnosticEvent>.unmodifiable(next);
  }

  void info(String message, {String? details}) =>
      log('info', message, details: details);
  void warn(String message, {String? details}) =>
      log('warn', message, details: details);
  void error(String message, {String? details}) =>
      log('error', message, details: details);

  void clear() {
    state = const <DiagnosticEvent>[];
  }

  String exportText() => state.map((e) => e.format()).join('\n');
}

final diagnosticsProvider =
    NotifierProvider<DiagnosticsNotifier, List<DiagnosticEvent>>(
      DiagnosticsNotifier.new,
    );
