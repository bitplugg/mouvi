import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mouvi/core/localization/app_localizations.dart';
import 'package:mouvi/state/diagnostics_provider.dart';
import 'package:mouvi/state/locale_provider.dart';

class DiagnosticsScreen extends ConsumerWidget {
  const DiagnosticsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeProvider);
    final localizations = AppLocalizations(locale);
    final events = ref.watch(diagnosticsProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(localizations.t('diagnostics')),
        actions: [
          IconButton(
            icon: const Icon(Icons.copy_all),
            tooltip: localizations.t('copyLogs'),
            onPressed: events.isEmpty
                ? null
                : () async {
                    final text = ref
                        .read(diagnosticsProvider.notifier)
                        .exportText();
                    await Clipboard.setData(ClipboardData(text: text));
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(localizations.t('logsCopied'))),
                    );
                  },
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: localizations.t('clearLogs'),
            onPressed: events.isEmpty
                ? null
                : () => ref.read(diagnosticsProvider.notifier).clear(),
          ),
        ],
      ),
      body: events.isEmpty
          ? Center(child: Text(localizations.t('noLogs')))
          : ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: events.length,
              separatorBuilder: (context, index) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final event = events[events.length - 1 - index];
                final color = switch (event.level) {
                  'error' => Theme.of(context).colorScheme.error,
                  'warn' => Colors.orange,
                  _ => Theme.of(context).colorScheme.primary,
                };
                return ListTile(
                  dense: true,
                  leading: Icon(
                    event.level == 'error'
                        ? Icons.error_outline
                        : event.level == 'warn'
                        ? Icons.warning_amber_outlined
                        : Icons.info_outline,
                    color: color,
                    size: 20,
                  ),
                  title: Text(
                    event.message,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  subtitle: Text(
                    [
                      event.time.toLocal().toString().split('.').first,
                      if (event.details != null && event.details!.isNotEmpty)
                        event.details!,
                    ].join('\n'),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  isThreeLine:
                      event.details != null && event.details!.isNotEmpty,
                );
              },
            ),
    );
  }
}
