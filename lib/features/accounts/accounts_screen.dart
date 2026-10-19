import '../../shared/localized_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/state.dart';
import '../../core/models.dart';

class AccountsScreen extends ConsumerWidget {
  const AccountsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    appBar: AppBar(title: const LText('Local account profiles')),
    body: ref
        .watch(accountsProvider)
        .when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) =>
              const Center(child: LText('Could not load accounts')),
          data: (accounts) => ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const LText(
                'Profiles only. SlipTrack never connects to your bank or asks for credentials. Masked identifiers remain ambiguous until you review the transfer.',
              ),
              const SizedBox(height: 20),
              ...accounts.map(
                (a) => Card(
                  child: ListTile(
                    leading: const Icon(Icons.account_balance_outlined),
                    title: Text(a.name),
                    subtitle: LText(
                      '${a.bank.label} · ${a.currency}\n${a.identifier.length > 4 ? '•••• ${a.identifier.substring(a.identifier.length - 4)}' : '••••'}',
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () => _add(context, ref),
                icon: const Icon(Icons.add),
                label: const LText('Add account'),
              ),
            ],
          ),
        ),
  );
  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final form = GlobalKey<FormState>();
    final name = TextEditingController(),
        holder = TextEditingController(),
        identifier = TextEditingController();
    Bank bank = Bank.trueMoney;
    await showDialog<void>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: const LText('Add account profile'),
          content: SingleChildScrollView(
            child: Form(
              key: form,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField(
                    isExpanded: true,
                    initialValue: bank,
                    items: Bank.values
                        .where((b) => b != Bank.unknown)
                        .map(
                          (b) =>
                              DropdownMenuItem(value: b, child: Text(b.label)),
                        )
                        .toList(),
                    onChanged: (v) => set(() => bank = v!),
                  ),
                  for (final e in {
                    'Display name': name,
                    'Account holder': holder,
                    'Account / wallet identifier': identifier,
                  }.entries)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: TextFormField(
                        controller: e.value,
                        decoration: InputDecoration(labelText: e.key),
                        validator: (v) =>
                            v == null || v.trim().isEmpty ? 'Required' : null,
                      ),
                    ),
                  const SizedBox(height: 12),
                  LText('Currency: ${bank.currency}'),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: const LText('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                if (!form.currentState!.validate()) return;
                await ref
                    .read(repositoryProvider)
                    .saveAccount(
                      Account(
                        id: newId(),
                        bank: bank,
                        name: name.text.trim(),
                        holder: holder.text.trim(),
                        identifier: identifier.text.trim(),
                        currency: bank.currency,
                      ),
                    );
                ref.invalidate(accountsProvider);
                if (c.mounted) Navigator.pop(c);
              },
              child: const LText('Save'),
            ),
          ],
        ),
      ),
    );
    name.dispose();
    holder.dispose();
    identifier.dispose();
  }
}
