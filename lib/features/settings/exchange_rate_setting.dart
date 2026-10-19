import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/state.dart';
import '../../core/exchange_rate.dart';
import '../../shared/localized_text.dart';

class ExchangeRateSetting extends ConsumerStatefulWidget {
  const ExchangeRateSetting({super.key});
  @override
  ConsumerState<ExchangeRateSetting> createState() =>
      _ExchangeRateSettingState();
}

class _ExchangeRateSettingState extends ConsumerState<ExchangeRateSetting> {
  final form = GlobalKey<FormState>();
  late final TextEditingController controller;
  bool saving = false;
  @override
  void initState() {
    super.initState();
    controller = TextEditingController(
      text: formatManualRate(
        (ref.read(preferencesProvider).values['mmkPerThbMicros'] as int?) ??
            defaultMmkPerThbMicros,
      ),
    );
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (saving || !form.currentState!.validate()) return;
    setState(() => saving = true);
    try {
      await ref.read(preferencesProvider).updateAll({
        'mmkPerThbMicros': parseManualRate(controller.text),
        'manualRateUpdatedAt': DateTime.now().toUtc().toIso8601String(),
      });
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: LText('Exchange rate saved')));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: LText('Could not save. Please try again.')),
        );
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Form(
        key: form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LText(
              'MMK conversion rate',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            TextFormField(
              key: const Key('manualRateInput'),
              controller: controller,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                prefixText: '1 THB = ',
                suffixText: 'MMK',
                labelText: tr(context, 'Manual rate'),
              ),
              validator: (v) => parseManualRate(v ?? '') == null
                  ? tr(context, 'Enter a positive rate, such as 133')
                  : null,
              onFieldSubmitted: (_) => save(),
            ),
            const SizedBox(height: 12),
            const LText(
              'Used for approximate THB totals. It is not a live or historical market rate.',
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: saving ? null : save,
              child: const LText('Save exchange rate'),
            ),
          ],
        ),
      ),
    ),
  );
}
