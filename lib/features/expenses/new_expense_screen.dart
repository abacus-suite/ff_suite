import 'package:flutter/material.dart';

import '../../core/services.dart';
import '../../core/theme.dart';
import 'expense_form_screen.dart';
import 'expenses_screen.dart';
import 'payment_request_screens.dart';

/// "+" → New Expense: claim what was paid from one's own pocket, record what
/// was paid with a company card, or ask accounts to pay the vendor directly.
class NewExpenseScreen extends StatelessWidget {
  const NewExpenseScreen({super.key, this.openList = true});

  /// After a claim is saved, go to My Expense to send it. Off when My Expense is already behind this screen.
  final bool openList;

  @override
  Widget build(BuildContext context) {
    Widget option(String kind, IconData icon, List<Color> colours, String title, String subtitle, String hint) => InkWell(
          borderRadius: BorderRadius.circular(26),
          onTap: () async {
            final saved = await Navigator.of(context).push<bool>(MaterialPageRoute(
                builder: (_) => kind == 'request' ? const PaymentRequestFormScreen() : ExpenseFormScreen(kind: kind)));
            if (saved != true || !context.mounted) return;
            if (kind == 'request') {
              // A request is followed in My Expense, on its own tab, till its tax invoice is in.
              Navigator.of(context).pushReplacement(
                  MaterialPageRoute(builder: (_) => const ExpensesScreen(initialTab: 'request')));
            } else if (openList) {
              // A saved claim is sent from My Expense, so that is where it goes next.
              Navigator.of(context)
                  .pushReplacement(MaterialPageRoute(builder: (_) => ExpensesScreen(initialTab: kind)));
            } else {
              Navigator.of(context).pop(true);
            }
          },
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(26),
              boxShadow: [BoxShadow(color: const Color(0xFF1B3A7A).withValues(alpha: 0.08), blurRadius: 22, offset: const Offset(0, 8))],
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(
                  width: 58,
                  height: 58,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: colours, begin: Alignment.topLeft, end: Alignment.bottomRight),
                    borderRadius: BorderRadius.circular(19),
                    boxShadow: [BoxShadow(color: colours.first.withValues(alpha: 0.35), blurRadius: 12, offset: const Offset(0, 5))],
                  ),
                  child: Icon(icon, color: Colors.white, size: 28),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
                    const SizedBox(height: 3),
                    Text(subtitle, style: const TextStyle(color: AppColors.muted, fontSize: 13)),
                  ]),
                ),
                CircleAvatar(
                  radius: 16,
                  backgroundColor: colours.first.withValues(alpha: 0.12),
                  child: Icon(Icons.arrow_forward_rounded, size: 18, color: colours.first),
                ),
              ]),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(color: colours.first.withValues(alpha: 0.07), borderRadius: BorderRadius.circular(12)),
                child: Row(children: [
                  Icon(Icons.info_outline_rounded, size: 15, color: colours.first),
                  const SizedBox(width: 8),
                  Expanded(child: Text(hint, style: TextStyle(fontSize: 12, color: colours.first, fontWeight: FontWeight.w600))),
                ]),
              ),
            ]),
          ),
        );

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('New Expense')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(4, 4, 4, 14),
            child: Text('What do you want to record?', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          ),
          option('claim', Icons.account_balance_wallet_rounded, const [Color(0xFFF59E0B), Color(0xFFEA580C)],
              'Expense Claiming', 'I paid from my own money – claim it', 'Add the bill, then send it for approval.'),
          if (Services.auth.profile?.expenseCard ?? false) ...[
            const SizedBox(height: 14),
            option('card', Icons.credit_card_rounded, const [Color(0xFF2563EB), Color(0xFF1E40AF)],
                'Company Card', 'Paid with a company card – record it', 'A picture of the bill is needed.'),
          ],
          const SizedBox(height: 14),
          option('request', Icons.request_quote_rounded, const [Color(0xFF8B5CF6), Color(0xFF6D28D9)],
              'Payment Request', 'Ask accounts to pay the vendor directly', 'Upload the tax invoice once it is paid.'),
        ],
      ),
    );
  }
}
