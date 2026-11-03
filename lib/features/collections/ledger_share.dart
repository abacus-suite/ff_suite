import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/format.dart';
import '../../core/services.dart';
import '../../core/theme.dart';
import '../../widgets/busy.dart';

/// The statement of account as one PDF - every invoice with the products on it, the payments and what
/// is left - saved in the cache's ledgers folder, the one the app may hand to WhatsApp.
Future<File> _fetchLedgerPdf(Map<String, dynamic> client) async {
  final url = await Services.api.url('/api/v1/clients/${client['id']}/ledger.pdf');
  final headers = await Services.api.authHeaders();
  final response = await http.get(Uri.parse(url), headers: headers);
  if (response.statusCode != 200) {
    throw Exception('The statement could not be prepared (${response.statusCode}).');
  }
  final dir = Directory('${(await getTemporaryDirectory()).path}/ledgers');
  await dir.create(recursive: true);
  final safe = '${client['name']}'.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
  final file = File('${dir.path}/Statement_$safe.pdf');
  await file.writeAsBytes(response.bodyBytes);
  return file;
}

const _whatsApp = MethodChannel('ff/whatsapp');

/// Builds the statement of account and hands it to the phone's share sheet, which is what
/// puts the file into WhatsApp. Returns true once it was shared.
Future<bool> shareLedgerPdf(BuildContext context, Map<String, dynamic> client) async {
  try {
    final file = await withBusy(context, 'Preparing the statement…', () => _fetchLedgerPdf(client));
    if (!context.mounted) return false;
    return await _shareSheet(file, client);
  } catch (e) {
    if (context.mounted) await showProblem(context, e.toString());
    return false;
  }
}

Future<bool> _shareSheet(File file, Map<String, dynamic> client) async {
  final result = await SharePlus.instance.share(ShareParams(
    files: [XFile(file.path, mimeType: 'application/pdf')],
    subject: 'Statement of account: ${client['name']}',
    text: 'Statement of account for ${client['name']}',
  ));
  return result.status != ShareResultStatus.dismissed;
}

/// Send Ledger: the statement PDF straight into the WhatsApp chat of the client's accounts contact.
/// Without a usable number, or without WhatsApp, the share sheet opens instead so it can still be sent.
/// Returns false when the statement could not be made at all (the caller may then send a text).
Future<bool> sendLedgerToContact(BuildContext context, Map<String, dynamic> client,
    {String? phone, String? contactName}) async {
  final File file;
  try {
    file = await withBusy(context, 'Preparing the statement…', () => _fetchLedgerPdf(client));
  } catch (_) {
    return false;
  }
  final number = whatsAppNumber(phone);
  final text = '${contactName == null ? 'Hello' : 'Hello $contactName'}, '
      'here is the statement of account for ${client['name']}.';
  if (number != null && Platform.isAndroid) {
    try {
      final sent = await _whatsApp.invokeMethod<bool>('sendFile', {'path': file.path, 'phone': number, 'text': text});
      if (sent == true) return true;
    } on PlatformException catch (_) {
      // Falls through to the share sheet.
    } on MissingPluginException catch (_) {
      // Falls through to the share sheet.
    }
  }
  if (context.mounted && number == null) {
    showSnack(context, 'No accounts contact number saved: choose the chat to send it to.');
  }
  await _shareSheet(file, client);
  return true;
}

String? _clean(Object? v) {
  final t = '${v ?? ''}'.trim();
  return t.isEmpty ? null : t;
}

/// The numbers the client already has, accounts contact first: (who, number).
List<(String, String)> ledgerNumbers(Map<String, dynamic> c) {
  final found = <(String, String)>[];
  void add(String who, Object? phone) {
    final n = _clean(phone);
    if (n != null && !found.any((e) => e.$2 == n)) found.add((who, n));
  }

  add(_clean(c['accounts_poc_name']) ?? 'Accounts contact', c['accounts_poc_phone']);
  add(_clean(c['poc_name']) ?? 'Contact', c['poc_phone']);
  final onboarding = c['onboarding'];
  if (onboarding is Map) {
    add(_clean(onboarding['accounts_poc_name']) ?? 'Accounts contact', onboarding['accounts_poc_phone']);
    add(_clean(onboarding['owner_name']) ?? 'Owner', onboarding['owner_phone']);
  }
  add('Outlet', c['phone']);
  return found;
}

/// Before the ledger goes: who it is for. Shows the accounts contact (POC) and the number; the employee can pick
/// another number the client has or type one, then Send opens that number's WhatsApp chat. Null when cancelled.
Future<({String phone, String? name})?> askLedgerRecipient(BuildContext context, Map<String, dynamic> client) async {
  var c = client;
  // The list the person came from may not carry the contacts: ask for the full record.
  if (ledgerNumbers(c).isEmpty && c['id'] != null) {
    try {
      c = {...c, ...(await Services.api.get('/api/v1/clients/${c['id']}') as Map<String, dynamic>)};
    } catch (_) {}
  }
  if (!context.mounted) return null;
  final options = ledgerNumbers(c);
  var name = options.isEmpty ? null : options.first.$1;
  final number = TextEditingController(text: options.isEmpty ? '' : options.first.$2);
  String? error;
  final result = await showDialog<({String phone, String? name})>(
    context: context,
    builder: (dialog) => StatefulBuilder(
      builder: (context, setDialog) => AlertDialog(
        title: const Text('Send the ledger'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${c['name']}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            const SizedBox(height: 4),
            Text(name == null ? 'No accounts contact saved: choose or type a number.' : 'To: $name',
                style: const TextStyle(color: AppColors.muted, fontSize: 13)),
            if (options.length > 1) ...[
              const SizedBox(height: 10),
              Wrap(spacing: 8, runSpacing: 6, children: [
                for (final (who, phone) in options)
                  ChoiceChip(
                    label: Text('$who · $phone'),
                    selected: number.text.trim() == phone,
                    onSelected: (_) => setDialog(() {
                      number.text = phone;
                      name = who;
                      error = null;
                    }),
                  ),
              ]),
            ],
            const SizedBox(height: 12),
            TextField(
              controller: number,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(
                labelText: 'WhatsApp number',
                prefixIcon: const Icon(Icons.phone_rounded),
                errorText: error,
              ),
              onChanged: (_) => setDialog(() => error = null),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog), child: const Text('Cancel')),
          FilledButton.icon(
            icon: const Icon(Icons.send_rounded, size: 18),
            label: const Text('Send'),
            onPressed: () {
              final typed = number.text.trim();
              if (whatsAppNumber(typed) == null) {
                setDialog(() => error = 'Enter a valid mobile number');
                return;
              }
              // A number typed over the contact's is no longer that contact's.
              final known = options.where((e) => e.$2 == typed).firstOrNull;
              Navigator.pop(dialog, (phone: typed, name: known?.$1 ?? (name != null && options.any((e) => e.$1 == name && e.$2 == typed) ? name : null)));
            },
          ),
        ],
      ),
    ),
  );
  number.dispose();
  return result;
}

/// Send Ledger from a visit or from receivables: ask who it is for, then straight into their WhatsApp chat.
Future<bool> sendLedgerWithPopup(BuildContext context, Map<String, dynamic> client) async {
  final to = await askLedgerRecipient(context, client);
  if (to == null || !context.mounted) return false;
  return sendLedgerToContact(context, client, phone: to.phone, contactName: to.name);
}
