import '../../shared/localized_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../app/state.dart';
import '../ocr/ocr_service.dart';
import '../../shared/components.dart';

class ScanScreen extends ConsumerWidget {
  const ScanScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scanner = ref.watch(scannerProvider);
    return ListenableBuilder(
      listenable: scanner,
      builder: (_, _) => PageBody('Scan center', [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.document_scanner_outlined, size: 48),
                const SizedBox(height: 20),
                Text(
                  scanner.status,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                LText('Photo permission: ${scanner.permissionState}'),
                const SizedBox(height: 12),
                if (scanner.busy) const LinearProgressIndicator(),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 24,
                  runSpacing: 12,
                  children: [
                    LText('${scanner.scanned} scanned'),
                    LText('${scanner.imported} to review'),
                    LText('${scanner.duplicates} duplicates'),
                    LText('${scanner.failed} failed'),
                    LText('${scanner.ignored} unrelated images skipped'),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: scanner.busy ? null : scanner.pick,
          icon: const Icon(Icons.photo_library_outlined),
          label: Text(ref.watch(preferencesProvider).text('Import Photos')),
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: scanner.busy ? null : () => scanner.catchUp(force: true),
          child: const LText('Scan Now'),
        ),
        OutlinedButton(
          onPressed: scanner.busy
              ? null
              : () async {
                  final date = await showDatePicker(
                    context: context,
                    initialDate: DateTime.now(),
                    firstDate: DateTime(2000),
                    lastDate: DateTime.now(),
                  );
                  if (date != null) {
                    await scanner.setSince(date);
                    await scanner.catchUp(force: true, historical: true);
                  }
                },
          child: const LText('Import Historical Slips'),
        ),
        TextButton(
          onPressed: scanner.togglePause,
          child: Text(scanner.paused ? 'Resume scanning' : 'Pause scanning'),
        ),
        TextButton(
          onPressed: scanner.busy ? null : scanner.retry,
          child: const LText('Retry failed items'),
        ),
        if (scanner.permissionState == 'limited')
          TextButton(
            onPressed: () => OnDeviceOCR.channel.invokeMethod('limitedPicker'),
            child: const LText('Manage selected photos'),
          ),
        FutureBuilder(
          future: ref.read(repositoryProvider).queueItems('failed'),
          builder: (_, snapshot) => Column(
            children: [
              for (final item in (snapshot.data ?? []).where(
                (j) => j['state'] == 'failed',
              ))
                Card(
                  child: ListTile(
                    title: const LText('Image could not be read'),
                    subtitle: const LText(
                      'You can enter transaction details yourself.',
                    ),
                    trailing: TextButton(
                      onPressed: scanner.busy
                          ? null
                          : () => scanner.reviewFailed(item),
                      child: const LText('Review manually'),
                    ),
                  ),
                ),
            ],
          ),
        ),
        FutureBuilder(
          future: ref.read(repositoryProvider).settings(),
          builder: (_, snapshot) => Column(
            children: [
              SwitchListTile(
                title: const LText('Automatic scanning'),
                subtitle: const LText(
                  'Request library access; system restrictions apply',
                ),
                value: snapshot.data?['automatic'] == true,
                onChanged: (v) async {
                  await scanner.setAutomatic(v);
                },
              ),
              ListTile(
                title: const LText('Scan photos created after'),
                subtitle: Text(
                  snapshot.data?['since'] == null
                      ? 'All accessible photos'
                      : DateFormat.yMMMd().format(
                          DateTime.fromMillisecondsSinceEpoch(
                            snapshot.data!['since'],
                          ),
                        ),
                ),
                trailing: const Icon(Icons.calendar_today_outlined),
                onTap: () async {
                  final date = await showDatePicker(
                    context: context,
                    initialDate: DateTime.now(),
                    firstDate: DateTime(2000),
                    lastDate: DateTime.now(),
                  );
                  if (date != null) {
                    await scanner.setSince(date);
                  }
                },
              ),
              ListTile(
                title: const LText('Last completed discovery'),
                subtitle: Text(
                  snapshot.data?['checkpoint'] == null
                      ? 'No scan yet'
                      : DateFormat.yMMMd().add_Hm().format(
                          DateTime.fromMillisecondsSinceEpoch(
                            snapshot.data!['checkpoint'],
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
        const Card(
          child: Padding(
            padding: EdgeInsets.all(20),
            child: LText(
              'OCR stays on your device. Android currently recognizes Latin script. Thai/Myanmar fields may require manual entry. iOS languages depend on the installed Vision runtime. Every imported transaction awaits your review.',
            ),
          ),
        ),
      ]),
    );
  }
}
