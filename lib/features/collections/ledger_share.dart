import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/format.dart';
import '../../core/services.dart';
import '../../widgets/busy.dart';

/// Builds the statement of account as one PDF - every invoice with the products on it,
/// the payments and what is left - and hands it to the phone's share sheet, which is what
/// puts the file into WhatsApp. Returns true once it was shared.
Future<bool> shareLedgerPdf(BuildContext context, Map<String, dynamic> client) async {
  try {
    final file = await withBusy(context, 'Preparing the statement…', () async {
      final url = await Services.api.url('/api/v1/clients/${client['id']}/ledger.pdf');
      final headers = await Services.api.authHeaders();
      final response = await http.get(Uri.parse(url), headers: headers);
      if (response.statusCode != 200) {
        throw Exception('The statement could not be prepared (${response.statusCode}).');
      }
      final dir = await getTemporaryDirectory();
      final safe = '${client['name']}'.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
      final path = File('${dir.path}/Statement_$safe.pdf');
      await path.writeAsBytes(response.bodyBytes);
      return path;
    });
    if (!context.mounted) return false;
    final result = await SharePlus.instance.share(ShareParams(
      files: [XFile(file.path, mimeType: 'application/pdf')],
      subject: 'Statement of account: ${client['name']}',
      text: 'Statement of account for ${client['name']}',
    ));
    return result.status != ShareResultStatus.dismissed;
  } catch (e) {
    if (context.mounted) await showProblem(context, e.toString());
    return false;
  }
}
