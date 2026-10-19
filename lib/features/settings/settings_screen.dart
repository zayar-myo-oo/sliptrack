import '../../shared/localized_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:local_auth/local_auth.dart';
import '../../app/state.dart';
import '../ocr/ocr_service.dart';
import '../../shared/components.dart';
import 'exchange_rate_setting.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(preferencesProvider);
    return ListenableBuilder(
      listenable: prefs,
      builder: (_, _) => PageBody('Settings', [
        ListTile(title: const LText('Savings & companion'), trailing: const Icon(Icons.chevron_right), onTap: () => context.push('/companion')),
        const ExchangeRateSetting(),
        ListTile(
          leading: const Icon(Icons.account_balance_outlined),
          title: const LText('Local account profiles'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.push('/accounts'),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField(
          isExpanded: true,
          initialValue: prefs.locale.languageCode,
          decoration: InputDecoration(labelText: tr(context, 'Language')),
          items: const [
            DropdownMenuItem(value: 'en', child: LText('English')),
            DropdownMenuItem(value: 'my', child: LText('မြန်မာ')),
            DropdownMenuItem(value: 'th', child: LText('ไทย')),
          ],
          onChanged: (v) => prefs.update('language', v),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField(
          isExpanded: true,
          initialValue: prefs.theme.name,
          decoration: InputDecoration(labelText: tr(context, 'Appearance')),
          items: ThemeMode.values
              .map((m) => DropdownMenuItem(value: m.name, child: Text(m.name)))
              .toList(),
          onChanged: (v) => prefs.update('theme', v),
        ),
        SwitchListTile(
          title: const LText('App lock'),
          subtitle: const LText('Biometric or device authentication on return'),
          value: prefs.values['lock'] == true,
          onChanged: (v) async {
            try {
              final ok = await LocalAuthentication().authenticate(
                localizedReason: 'Confirm SlipTrack app lock settings',
              );
              if (ok) await prefs.update('lock', v);
            } catch (_) {
              if (context.mounted) {
                message(
                  context,
                  'Device authentication is unavailable. Set up a screen lock first.',
                );
              }
            }
          },
        ),
        ListTile(
          title: const LText('Photo access & automatic scanning'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.go('/scan'),
        ),
        ListTile(
          title: const LText('Encrypted local backup'),
          subtitle: const LText('Export or restore a password-protected file'),
          trailing: const Icon(Icons.lock_outline),
          onTap: () => _backup(context, ref),
        ),
        ListTile(
          title: const LText('Delete all local data'),
          leading: const Icon(Icons.delete_outline),
          onTap: () async {
            final ok = await showDialog<bool>(
              context: context,
              builder: (c) => AlertDialog(
                title: const LText('Delete all SlipTrack data?'),
                content: const LText(
                  'This permanently removes local transactions, profiles and scanning history. Photos remain in your library.',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(c, false),
                    child: const LText('Cancel'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(c, true),
                    child: const LText('Delete all'),
                  ),
                ],
              ),
            );
            if (ok == true) {
              final scanner = ref.read(scannerProvider);
              try {
                await scanner.stop();
              } catch (_) {
                if (context.mounted) {
                  message(
                    context,
                    'The current image is still processing. Try deletion again after it finishes.',
                  );
                }
                return;
              }
              await ref.read(repositoryProvider).deleteAll();
              await OnDeviceOCR.channel.invokeMethod('cleanup', {'all': true});
              scanner.resetAfterDeletion();
              await prefs.reset();
              ref.invalidate(accountsProvider);
              if (context.mounted) context.go('/welcome');
            }
          },
        ),
        const SizedBox(height: 20),
        const Card(
          child: Padding(
            padding: EdgeInsets.all(20),
            child: LText(
              'Your financial records are encrypted on this device. No cloud OCR, analytics upload, bank credentials, notifications or SMS access. Original photos stay in your library.\n\nReceipts are evidence for personal tracking. SlipTrack does not verify payments or bank balances.',
            ),
          ),
        ),
      ]),
    );
  }

  Future<void> _backup(BuildContext context, WidgetRef ref) async {
    final password = TextEditingController();
    bool working = false;
    await showDialog<void>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: const LText('Encrypted local backup'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const LText(
                'Keep this password safe. Restoring requires an empty database. Choose a local file or destination using the system picker.',
              ),
              const SizedBox(height: 12),
              TextField(
                controller: password,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: tr(context, 'Password (12+ characters)'),
                ),
              ),
              if (working) const LinearProgressIndicator(),
            ],
          ),
          actions: [
            TextButton(
              onPressed: working ? null : () => Navigator.pop(c),
              child: const LText('Close'),
            ),
            for (final action in ['Restore', 'Export'])
              TextButton(
                onPressed: working
                    ? null
                    : () async {
                        if (password.text.length < 12) {
                          message(context, 'Use at least 12 characters');
                          return;
                        }
                        set(() => working = true);
                        try {
                          final repo = ref.read(repositoryProvider);
                          if (action == 'Export') {
                            final saved = await OnDeviceOCR.channel
                                .invokeMethod<bool>('backupExport', {
                                  'data': await repo.exportEncrypted(
                                    password.text,
                                  ),
                                });
                            if (saved != true) return;
                          } else {
                            final text = await OnDeviceOCR.channel
                                .invokeMethod<String>('backupImport');
                            if (text == null) return;
                            await ref.read(scannerProvider).stop();
                            await repo.importEncrypted(text, password.text);
                            ref.invalidate(accountsProvider);
                          }
                          if (context.mounted) {
                            message(context, '$action completed');
                          }
                        } catch (_) {
                          if (context.mounted) {
                            message(
                              context,
                              '$action failed. Check the password, chosen file and restore requirements.',
                            );
                          }
                        } finally {
                          if (c.mounted) set(() => working = false);
                        }
                      },
                child: Text(action),
              ),
          ],
        ),
      ),
    );
    password.dispose();
  }
}
