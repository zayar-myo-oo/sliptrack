import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../app/state.dart';
import '../../core/data_groups.dart';
import '../../core/income_cycle.dart';
import '../ocr/ocr_service.dart';
import '../../shared/components.dart';
import '../../shared/localized_text.dart';

class ManageDataScreen extends ConsumerStatefulWidget {
  const ManageDataScreen({super.key});
  @override
  ConsumerState<ManageDataScreen> createState() => _ManageDataState();
}

class _ManageDataState extends ConsumerState<ManageDataScreen> {
  final selected = <DataGroup>{};
  bool allDates = false, busy = false;
  DateTime anchor = DateTime.now();
  Future<void> remove() async {
    final cycle = IncomeCycle.fromIncome(
      anchor,
      ref.read(slipsProvider).asData?.value ?? [],
    );
    final groups = Set<DataGroup>.of(selected);
    final repo = ref.read(repositoryProvider);
    final counts = await repo.dataCounts(
      start: allDates ? null : cycle.start,
      end: allDates ? null : cycle.end,
    );
    if (!mounted) return;
    final total = groups.fold<int>(0, (sum, g) => sum + counts[g]!);
    if (total == 0) {
      message(context, 'No matching records to delete.');
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const LText('Delete selected data?'),
        content: Text(
          '${groups.map((g) => '${tr(context, g.label)}: ${counts[g]}').join('\n')}\n\n${tr(context, allDates ? 'All dates' : 'Selected pay cycle')}\n${tr(context, 'This cannot be undone. Original photos and other data stay unchanged.')}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const LText('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const LText('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => busy = true);
    final scanner = ref.read(scannerProvider);
    try {
      await scanner.stop(disableAutomatic: false);
      final sources = (await repo.slips())
          .where(
            (s) =>
                groups.any((g) => g.matches(s)) &&
                (allDates || cycle.contains(s.date)),
          )
          .map((s) => s.source)
          .where((source) => source.isNotEmpty)
          .toSet();
      final removed = await repo.deleteData(
        groups,
        start: allDates ? null : cycle.start,
        end: allDates ? null : cycle.end,
      );
      for (final source in sources) {
        try {
          await OnDeviceOCR.channel.invokeMethod('cleanup', {'id': source});
        } catch (_) {
          /* Deletion is durable; source-library photos are never deleted. */
        }
      }
      await ref.read(preferencesProvider).reload();
      await ref.read(coachProvider).evaluate();
      await scanner.checkIncome();
      if (mounted) {
        selected.clear();
        message(context, '$removed records deleted');
      }
    } catch (_) {
      if (mounted) message(context, 'Could not delete data. Please try again.');
    } finally {
      scanner.paused = false;
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cycle = IncomeCycle.fromIncome(
      anchor,
      ref.watch(slipsProvider).asData?.value ?? [],
    );
    return Scaffold(
      appBar: AppBar(title: const LText('Manage data')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const LText(
            'Choose what to delete. Nothing is removed until you confirm.',
          ),
          const SizedBox(height: 12),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, label: LText('Pay cycle')),
              ButtonSegment(value: true, label: LText('All dates')),
            ],
            selected: {allDates},
            onSelectionChanged: busy
                ? null
                : (v) => setState(() => allDates = v.single),
          ),
          if (!allDates)
            Row(
              children: [
                IconButton(
                  onPressed: busy
                      ? null
                      : () => setState(
                          () => anchor = cycle.start.subtract(
                            const Duration(days: 1),
                          ),
                        ),
                  icon: const Icon(Icons.chevron_left),
                ),
                Expanded(
                  child: Text(
                    '${DateFormat('d MMM yyyy').format(cycle.start)} – ${cycle.isOpen ? 'Next salary' : DateFormat('d MMM yyyy').format(cycle.end.subtract(const Duration(days: 1)))}',
                    textAlign: TextAlign.center,
                  ),
                ),
                IconButton(
                  onPressed: busy || cycle.isOpen
                      ? null
                      : () => setState(() => anchor = cycle.end),
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
          FutureBuilder(
            future: ref
                .read(repositoryProvider)
                .dataCounts(
                  start: allDates ? null : cycle.start,
                  end: allDates ? null : cycle.end,
                ),
            builder: (_, snapshot) => Column(
              children: [
                for (final group in DataGroup.values)
                  CheckboxListTile(
                    title: LText(group.label),
                    subtitle: Text(
                      '${snapshot.data?[group] ?? '…'} ${tr(context, 'records')}',
                    ),
                    value: selected.contains(group),
                    onChanged: busy
                        ? null
                        : (v) => setState(() {
                            if (v == true) {
                              selected.add(group);
                            } else {
                              selected.remove(group);
                            }
                          }),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          const LText(
            'Deleting income locks scanning for that pay cycle. Deleting savings entries keeps earned cat levels and outfits.',
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            key: const Key('deleteSelectedData'),
            onPressed: busy || selected.isEmpty ? null : remove,
            icon: const Icon(Icons.delete_outline),
            label: const LText('Delete selected data'),
          ),
        ],
      ),
    );
  }
}
