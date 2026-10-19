import '../../shared/localized_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:local_auth/local_auth.dart';
import '../../app/state.dart';
import '../ocr/ocr_service.dart';
import '../../shared/components.dart';
import '../../shared/design.dart';
import 'exchange_rate_setting.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(preferencesProvider);
    return ListenableBuilder(
      listenable: prefs,
      builder: (_, _) => PageBody('Settings', [
        const SectionHeader(LText('Money')),
        _Group([
          _Row(
            icon: Icons.savings_outlined,
            title: 'Savings & companion',
            onTap: () => context.push('/companion'),
          ),
          _Row(
            icon: Icons.account_balance_outlined,
            title: 'Local account profiles',
            onTap: () => context.push('/accounts'),
          ),
          const ExpansionTile(
            leading: _IconTile(Icons.currency_exchange_rounded),
            title: LText('Exchange rate'),
            childrenPadding: EdgeInsets.fromLTRB(16, 0, 16, 12),
            children: [ExchangeRateSetting()],
          ),
        ]),
        const SectionHeader(LText('Preferences')),
        _Group([
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
            child: DropdownButtonFormField(
              isExpanded: true,
              initialValue: prefs.locale.languageCode,
              decoration: InputDecoration(
                labelText: tr(context, 'Language'),
                prefixIcon: const Icon(Icons.translate_rounded),
              ),
              items: const [
                DropdownMenuItem(value: 'en', child: LText('English')),
                DropdownMenuItem(value: 'my', child: LText('မြန်မာ')),
                DropdownMenuItem(value: 'th', child: LText('ไทย')),
              ],
              onChanged: (v) => prefs.update('language', v),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
            child: SegmentedButton<String>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(
                  value: 'system',
                  icon: Icon(Icons.brightness_auto_rounded),
                  label: LText('Auto'),
                ),
                ButtonSegment(
                  value: 'light',
                  icon: Icon(Icons.light_mode_rounded),
                  label: LText('Light'),
                ),
                ButtonSegment(
                  value: 'dark',
                  icon: Icon(Icons.dark_mode_rounded),
                  label: LText('Dark'),
                ),
              ],
              selected: {prefs.theme.name},
              onSelectionChanged: (v) => prefs.update('theme', v.first),
            ),
          ),
          _Row(
            icon: Icons.photo_library_outlined,
            title: 'Photo access & automatic scanning',
            onTap: () => context.go('/scan'),
          ),
        ]),
        const SectionHeader(LText('Privacy & data')),
        _Group([
          SwitchListTile(
            secondary: const _IconTile(Icons.fingerprint_rounded),
            title: const LText('App lock'),
            subtitle: const LText(
              'Biometric or device authentication on return',
            ),
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
          _Row(
            icon: Icons.lock_outline_rounded,
            title: 'Encrypted local backup',
            subtitle: 'Export or restore a password-protected file',
            onTap: () => _backup(context, ref),
          ),
          _Row(
            icon: Icons.storage_outlined,
            title: 'Manage data',
            subtitle: 'Delete income, expenses, receipts or savings separately',
            onTap: () => context.push('/manage-data'),
          ),
        ]),
        const SizedBox(height: 10),
        _Group([
          ListTile(
            leading: const _IconTile(
              Icons.delete_outline_rounded,
              color: Palette.expense,
            ),
            title: const LText(
              'Delete all local data',
              style: TextStyle(color: Palette.expense),
            ),
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
                await OnDeviceOCR.channel.invokeMethod('cleanup', {
                  'all': true,
                });
                scanner.resetAfterDeletion();
                await prefs.reset();
                ref.invalidate(accountsProvider);
                if (context.mounted) context.go('/welcome');
              }
            },
          ),
        ]),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.shield_outlined,
                size: 18,
                color: Palette.muted(context),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: LText(
                  'Your financial records are encrypted on this device. No cloud OCR, analytics upload, bank credentials, access to other apps’ notifications or SMS. Optional spending alerts stay on this device. Original photos stay in your library.\n\nReceipts are evidence for personal tracking. SlipTrack does not verify payments or bank balances.',
                  style: TextStyle(fontSize: 12, color: Palette.muted(context)),
                ),
              ),
            ],
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
                            await ref.read(preferencesProvider).reload();
                            await ref.read(coachProvider).evaluate();
                            ref.read(scannerProvider).paused = false;
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

class _Group extends StatelessWidget {
  const _Group(this.children);
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Surface(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Column(children: children),
  );
}

class _IconTile extends StatelessWidget {
  const _IconTile(this.icon, {this.color});
  final IconData icon;
  final Color? color;
  @override
  Widget build(BuildContext context) => Container(
    width: 36,
    height: 36,
    decoration: BoxDecoration(
      color: color?.withValues(alpha: .12) ?? Palette.soft(context),
      borderRadius: BorderRadius.circular(11),
    ),
    child: Icon(icon, size: 19, color: color ?? Palette.text(context)),
  );
}

class _Row extends StatelessWidget {
  const _Row({
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
  });
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => ListTile(
    leading: _IconTile(icon),
    title: LText(title, style: const TextStyle(fontWeight: FontWeight.w500)),
    subtitle: subtitle == null
        ? null
        : LText(
            subtitle!,
            style: TextStyle(fontSize: 12, color: Palette.muted(context)),
          ),
    trailing: Icon(Icons.chevron_right_rounded, color: Palette.muted(context)),
    onTap: onTap,
  );
}
