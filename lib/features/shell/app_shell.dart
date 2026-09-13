import 'package:flutter/material.dart';

import '../../core/services.dart';
import '../../core/theme.dart';
import '../../core/format.dart';
import '../../widgets/sync_status.dart';
import '../clients/add_client_screen.dart';
import '../collections/collect_payment_screen.dart';
import '../leaves/leaves_screen.dart';
import '../orders/catalog_screen.dart';
import '../tasks/tasks_screen.dart';
import '../visits/visit_gate.dart';
import '../clients/clients_screen.dart';
import '../expenses/new_expense_screen.dart';
import '../home/home_screen.dart';
import '../more/more_screen.dart';
import '../orders/orders_screen.dart';

class _ShellTab {
  const _ShellTab(
      this.key, this.icon, this.activeIcon, this.label, this.screen);

  final String key;
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final Widget screen;
}

/// Bottom navigation: Home · Customers · Orders · Reports · More.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  String _current = 'home';

  void _open(String key) {
    setState(() => _current = key);
    Services.refresh.value++;
  }

  List<_ShellTab> _tabs() {
    final profile = Services.auth.profile!;
    return [
      _ShellTab('home', Icons.home_outlined, Icons.home_rounded, 'Home',
          HomeScreen(onOpenTab: _open)),
      if (profile.feature('visits'))
        _ShellTab(
            'customers',
            Icons.groups_2_outlined,
            Icons.groups_2_rounded,
            '${profile.label('client', 'Customer')}s',
            const ClientsScreen(embedded: true)),
      if (profile.feature('orders'))
        _ShellTab(
            'orders',
            Icons.receipt_long_outlined,
            Icons.receipt_long_rounded,
            '${profile.label('order', 'Order')}s',
            const OrdersScreen(embedded: true)),
      const _ShellTab('more', Icons.more_horiz_rounded,
          Icons.more_horiz_rounded, 'More', MoreScreen()),
    ];
  }

  /// The "+" in the middle: the two things people start from nothing.
  Future<void> _quickCreate(BuildContext context) async {
    final profile = Services.auth.profile!;
    final customer = profile.label('client', 'customer').toLowerCase();
    Widget option(String key, IconData icon, Color colour, String title, String subtitle, BuildContext sheet) =>
        ListTile(
          leading: CircleAvatar(
            backgroundColor: colour.withValues(alpha: 0.12),
            child: Icon(icon, color: colour),
          ),
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text(subtitle),
          onTap: () => Navigator.pop(sheet, key),
        );
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheet) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Taken at the customer: each one starts with a check-in there.
              if (profile.feature('orders'))
                option('order', Icons.add_shopping_cart_rounded, AixoloColors.primary,
                    'New ${profile.orderWord.toLowerCase()}', 'Pick the $customer, check in, add products', sheet),
              if (profile.paymentCollection)
                option('payment', Icons.payments_rounded, AixoloColors.teal, 'Collect payment',
                    'Pick the $customer, check in, record the amount', sheet),
              if (profile.feature('visits'))
                option('client', Icons.add_business_rounded, AixoloColors.success, 'New $customer',
                    'Add a shop you are standing in front of', sheet),
              if (profile.isManager)
                option('task', Icons.add_task_rounded, AixoloColors.purple, 'Give a task',
                    'Send a task to someone in your team', sheet),
              option('leave', Icons.beach_access_rounded, AixoloColors.sky, 'Leave request',
                  'Ask for time off', sheet),
              option('expense', Icons.receipt_long_rounded, AixoloColors.warning, 'New expense claim',
                  'Bus fare, lunch, anything you paid for', sheet),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
    if (choice == null || !context.mounted) return;
    final navigator = Navigator.of(context);
    Future<void> open(Widget screen) => navigator.push(MaterialPageRoute(builder: (_) => screen));

    switch (choice) {
      case 'order' || 'payment':
        final client = await navigator.push<Map<String, dynamic>>(
            MaterialPageRoute(builder: (_) => const ClientsScreen(pickMode: true)));
        if (client == null || !context.mounted) break;
        final visit = await ensureCheckedIn(context, client);
        if (visit == null || !context.mounted) break;
        await open(choice == 'order'
            ? CatalogScreen(client: client)
            : CollectPaymentScreen(client: client, visitId: visit['id'] as int?));
      case 'client':
        await open(const AddClientScreen());
      case 'task':
        await open(const NewTaskScreen());
      case 'leave':
        await _requestLeave(context);
      default:
        await open(const NewExpenseScreen());
    }
    Services.refresh.value++;
  }

  Future<void> _requestLeave(BuildContext context) async {
    try {
      final data = await Services.api.get('/api/v1/leaves') as Map<String, dynamic>;
      final types = ((data['types'] as List?) ?? []).cast<Map<String, dynamic>>();
      if (!context.mounted) return;
      if (types.isEmpty) {
        showSnack(context, 'No leave types are set up yet.');
        return;
      }
      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => LeaveRequestScreen(types: types)));
    } catch (e) {
      if (context.mounted) showSnack(context, e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final tabs = _tabs();
    var index = tabs.indexWhere((t) => t.key == _current);
    if (index < 0) index = 0;
    // The "+" sits in the middle of the bar, so the tabs are split around it.
    final half = tabs.length ~/ 2;
    return Scaffold(
      extendBody: true,
      body: ListenableBuilder(
        listenable: Listenable.merge([Services.api.online, Services.outbox.failed]),
        builder: (context, child) {
          final banner = !Services.api.online.value || Services.outbox.failed.value > 0;
          return Column(
            children: [
              const OfflineBanner(),
              // The banner already sits under the status bar; the screens below should not pad for it again.
              Expanded(child: MediaQuery.removePadding(context: context, removeTop: banner, child: child!)),
            ],
          );
        },
        child: IndexedStack(index: index, children: [for (final tab in tabs) tab.screen]),
      ),
      floatingActionButton: Container(
        width: 58,
        height: 58,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: AixoloColors.brandGradient,
          boxShadow: [
            BoxShadow(
              color: AixoloColors.primary.withValues(alpha: 0.38),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: () => _quickCreate(context),
            child: const Icon(Icons.add_rounded, color: Colors.white, size: 30),
          ),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: BottomAppBar(
        shape: const CircularNotchedRectangle(),
        notchMargin: 8,
        color: Colors.white,
        elevation: 10,
        padding: EdgeInsets.zero,
        height: 66,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            // Each side gets half the bar, so the "+" sits dead centre
            // however many tabs fall on either side of it.
            Expanded(
              child: Row(children: [
                for (var i = 0; i < half; i++)
                  Expanded(child: _tabButton(tabs[i], i == index)),
              ]),
            ),
            const SizedBox(width: 72),
            Expanded(
              child: Row(children: [
                for (var i = half; i < tabs.length; i++)
                  Expanded(child: _tabButton(tabs[i], i == index)),
              ]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tabButton(_ShellTab tab, bool active) {
    final colour = active ? AixoloColors.primary : AixoloColors.muted;
    return InkWell(
      onTap: () => _open(tab.key),
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              decoration: BoxDecoration(
                color: active ? const Color(0xFFE8EFFF) : Colors.transparent,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(active ? tab.activeIcon : tab.icon,
                  color: colour, size: 22),
            ),
            const SizedBox(height: 2),
            Text(
              tab.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 10.5, fontWeight: FontWeight.w700, color: colour),
            ),
          ],
        ),
      ),
    );
  }
}
