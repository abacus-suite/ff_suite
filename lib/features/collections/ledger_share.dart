import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/format.dart';
import '../../core/services.dart';
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
