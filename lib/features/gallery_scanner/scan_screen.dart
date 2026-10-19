import '../../shared/localized_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:go_router/go_router.dart';
import '../../app/state.dart';
import '../../core/models.dart';
import '../../core/income_cycle.dart';
import '../ocr/ocr_service.dart';
import '../../shared/components.dart';
import '../../shared/design.dart';
import '../companion/companion_card.dart';
import '../companion/coach_models.dart';

class ScanScreen extends ConsumerStatefulWidget {
  const ScanScreen({super.key});
  @override
  ConsumerState<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends ConsumerState<ScanScreen> {
  Direction scanDirection = Direction.expense;
  Future<bool> chooseSource() async {
    try {
      final scanner = ref.read(scannerProvider);
      final gallery = scanner.gallery;
      if (gallery is! NativeGallery) return true;
      final permission = await gallery.permission(request: true);
      if (!['full', 'limited'].contains(permission)) {
        if (mounted) {
          message(
            context,
            'Allow photo access to scan an album or all photos.',
          );
        }
        return false;
      }
      final albums = await gallery.albums();
      if (!mounted) return false;
      final selected = await showModalBottomSheet<Map<String, dynamic>>(
        context: context,
        builder: (c) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              const ListTile(title: LText('Where are your slips?')),
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: const LText('All photos'),
                onTap: () => Navigator.pop(c, <String, dynamic>{
                  'id': null,
                  'name': 'All photos',
                }),
              ),
              for (final album in albums)
                ListTile(
                  leading: const Icon(Icons.folder_outlined),
                  title: Text(album['name']),
                  onTap: () => Navigator.pop(c, album),
                ),
            ],
          ),
        ),
      );
      if (selected == null) return false;
      await ref.read(repositoryProvider).patchSettings({
        'scanAlbumId': selected['id'],
        'scanAlbumName': selected['name'],
        'checkpoint': 0,
        'since': 0,
      });
      if (mounted) setState(() {});
      return true;
    } catch (_) {
      if (mounted) {
        message(
          context,
          'Could not open photo albums. Check photo access and try again.',
        );
      }
      return false;
    }
  }

  Future<void> importReceipts(bool needsIncome, {bool camera = false}) async {
    if (needsIncome) {
      context.push('/income');
      return;
    }
    final scanner = ref.read(scannerProvider);
    await scanner.pick(direction: scanDirection, camera: camera);
    final records = await ref.read(repositoryProvider).slips();
    final picked = records
        .where((s) => scanner.lastPickedReviewIds.contains(s.id))
        .toList();
    final waiting = picked
        .where((s) => s.review == ReviewStatus.pending)
        .toList();
    if (!mounted) return;
    if (waiting.length == 1) {
      context.push('/review/${waiting.single.id}');
    } else if (picked.isNotEmpty && waiting.isEmpty) {
      context.go('/');
      message(
        context,
        'Receipt saved. Income and expenses updated for the receipt date.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final scanner = ref.watch(scannerProvider);
    final all = ref.watch(slipsProvider).asData?.value ?? <Slip>[];
    final needsIncome = !IncomeCycle.fromIncome(
      DateTime.now(),
      all,
    ).hasIncome(all);
    final pending = all.where((s) => s.review == ReviewStatus.pending).toList();
    return ListenableBuilder(
      listenable: scanner,
      builder: (_, _) => PageBody('Scan center', [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Palette.brand, Palette.brandDeep],
            ),
            borderRadius: BorderRadius.circular(28),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  SizedBox(
                    width: 78,
                    height: 78,
                    child: Buddy(
                      mood: PetMood.happy,
                      progress: ref.watch(coachProvider).progress,
                      outfit: ref.watch(coachProvider).outfit,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        LText(
                          scanner.busy
                              ? 'Munching your slips…'
                              : 'Feed me your slips!',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 20,
                            letterSpacing: -.3,
                          ),
                        ),
                        const SizedBox(height: 4),
                        const LText(
                          'I read them on your phone and sort your money.',
                          style: TextStyle(color: Colors.white70, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    for (final d in [Direction.expense, Direction.income])
                      Expanded(
                        child: GestureDetector(
                          onTap: scanner.busy
                              ? null
                              : () => setState(() => scanDirection = d),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            decoration: BoxDecoration(
                              color: scanDirection == d
                                  ? Colors.white
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  d == Direction.expense
                                      ? Icons.north_east_rounded
                                      : Icons.south_west_rounded,
                                  size: 16,
                                  color: scanDirection == d
                                      ? Palette.brandDeep
                                      : Colors.white70,
                                ),
                                const SizedBox(width: 6),
                                LText(
                                  d == Direction.expense ? 'Expense' : 'Income',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: scanDirection == d
                                        ? Palette.brandDeep
                                        : Colors.white70,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              FilledButton.icon(
                key: const Key('pickReceipts'),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Palette.brandDeep,
                ),
                onPressed: scanner.busy
                    ? null
                    : () => importReceipts(needsIncome),
                icon: Icon(
                  needsIncome
                      ? Icons.account_balance_wallet_outlined
                      : Icons.add_photo_alternate_outlined,
                ),
                label: LText(
                  needsIncome
                      ? 'Add income to start scanning'
                      : 'Import Photos',
                ),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                key: const Key('cameraReceipt'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Colors.white38),
                ),
                onPressed: scanner.busy
                    ? null
                    : () => importReceipts(needsIncome, camera: true),
                icon: const Icon(Icons.photo_camera_outlined),
                label: const LText('Take a photo of a receipt'),
              ),
              const SizedBox(height: 4),
              TextButton.icon(
                style: TextButton.styleFrom(foregroundColor: Colors.white),
                onPressed: scanner.busy
                    ? null
                    : () async {
                        if (!await scanner.checkIncome()) {
                          if (context.mounted) context.push('/income');
                          return;
                        }
                        if (await chooseSource()) {
                          scanner.paused = false;
                          await scanner.catchUp(force: true, historical: true);
                        }
                      },
                icon: const Icon(Icons.auto_awesome_rounded, size: 18),
                label: const LText('Scan Now'),
              ),
            ],
          ),
        ),
        if (needsIncome)
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 12, 4, 0),
            child: LText(
              'Add income for this pay cycle before scanning receipts. Your salary date starts the period; your next salary closes it.',
              style: TextStyle(fontSize: 13, color: Palette.muted(context)),
            ),
          ),
        const SizedBox(height: 12),
        if (scanner.busy)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: const LinearProgressIndicator(minHeight: 8),
            ),
          ),
        Row(
          children: [
            for (final stat in [
              (
                '${scanner.imported}',
                'imported',
                Icons.check_rounded,
                Palette.income,
              ),
              (
                '${pending.length}',
                'to review',
                Icons.visibility_outlined,
                Palette.warn,
              ),
              (
                '${scanner.duplicates}',
                'duplicates',
                Icons.copy_rounded,
                const Color(0xff6d7fd6),
              ),
            ])
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      vertical: 14,
                      horizontal: 12,
                    ),
                    decoration: BoxDecoration(
                      color: stat.$4.withValues(alpha: .12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(stat.$3, size: 18, color: stat.$4),
                        const SizedBox(height: 8),
                        Text(
                          stat.$1,
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: Palette.text(context),
                          ),
                        ),
                        LText(
                          stat.$2,
                          style: TextStyle(
                            fontSize: 12,
                            color: Palette.muted(context),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
        SectionHeader(
          const LText('Ready to review'),
          action: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: pending.isEmpty
                  ? Palette.soft(context)
                  : Palette.warn.withValues(alpha: .15),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '${pending.length}',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: pending.isEmpty ? Palette.muted(context) : Palette.warn,
              ),
            ),
          ),
        ),
        if (pending.isEmpty)
          const Surface(
            child: EmptyState(
              'No receipts waiting',
              'Choose Income or Expense, then import a slip to update your balance.',
            ),
          )
        else
          Surface(
            padding: const EdgeInsets.all(4),
            child: Column(
              children: [
                for (final s in pending.take(8))
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SlipTile(s),
                      if (s.amountMinor == null ||
                          s.date == null ||
                          s.direction == Direction.unknown)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(68, 0, 12, 10),
                          child: Text(
                            [
                              if (s.amountMinor == null)
                                'Amount needs checking',
                              if (s.date == null) 'Date needs checking',
                              if (s.direction == Direction.unknown)
                                'Choose income or expense',
                            ].join(' · '),
                            style: const TextStyle(
                              fontSize: 12,
                              color: Palette.warn,
                            ),
                          ),
                        ),
                    ],
                  ),
              ],
            ),
          ),
        if (pending.length > 8)
          TextButton(
            onPressed: () => context.go('/transactions?review=true'),
            child: const LText('Review all receipts'),
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
                          : () async {
                              final id = await scanner.reviewFailed(item);
                              if (context.mounted && id != null) {
                                context.push('/review/$id');
                              }
                            },
                      child: const LText('Review manually'),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Surface(
          onTap: () => _openSettings(context),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Palette.soft(context),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.tune_rounded,
                  size: 20,
                  color: Palette.text(context),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const LText(
                      'Auto-scan & gallery',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    LText(
                      scanner.paused
                          ? 'Paused · tap to manage'
                          : 'Photo access, history and retries',
                      style: TextStyle(
                        fontSize: 12,
                        color: Palette.muted(context),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: Palette.muted(context)),
            ],
          ),
        ),
      ]),
    );
  }

  Future<void> _openSettings(BuildContext context) {
    final scanner = ref.read(scannerProvider);
    Future<DateTime?> pickDate() => showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (c) => ListenableBuilder(
        listenable: scanner,
        builder: (c, _) => FutureBuilder(
          future: ref.read(repositoryProvider).settings(),
          builder: (c, snapshot) {
            final settings = snapshot.data;
            return SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    LText(
                      'Auto-scan & gallery',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 4),
                    LText(
                      'Photo permission: ${scanner.permissionState}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Palette.muted(context),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Surface(
                      color: Palette.soft(context),
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Column(
                        children: [
                          SwitchListTile(
                            title: const LText('Automatic scanning'),
                            subtitle: const LText(
                              'Request library access; system restrictions apply',
                            ),
                            value: settings?['automatic'] == true,
                            onChanged: (v) async {
                              if (v && !await chooseSource()) return;
                              await scanner.setAutomatic(v);
                            },
                          ),
                          ListTile(
                            leading: const Icon(Icons.event_rounded),
                            title: const LText('Scan photos created after'),
                            subtitle: Text(
                              settings?['since'] == null
                                  ? tr(context, 'All accessible photos')
                                  : DateFormat.yMMMd().format(
                                      DateTime.fromMillisecondsSinceEpoch(
                                        settings!['since'],
                                      ),
                                    ),
                            ),
                            onTap: () async {
                              final date = await pickDate();
                              if (date != null) await scanner.setSince(date);
                            },
                          ),
                          ListTile(
                            leading: const Icon(Icons.history_rounded),
                            title: const LText('Last completed discovery'),
                            subtitle: Text(
                              settings?['checkpoint'] == null
                                  ? tr(context, 'No scan yet')
                                  : DateFormat.yMMMd().add_Hm().format(
                                      DateTime.fromMillisecondsSinceEpoch(
                                        settings!['checkpoint'],
                                      ),
                                    ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ActionChip(
                          avatar: const Icon(
                            Icons.history_edu_rounded,
                            size: 18,
                          ),
                          label: const LText('Import Historical Slips'),
                          onPressed: scanner.busy
                              ? null
                              : () async {
                                  final date = await pickDate();
                                  if (date != null) {
                                    await scanner.setSince(date);
                                    await scanner.catchUp(
                                      force: true,
                                      historical: true,
                                    );
                                  }
                                },
                        ),
                        ActionChip(
                          avatar: Icon(
                            scanner.paused
                                ? Icons.play_arrow_rounded
                                : Icons.pause_rounded,
                            size: 18,
                          ),
                          label: Text(
                            tr(
                              context,
                              scanner.paused
                                  ? 'Resume scanning'
                                  : 'Pause scanning',
                            ),
                          ),
                          onPressed: scanner.togglePause,
                        ),
                        if (scanner.failed > 0)
                          ActionChip(
                            avatar: const Icon(Icons.refresh_rounded, size: 18),
                            label: const LText('Retry failed items'),
                            onPressed: scanner.busy ? null : scanner.retry,
                          ),
                        if (scanner.permissionState == 'limited')
                          ActionChip(
                            avatar: const Icon(
                              Icons.photo_library_outlined,
                              size: 18,
                            ),
                            label: const LText('Manage selected photos'),
                            onPressed: () => OnDeviceOCR.channel.invokeMethod(
                              'limitedPicker',
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.shield_outlined,
                          size: 16,
                          color: Palette.muted(context),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: LText(
                            'OCR stays on your device. Android currently recognizes Latin script. Thai/Myanmar fields may require manual entry. iOS languages depend on the installed Vision runtime. Readable slips from photos, albums and sharing update totals automatically.',
                            style: TextStyle(
                              fontSize: 11,
                              color: Palette.muted(context),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
