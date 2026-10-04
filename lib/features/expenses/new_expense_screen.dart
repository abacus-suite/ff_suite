import 'package:flutter/material.dart';

import '../../core/theme.dart';
import 'expense_form_screen.dart';

/// "+" → New Expense: claim what was paid from one's own pocket, or record what
/// was paid with a company card.
class NewExpenseScreen extends StatelessWidget {
  const NewExpenseScreen({super.key});

  @override
  Widget build(BuildContext context) {
    Widget option(String kind, IconData icon, Color tint, String title, String subtitle, String note) => InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: () async {
            final saved = await Navigator.of(context)
                .push<bool>(MaterialPageRoute(builder: (_) => ExpenseFormScreen(kind: kind)));
            if (saved == true && context.mounted) Navigator.of(context).pop(true);
          },
          child: Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [BoxShadow(color: const Color(0xFF1B3A7A).withValues(alpha: 0.08), blurRadius: 20, offset: const Offset(0, 8))],
            ),
            child: Row(children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(color: tint.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(18)),
                child: Icon(icon, color: tint, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
                  const SizedBox(height: 3),
                  Text(subtitle, style: const TextStyle(color: AppColors.muted, fontSize: 13)),
                  const SizedBox(height: 8),
                  Text(note, style: TextStyle(color: tint, fontSize: 12, fontWeight: FontWeight.w700)),
                ]),
              ),
              const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
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
            child: Text('Choose an option', style: TextStyle(fontSize: 14, color: AppColors.muted)),
          ),
          option('claim', Icons.account_balance_wallet_rounded, AppColors.warning, 'Expense Claiming',
              'I paid from my own money', 'Claim it back. Send by Monday 10:00 am'),
          const SizedBox(height: 14),
          option('card', Icons.credit_card_rounded, AppColors.primary, 'Expense Submission',
              'Paid with company card', 'Recorded for reconciliation, not a claim'),
        ],
      ),
    );
  }
}
