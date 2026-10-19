import '../../shared/localized_text.dart';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../app/state.dart';
import '../../core/models.dart';
import '../ocr/ocr_service.dart';
import '../slip_recognition/parsers.dart';
import '../../shared/components.dart';

class ReviewScreen extends ConsumerStatefulWidget {
  const ReviewScreen({required this.id, super.key});
  final String id;
  @override
  ConsumerState<ReviewScreen> createState() => _ReviewState();
}

class _ReviewState extends ConsumerState<ReviewScreen> {
  Slip? slip;
  Future<Uint8List?>? preview;
  final fields = <String, TextEditingController>{};
  final form = GlobalKey<FormState>();
  bool saving = false, duplicateAcknowledged = false;
  String? error;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    final items = await ref.read(repositoryProvider).slips();
    final s = items.where((s) => s.id == widget.id).firstOrNull;
    if (!mounted) return;
    if (s == null) {
      setState(() => error = 'Receipt no longer exists');
      return;
    }
    for (final e in {
      'Amount': s.amountMinor == null
          ? ''
          : '${s.amountMinor! ~/ 100}.${(s.amountMinor! % 100).toString().padLeft(2, '0')}',
      'Date and time': s.date == null
          ? ''
          : DateFormat('dd/MM/yyyy HH:mm:ss').format(s.date!),
      'Sender': s.sender,
      'Receiver': s.receiver,
      'Sender identifier': s.senderId,
      'Receiver identifier': s.receiverId,
      'Reference': s.reference,
      'Description': s.description,
      'Category': s.category,
    }.entries) {
      fields[e.key] = TextEditingController(text: e.value);
    }
    preview = s.source.isEmpty
        ? Future.value(null)
        : NativeGallery().thumbnail(s.source);
    setState(() => slip = s);
  }

  @override
  void dispose() {
    for (final c in fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> save(bool confirm) async {
    if (saving || (confirm && !form.currentState!.validate())) return;
    final s = slip!;
    s.amountMinor = parseMinor(fields['Amount']!.text);
    s.date = parseSlipDate(fields['Date and time']!.text);
    s.sender = fields['Sender']!.text;
    s.receiver = fields['Receiver']!.text;
    s.senderId = fields['Sender identifier']!.text;
    s.receiverId = fields['Receiver identifier']!.text;
    s.reference = fields['Reference']!.text.trim();
    s.description = fields['Description']!.text;
    s.category = fields['Category']!.text.trim().isEmpty
        ? 'Uncategorized'
        : fields['Category']!.text.trim();
    if (confirm &&
        (!s.valid || (s.possibleDuplicate && !duplicateAcknowledged))) {
      message(
        context,
        'Check provider, positive amount, date, currency and direction. Acknowledge any possible duplicate.',
      );
      return;
    }
    s.review = confirm ? ReviewStatus.confirmed : ReviewStatus.pending;
    setState(() => saving = true);
    try {
      await ref.read(repositoryProvider).saveSlip(s);
      if (confirm) {
        try {
          await OnDeviceOCR.channel.invokeMethod('cleanup', {'id': s.source});
        } catch (_) {
          /* Database save is already durable. */
        }
      }
      if (mounted) context.pop();
    } on StateError catch (error) {
      if (mounted) message(context, error.message);
    } catch (_) {
      if (mounted) message(context, 'Could not save. Please try again.');
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = slip;
    return Scaffold(
      appBar: AppBar(
        title: const LText('Review receipt'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: s == null
                ? null
                : () async {
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (c) => AlertDialog(
                        title: const LText('Delete this transaction?'),
                        content: const LText(
                          'The gallery image stays in your photo library.',
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
                    if (ok == true) {
                      await ref.read(repositoryProvider).deleteSlip(s.id);
                      try {
                        await OnDeviceOCR.channel.invokeMethod('cleanup', {
                          'id': s.source,
                        });
                      } catch (_) {
                        /* Source cleanup can be retried on data deletion. */
                      }
                      if (context.mounted) context.pop();
                    }
                  },
          ),
        ],
      ),
      body: s == null
          ? Center(
              child: error == null
                  ? const CircularProgressIndicator()
                  : Text(error!),
            )
          : Form(
              key: form,
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  if (s.source.isNotEmpty)
                    FutureBuilder(
                      future: preview,
                      builder: (_, snapshot) => snapshot.data == null
                          ? const Card(
                              child: Padding(
                                padding: EdgeInsets.all(20),
                                child: LText(
                                  'Source unavailable or permission removed. Extracted record is preserved.',
                                ),
                              ),
                            )
                          : SizedBox(
                              height: 280,
                              child: InteractiveViewer(
                                child: Image.memory(
                                  snapshot.data!,
                                  fit: BoxFit.contain,
                                ),
                              ),
                            ),
                    ),
                  const SizedBox(height: 12),
                  const LText(
                    'Check all fields against the original receipt. OCR and parser scores are not proof of payment.',
                  ),
                  if (s.possibleDuplicate)
                    CheckboxListTile(
                      title: const LText(
                        'Possible duplicate — I have checked this is a separate transaction',
                      ),
                      value: duplicateAcknowledged,
                      onChanged: (v) =>
                          setState(() => duplicateAcknowledged = v ?? false),
                    ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<Bank>(
                    isExpanded: true,
                    initialValue: s.bank,
                    decoration: InputDecoration(
                      labelText: tr(context, 'Provider'),
                    ),
                    items: Bank.values
                        .map(
                          (b) =>
                              DropdownMenuItem(value: b, child: Text(b.label)),
                        )
                        .toList(),
                    onChanged: (v) => setState(() {
                      s.bank = v!;
                      s.currency = v.currency;
                      s.zone = v.zone;
                    }),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    key: ValueKey(s.currency),
                    initialValue: s.currency,
                    decoration: InputDecoration(
                      labelText: tr(context, 'Currency'),
                    ),
                    items: ['THB', 'MMK']
                        .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                        .toList(),
                    onChanged: (v) => setState(() => s.currency = v!),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<Direction>(
                    isExpanded: true,
                    initialValue: s.direction,
                    decoration: InputDecoration(
                      labelText: tr(context, 'Direction'),
                    ),
                    items: Direction.values
                        .map(
                          (d) =>
                              DropdownMenuItem(value: d, child: Text(d.name)),
                        )
                        .toList(),
                    onChanged: (v) => setState(() => s.direction = v!),
                  ),
                  const SizedBox(height: 12),
                  FutureBuilder(
                    future: ref.read(repositoryProvider).accounts(),
                    builder: (_, snapshot) => DropdownButtonFormField<String>(
                      isExpanded: true,
                      key: ValueKey(snapshot.hasData),
                      initialValue:
                          (snapshot.data ?? []).any((a) => a.id == s.accountId)
                          ? s.accountId
                          : '',
                      decoration: InputDecoration(
                        labelText: tr(context, 'Local account'),
                      ),
                      items: [
                        const DropdownMenuItem(
                          value: '',
                          child: LText('Unassigned'),
                        ),
                        ...(snapshot.data ?? []).map(
                          (a) => DropdownMenuItem(
                            value: a.id,
                            child: Text(a.name),
                          ),
                        ),
                      ],
                      onChanged: (v) => s.accountId = v == '' ? null : v,
                    ),
                  ),
                  ...fields.entries.map(
                    (e) => Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: TextFormField(
                        controller: e.value,
                        decoration: InputDecoration(
                          labelText: tr(context, e.key),
                          helperText: e.key == 'Date and time'
                              ? 'dd/MM/yyyy HH:mm:ss · ${s.zone ?? 'Timezone unknown'}'
                              : null,
                        ),
                        keyboardType: e.key == 'Amount'
                            ? const TextInputType.numberWithOptions(
                                decimal: true,
                              )
                            : TextInputType.text,
                        validator: (value) =>
                            e.key == 'Amount' && parseMinor(value ?? '') == null
                            ? 'Enter a decimal amount'
                            : e.key == 'Date and time' &&
                                  parseSlipDate(value ?? '') == null
                            ? 'Enter the actual transaction date and time'
                            : null,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  ExpansionTile(
                    title: const LText('Recognized text (on device)'),
                    children: [
                      SelectableText(
                        s.rawText.isEmpty
                            ? 'No text detected. Enter the details from the receipt.'
                            : s.rawText,
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: saving ? null : () => save(true),
                    child: const LText('Confirm transaction'),
                  ),
                  TextButton(
                    onPressed: saving ? null : () => save(false),
                    child: const LText('Save for later review'),
                  ),
                ],
              ),
            ),
    );
  }
}
