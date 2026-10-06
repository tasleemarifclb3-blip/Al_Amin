import 'dart:async';
import 'screens/simple_radio.dart';

import 'package:drift/drift.dart' show Value;

import 'package:flutter/material.dart';
import 'domain/format.dart';

import 'package:flutter/services.dart';


import 'database/sync_firestore_service.dart';

import 'database/app_database.dart';

import 'database/accounting_service.dart';

import 'database/workflow_service.dart';

import 'screens/brand.dart';

import 'screens/donations_accounts_page.dart';

import 'screens/financial_entry_page.dart';

import 'screens/fund_expense_page.dart';

import 'screens/households_page.dart';

import 'screens/ledger_page.dart';

import 'screens/qarza_hassanah_page.dart';

import 'screens/reports_page.dart';

import 'screens/receipt_actions.dart';

import 'screens/zakaat_expenditure_page.dart';

import 'screens/security.dart';

import 'screens/data_management_page.dart';

import 'screens/app_ui.dart';
import 'screens/finance_charts.dart';
import 'screens/pdf_support.dart';
import 'screens/wifi_sync_page.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

final AppDatabase appDatabase = AppDatabase();

Future<void> main() async {

  WidgetsFlutterBinding.ensureInitialized();

  await initializeSecurity();
  await PdfSupport.load();

  // Render the application first. Database/Firebase synchronization is*

  // deliberately started after the first frame so a slow web database,*

  // Firebase authentication, or a network problem cannot delay the login*

  // screen or block the Android UI thread during startup.*

  runApp(const BaitulMaalApp());

  WidgetsBinding.instance.addPostFrameCallback((_) {

    unawaited(SyncFirestoreService.initialize(appDatabase));

  });

}

class BaitulMaalApp extends StatelessWidget {

  const BaitulMaalApp({super.key});

  @override

  Widget build(BuildContext context) {

    final scheme = ColorScheme.fromSeed(seedColor: kBrandGreen, brightness: Brightness.light);

    return MaterialApp(

      navigatorKey: navigatorKey,

      debugShowCheckedModeBanner: false,

      title: 'Al-Amin Baitul Maal',

      theme: ThemeData(

        useMaterial3: true,

        colorScheme: scheme,

        scaffoldBackgroundColor: Colors.transparent,

        cardTheme: CardThemeData(

          elevation: 1.5,

          margin: const EdgeInsets.symmetric(vertical: 6),

          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),

        ),

        appBarTheme: const AppBarTheme(

          backgroundColor: Colors.transparent,

          foregroundColor: kBrandGreen,

          centerTitle: false,

        ),

      ),

      builder: (context, child) => _AlAminBackdrop(child: child),

      home: LoginPage(onSuccess: () { navigatorKey.currentState?.pushReplacement(MaterialPageRoute(builder: (_) => const DashboardPage())); }),

    );

  }

}

class _AlAminBackdrop extends StatelessWidget {

  final Widget? child;

  const _AlAminBackdrop({this.child});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFFF7FAF8),
            Color(0xFFEEF5F1),
            Color(0xFFF8F5ED),
          ],
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned(
            top: -120,
            left: -90,
            child: Container(
              width: 300,
              height: 300,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0x141F7A68),
              ),
            ),
          ),
          Positioned(
            right: -110,
            bottom: 80,
            child: Container(
              width: 280,
              height: 280,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0x12C9A84E),
              ),
            ),
          ),
          child ?? const SizedBox.shrink(),
        ],
      ),
    );
  }
}

class DashboardPage extends StatefulWidget {

  const DashboardPage({super.key});

  @override

  State<DashboardPage> createState() => _DashboardPageState();

}

class _DashboardPageState extends State<DashboardPage> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final ValueNotifier<int> _rev = ValueNotifier<int>(0);
  final ValueNotifier<_FinancialSummary?> _live = ValueNotifier<_FinancialSummary?>(null);
  final PageController _pages = PageController();

  late Future<_FinancialSummary> _future;

  int _index = 0;

  @override

  void initState() {

    super.initState();

    _future = _load();

  SyncFirestoreService.dataRevision.addListener(_onSyncData);
    SyncFirestoreService.resetRevision.addListener(_onGlobalReset);
  }

  Timer? _syncRefreshTimer;
  DateTime _lastSyncRefresh = DateTime.fromMillisecondsSinceEpoch(0);

  /// A synchronization changed local data: reload the figures on screen.
  /// Several sync cycles are merged into one reload, and reloads are spaced at
  /// least 20 seconds apart so the screen never flickers or reloads constantly.
  void _onSyncData() {
    if (!mounted || _syncRefreshTimer != null) return;
    const minGap = Duration(seconds: 20);
    final wait = minGap - DateTime.now().difference(_lastSyncRefresh);
    _syncRefreshTimer = Timer(wait.isNegative ? const Duration(seconds: 2) : wait, () {
      _syncRefreshTimer = null;
      if (!mounted) return;
      _lastSyncRefresh = DateTime.now();
      _refresh();
    });
  }

  /// Another device deleted the entire database: this device has already been
  /// cleared, so return to the home screen and reload.
  void _onGlobalReset() {
    if (!mounted) return;
    _syncRefreshTimer?.cancel();
    _syncRefreshTimer = null;
    final homeRoute = ModalRoute.of(context);
    Navigator.of(context).popUntil((route) => route == homeRoute || route.isFirst);
    _refresh();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        duration: Duration(seconds: 8),
        content: Text('The database was deleted from another device. All data on this device has been cleared.'),
      ),
    );
}

  @override

  void dispose() {

    SyncFirestoreService.dataRevision.removeListener(_onSyncData);
    _syncRefreshTimer?.cancel();
    SyncFirestoreService.resetRevision.removeListener(_onGlobalReset);
    _pages.dispose();
    _rev.dispose();
    _live.dispose();

    super.dispose();

  }

  Future<_FinancialSummary> _load() async {
    final loaded = await _loadFromDatabase();
    // Keep the latest figures where every screen can show them at once.
    if (mounted) _live.value = loaded;
    return loaded;
  }

  Future<_FinancialSummary> _loadFromDatabase() async {

    final totals = await AccountingService.totals(appDatabase);

    final now = DateTime.now();

    bool sameDate(DateTime d) =>

        d.year == now.year && d.month == now.month && d.day == now.day;

    var todayCash = 0.0;

    var todayBank = 0.0;

    final members = await appDatabase.select(appDatabase.householdPayments).get();

    for (final p in members) {

      if (!sameDate(p.paymentDate)) continue;

      if (p.paymentMode == 'Cash') todayCash += p.amount;

      if (p.paymentMode == 'Bank Transfer') todayBank += p.amount;

    }

    final transactions = await appDatabase.select(appDatabase.financialTransactions).get();

    for (final t in transactions) {

      if (!sameDate(t.transactionDate)) continue;

      if (t.paymentMode == 'Cash') todayCash += t.amount;

      if (t.paymentMode == 'Bank Transfer') todayBank += t.amount;

    }

    final adjustments = await appDatabase.select(appDatabase.fundAdjustments).get();

    for (final a in adjustments) {

      if (!sameDate(a.transactionDate)) continue;

      if (a.adjustmentType != 'QARZA_RECOVERY') continue;

      if (a.paymentMode == 'Cash') todayCash += a.amount;

      if (a.paymentMode == 'Bank Transfer') todayBank += a.amount;

    }

    final manualRows = await appDatabase.select(appDatabase.manualBalances).get();

    final cash = manualRows.isEmpty ? 0.0 : manualRows.first.cashInHand;

    final bank = manualRows.isEmpty ? 0.0 : manualRows.first.bankBalance;

    return _FinancialSummary(

      monthlyDonation: totals.monthlyDonation,

      generalDonation: totals.generalDonation,

      boxCollection: totals.boxCollection,

      otherIncome: totals.otherIncome,

      zakaat: totals.zakaatFund,

      sadqaFitr: totals.sadqaFund,

      qarzaNet: totals.qarzaNet,

      todayCash: todayCash,

      todayBank: todayBank,

      cashInHand: cash,

      bankBalance: bank,

      donationFund: totals.donationFund,

      expectedTotal: totals.netAvailable,

    );

  }

  void _refresh() {

    if (!mounted) return;

    setState(() {

      _future = _load();

    });
    _rev.value++;

  }

  Future<void> _syncAndRefresh() async {

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(

      const SnackBar(

        content: Row(children: [

          SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),

          SizedBox(width: 12),

          Text('Synchronizing with Firebase...'),

        ]),

        duration: Duration(seconds: 30),

      ),

    );

    final status = await SyncFirestoreService.syncNow();

    if (!mounted) return;

    ScaffoldMessenger.of(context).hideCurrentSnackBar();

    if (status.ok && !status.busy) {

      _refresh();

      ScaffoldMessenger.of(context).showSnackBar(

        const SnackBar(content: Text('Sync completed successfully. Ledgers and reports have been refreshed.')),

      );

    } else {

      ScaffoldMessenger.of(context).showSnackBar(

        SnackBar(content: Text('Sync could not be completed: ${status.message ?? 'Sync is already running.'}')),

      );

    }

  }

  Future<void> _logout() async {

    if (!mounted) return;

    final user = (currentUsername ?? '').trim();

    final confirmed = await showDialog<bool>(

      context: context,

      barrierDismissible: false,

      builder: (dialogContext) => AlertDialog(

        title: const Text('Logout'),

        content: Text(

          'Logout ${user.isEmpty ? 'the current user' : user}?\n\n'

          'No accounting data or Firebase data will be deleted.',

        ),

        actions: [

          TextButton(

            onPressed: () => Navigator.of(dialogContext).pop(false),

            child: const Text('CANCEL'),

          ),

          FilledButton(

            onPressed: () => Navigator.of(dialogContext).pop(true),

            child: const Text('LOGOUT'),

          ),

        ],

      ),

    );

    if (confirmed != true || !mounted) return;

    currentUsername = null;

    navigatorKey.currentState?.pushAndRemoveUntil(

      MaterialPageRoute(

        builder: (_) => LoginPage(

          onSuccess: () {

            navigatorKey.currentState?.pushReplacement(

              MaterialPageRoute(builder: (_) => const DashboardPage()),

            );

          },

        ),

      ),

      (route) => false,

    );

  }

  Future<void> _push(Widget page) async {

    await Navigator.push(context, MaterialPageRoute(builder: (_) => page));

    if (mounted) _refresh();

  }

  Future<void> _openDataManagement() async {

    final controller = TextEditingController();

    bool obscure = true;

    final password = await showDialog<String>(

      context: context,

      barrierDismissible: false,

      useRootNavigator: true,

      requestFocus: false,

      builder: (dialogContext) => StatefulBuilder(

        builder: (context, setDialogState) => AlertDialog(

          title: const Row(

            children: [

              Icon(Icons.lock_outline_rounded, color: kBrandGreen),

              SizedBox(width: 10),

              Text('Data Management'),

            ],

          ),

          content: TextField(

            controller: controller,

            // Do not request focus automatically. On Flutter web, an*

            // // autofocus TextField inside a modal can leave the dialog*

            // FocusScope attached for one frame after the route is popped.*

            obscureText: obscure,

            decoration: InputDecoration(

              labelText: 'Superuser Password',

              border: const OutlineInputBorder(),

              suffixIcon: IconButton(

                tooltip: obscure ? 'Show password' : 'Hide password',

                onPressed: () => setDialogState(() => obscure = !obscure),

                icon: Icon(obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),

              ),

            ),

            onSubmitted: (_) {

              FocusScope.of(dialogContext).unfocus();

              Navigator.pop(dialogContext, controller.text);

            },

          ),

          actions: [

            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('CANCEL')),

            FilledButton.icon(

              onPressed: () {

                FocusScope.of(dialogContext).unfocus();

                Navigator.pop(dialogContext, controller.text);

              },

              icon: const Icon(Icons.lock_open_rounded),

              label: const Text('CONTINUE'),

            ),

          ],

        ),

      ),

    );

    // Let the modal route, FocusScope and keyboard detach before disposing*

    // the controller or pushing the Data Management page. This prevents the*

    // Flutter web '_dependents.isEmpty' assertion during dialog teardown.*

    await Future<void>.delayed(const Duration(milliseconds: 120));

    controller.dispose();

    if (!mounted || password == null) return;

    if (!verifySuperuserPassword(password.trim())) {

      ScaffoldMessenger.of(context).showSnackBar(

        const SnackBar(content: Text('Invalid Superuser password.')),

      );

      return;

    }

    await _push(DataManagementPage(database: appDatabase));

  }

  Future<void> _editActualBalance(
    String title,
    double currentAmount,
    double otherAmount,
  ) async {
    final controller = TextEditingController(text: currentAmount.toStringAsFixed(2));
    final result = await showDialog<double>(
      context: context,
      barrierDismissible: false,
      useRootNavigator: true,
      requestFocus: false,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: false,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          textInputAction: TextInputAction.done,
          decoration: const InputDecoration(
            labelText: 'Amount',
            prefixText: '₹ ',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              FocusManager.instance.primaryFocus?.unfocus();
              Navigator.of(dialogContext).pop();
            },
            child: const Text('CANCEL'),
          ),
          TextButton(
            onPressed: () {
              FocusManager.instance.primaryFocus?.unfocus();
              Navigator.of(dialogContext).pop(0.0);
            },
            child: const Text('CLEAR'),
          ),
          FilledButton(
            onPressed: () {
              final clean = controller.text.replaceAll(',', '').replaceAll('₹', '').trim();
              final value = double.tryParse(clean);
              if (value == null || value < 0 || !value.isFinite) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Enter a valid non-negative amount.')),
                );
                return;
              }
              FocusManager.instance.primaryFocus?.unfocus();
              Navigator.of(dialogContext).pop(value);
            },
            child: const Text('SAVE'),
          ),
        ],
      ),
    );

    // Unfocus before disposing the controller; the keyboard/focus route must
    // detach before the reconciliation page refreshes its data.
    FocusManager.instance.primaryFocus?.unfocus();
    // Show the new figure immediately; the database save and reload below only
    // confirm it (and correct it if saving fails).
    final shown = _live.value;
    if (result != null && mounted && shown != null) {
      _live.value = title == 'Cash in Hand'
          ? shown.copyWith(cashInHand: result)
          : shown.copyWith(bankBalance: result);
    }
    await Future<void>.delayed(const Duration(milliseconds: 150));
    controller.dispose();
    if (result == null || !mounted) return;

    try {
      final rows = await appDatabase.select(appDatabase.manualBalances).get();
      final cash = title == 'Cash in Hand' ? result : otherAmount;
      final bank = title == 'Bank Balance' ? result : otherAmount;
      if (rows.isEmpty) {
        await appDatabase.into(appDatabase.manualBalances).insert(
          ManualBalancesCompanion.insert(
            cashInHand: Value(cash),
            bankBalance: Value(bank),
          ),
        );
      } else {
        await (appDatabase.update(appDatabase.manualBalances)
              ..where((t) => t.id.equals(rows.first.id)))
            .write(ManualBalancesCompanion(
          cashInHand: Value(cash),
          bankBalance: Value(bank),
          updatedAt: Value(DateTime.now()),
        ));
      }
      if (!mounted) return;
      _refresh();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save $title: $e')),
        );
      }
      if (mounted) _refresh();
    }
  }

  Future<void> _confirmExit() async {

    if (!mounted) return;

    final shouldExit = await showDialog<bool>(

      context: context,

      builder: (dialogContext) => AlertDialog(

        title: const Text('Exit Al-Amin Baitul Maal?'),

        content: const Text('Are you sure you want to leave the application?'),

        actions: [

          TextButton(

            onPressed: () => Navigator.of(dialogContext).pop(false),

            child: const Text('Cancel'),

          ),

          FilledButton(

            onPressed: () => Navigator.of(dialogContext).pop(true),

            child: const Text('Exit'),

          ),

        ],

      ),

    );

    if (shouldExit != true || !mounted) return;

    await appDatabase.close();

    await SystemNavigator.pop();

  }

  @override

  Widget build(BuildContext context) {

    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(

      statusBarColor: Colors.transparent,

      systemNavigationBarColor: Colors.transparent,

      statusBarIconBrightness: Brightness.dark,

      systemNavigationBarIconBrightness: Brightness.dark,

    ));

    return PopScope(

      canPop: false,

      onPopInvokedWithResult: (didPop, result) {

        if (!didPop) {

          _confirmExit();

        }

      },

      child: Scaffold(
        key: _scaffoldKey,
        drawer: _buildDrawer(),
        // Keep the full logo at the top of the dashboard. Action buttons*

        // deliberately sit below it rather than sharing the logo row.*

        appBar: const PreferredSize(

          preferredSize: Size.zero,

          child: SizedBox.shrink(),

        ),

        body: IslamicBackground(
          child: FutureBuilder<_FinancialSummary>(

          future: _future,

          builder: (context, snap) {

            final stale = _live.value;
            // Keep showing the last figures while a reload runs in the background:
            // the spinner only appears the very first time.
            if (snap.connectionState != ConnectionState.done && stale == null) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snap.hasError && stale == null) {

              return Center(

                child: Padding(

                  padding: const EdgeInsets.all(16),

                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Could not load Dashboard:\n${snap.error}',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: _refresh,
                        icon: const Icon(Icons.refresh),
                        label: const Text('RETRY'),
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: () => _scaffoldKey.currentState?.openDrawer(),
                        icon: const Icon(Icons.menu_rounded),
                        label: const Text('MENU'),
                      ),
                    ],
                  ),

                ),

              );

            }

            final s = snap.data ?? stale!;
            return _singleScreen(s);
          },
        ),
        ),
      ),
    );
  }

  Widget _approvalBanner() {

    return FutureBuilder<String>(

      future: WorkflowService.activeApprover(appDatabase),

      builder: (context, approverSnap) {

        final approver = (approverSnap.data ?? '').trim();

        return FutureBuilder<List<PendingCheque>>(

          future: WorkflowService.pending(appDatabase),

          builder: (context, snap) {

            final pending = snap.data ?? const <PendingCheque>[];

            if (pending.isEmpty) return const SizedBox.shrink();

            return Card(

              child: ListTile(

                leading: const Icon(Icons.pending_actions),

                title: Text(

                  '${pending.length} transaction${pending.length == 1 ? '' : 's'} awaiting approval',

                  style: const TextStyle(fontWeight: FontWeight.bold),

                ),

                subtitle: Text(approver.isEmpty ? 'A transaction requires approval.' : 'Configured approver: $approver'),

                trailing: FilledButton.tonal(

                  onPressed: _showPendingApprovals,

                  child: const Text('Review'),

                ),

              ),

            );

          },

        );

      },

    );

  }

  Future<void> _changeApprover() async {

    if (!await requireSuperuserPassword(

      context,

      title: 'Change Approval Authority',

      message: 'Enter the superuser password to change the single active approver.',

    )) {
      return;
    }

    if (!mounted) return;

    final users = kUserPasswords.keys.toList()

      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    final current = await WorkflowService.activeApprover(appDatabase);

    var selected = users.contains(current) ? current : (users.isEmpty ? '' : users.first);
    if (!mounted) return;

    final chosen = await showDialog<String>(

      context: context,

      builder: (ctx) => StatefulBuilder(

        builder: (ctx, setLocal) => AlertDialog(

          title: const Text('Single Active Approver'),

          content: DropdownButtonFormField<String>(

            initialValue: selected.isEmpty ? null : selected,

            decoration: const InputDecoration(

              labelText: 'Approver',

              border: OutlineInputBorder(),

            ),

            items: users.map((u) => DropdownMenuItem(value: u, child: Text(u))).toList(),

            onChanged: (v) => setLocal(() => selected = v ?? selected),

          ),

          actions: [

            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),

            FilledButton(

              onPressed: selected.isEmpty ? null : () => Navigator.pop(ctx, selected),

              child: const Text('Save'),

            ),

          ],

        ),

      ),

    );

    if (chosen == null || !mounted) return;

    await WorkflowService.setActiveApprover(appDatabase, chosen);

    await SyncFirestoreService.syncNow();

    if (mounted) {

      _refresh();

      ScaffoldMessenger.of(context).showSnackBar(

        SnackBar(content: Text('Active approver changed to $chosen.')),

      );

    }

  }

  Future<void> _showPendingApprovals() async {

    final activeApprover = await WorkflowService.activeApprover(appDatabase);

    final user = (currentUsername ?? '').trim();

    final canApprove = user.toLowerCase() == activeApprover.toLowerCase();

    var pending = await WorkflowService.pending(appDatabase);

    if (!mounted) return;

    Future<String?> askReason() async {

      final controller = TextEditingController();

      final reason = await showDialog<String>(

        context: context,

        barrierDismissible: false,

        builder: (ctx) => AlertDialog(

          title: const Text('Disprove Transaction'),

          content: TextField(

            controller: controller,

            autofocus: true,

            maxLines: 4,

            decoration: const InputDecoration(

              labelText: 'Reason *',

              hintText: 'Enter why this transaction is being disproved',

              border: OutlineInputBorder(),

            ),

          ),

          actions: [

            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),

            FilledButton(

              onPressed: () {

                if (controller.text.trim().isNotEmpty) Navigator.pop(ctx, controller.text.trim());

              },

              child: const Text('Disprove'),

            ),

          ],

        ),

      );

      controller.dispose();

      return reason;

    }

    await showDialog<void>(

      context: context,

      builder: (dialogContext) => StatefulBuilder(

        builder: (dialogContext, setDialogState) => AlertDialog(

          title: Text('Unapproved Transactions — $activeApprover'),

          content: SizedBox(

            width: 700,

            child: pending.isEmpty

                ? const Text('No unapproved transactions.')

                : ListView.builder(

                    shrinkWrap: true,

                    itemCount: pending.length,

                    itemBuilder: (context, index) {

                      final item = pending[index];

                      return Card(

                        child: Padding(

                          padding: const EdgeInsets.all(12),

                          child: Column(

                            crossAxisAlignment: CrossAxisAlignment.start,

                            children: [

                              Text(item.description, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),

                              const SizedBox(height: 5),

                              Text(

                                'Reference: ${item.reference.isEmpty ? '—' : item.reference}\n'

                                'Amount: ₹${item.amount.asAmount}\n'

                                'Prepared by: ${item.requestedBy}\n'

                                'Date: ${item.requestedAt == null ? '—' : ReceiptActions.formatDate(item.requestedAt!)}',

                              ),

                              const SizedBox(height: 6),

                              Text('Awaiting approval from $activeApprover.'),

                              const SizedBox(height: 8),

                              Row(

                                mainAxisAlignment: MainAxisAlignment.end,

                                children: [

                                  OutlinedButton.icon(

                                    onPressed: !canApprove ? null : () async {

                                      final reason = await askReason();

                                      if (reason == null) return;

                                      await WorkflowService.reject(

                                        appDatabase,

                                        sourceTable: item.sourceTable,

                                        transactionId: item.transactionId,

                                        rejectedBy: user,

                                        reason: reason,

                                      );

                                      pending = await WorkflowService.pending(appDatabase);

                                      if (dialogContext.mounted) setDialogState(() {});

                                      if (mounted) _refresh();

                                    },

                                    icon: const Icon(Icons.block),

                                    label: const Text('Disprove'),

                                  ),

                                  const SizedBox(width: 8),

                                  FilledButton.icon(

                                    onPressed: !canApprove ? null : () async {

                                      await WorkflowService.approve(

                                        appDatabase,

                                        sourceTable: item.sourceTable,

                                        transactionId: item.transactionId,

                                        approver: user,

                                      );

                                      pending = await WorkflowService.pending(appDatabase);

                                      if (dialogContext.mounted) setDialogState(() {});

                                      if (mounted) _refresh();

                                    },

                                    icon: const Icon(Icons.check),

                                    label: const Text('Approve'),

                                  ),

                                ],

                              ),

                            ],

                          ),

                        ),

                      );

                    },

                  ),

          ),

          actions: [

            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Close')),

          ],

        ),

      ),

    );

    if (mounted) _refresh();

  }

  Future<void> _switchUser() async {

    final users = kUserPasswords.keys.toList()

      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    final initial = users.contains((currentUsername ?? '').trim())

        ? (currentUsername ?? '').trim()

        : (users.isEmpty ? '' : users.first);

    final authenticatedUser = await showDialog<String>(

      context: context,

      barrierDismissible: false,

      useRootNavigator: true,

      builder: (_) => _SwitchUserDialog(users: users, initialUser: initial),

    );

    if (authenticatedUser == null || !mounted) return;

    // Rebuild only after the dialog route, focus node and keyboard have fully*

    // detached. This avoids the recurring Flutter _dependents.isEmpty assertion.*

    await Future<void>.delayed(const Duration(milliseconds: 120));

    if (!mounted) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {

      if (!mounted) return;

      setState(() {

        currentUsername = authenticatedUser;

      });

    });

  }

  Widget _dashboardScrollable(_FinancialSummary s, Widget content) {

    return LayoutBuilder(

      builder: (context, constraints) {

        // Keep the dashboard comfortably sized on large laptop/desktop*

        // screens while allowing it to use the available width on phones.*

        final isDesktop = constraints.maxWidth >= 800;

        final maxContentWidth = isDesktop ? 1100.0 : double.infinity;

        return Column(
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(isDesktop ? 24 : 16, 8, isDesktop ? 24 : 16, 0),
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxContentWidth),
                  child: const AppPageHeader(
                    title: 'Al-Amin Baitul Maal',
                    subtitle: 'Manage receipts, funds, expenses and approvals',
                    compact: true,
                  ),
                ),
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(isDesktop ? 24 : 16, 0, isDesktop ? 24 : 16, 16),
                child: Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: maxContentWidth),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: .78),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      children: [
                        IconButton(
                          tooltip: 'Menu',
                          onPressed: () => _scaffoldKey.currentState?.openDrawer(),
                          icon: const Icon(Icons.menu_rounded, color: kBrandGreen, size: 26),
                        ),
                        const SizedBox(width: 2),
                        Expanded(
                          child: Text(
                            'Welcome, ${(currentUsername ?? '').trim().isEmpty ? 'User' : (currentUsername ?? '').trim()}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Reconciliation',
                          onPressed: _openReconciliation,
                          icon: const Icon(Icons.balance_outlined, size: 22),
                          color: kBrandGreen,
                          visualDensity: VisualDensity.compact,
                        ),
                        IconButton(
                          tooltip: 'Unapproved Transactions',
                          onPressed: _showPendingApprovals,
                          icon: const Icon(Icons.pending_actions_outlined, size: 22),
                          color: kBrandGreen,
                          visualDensity: VisualDensity.compact,
                        ),
                        IconButton(
                          tooltip: 'Sync & Refresh',
                          onPressed: _syncAndRefresh,
                          icon: const Icon(Icons.refresh_rounded, size: 22),
                          color: kBrandGreen,
                          visualDensity: VisualDensity.compact,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),

                  content,

                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        );

      },

    );

  }

  Widget _screenOne(_FinancialSummary s) =>
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [

          _approvalBanner(),
          const SizedBox(height: 2),
          _section('Receive Payment'),

          _buttonGrid([

            _menu('Monthly Donation', Icons.people_alt_outlined, () => _push(HouseholdsPage(database: appDatabase))),

            _menu('General Donation', Icons.volunteer_activism_outlined, () => _push(FinancialEntryPage(database: appDatabase, title: 'General Donation', category: 'GD', receiptPrefix: 'GD', typeLabel: 'General Donation'))),

            _menu('Box Collection', Icons.inventory_2_outlined, () => _push(FinancialEntryPage(database: appDatabase, title: 'Box Collection', category: 'BD', receiptPrefix: 'BD', typeLabel: 'Box Collection'))),

            _menu('Other Income', Icons.payments_outlined, () => _push(FinancialEntryPage(database: appDatabase, title: 'Other Income', category: 'OI', receiptPrefix: 'OI', typeLabel: 'Other Income'))),

            _menu('Zakaat Received', Icons.account_balance_wallet_outlined, () => _push(FinancialEntryPage(database: appDatabase, title: 'Zakaat', category: 'ZK', receiptPrefix: 'ZK', typeLabel: 'Zakaat'))),

            _menu('Sadqa-e-Fitr', Icons.card_giftcard_outlined, () => _push(FinancialEntryPage(database: appDatabase, title: 'Sadqa-e-Fitr', category: 'SF', receiptPrefix: 'SF', typeLabel: 'Sadqa-e-Fitr'))),

            _menu('Qarz-e-Hassanah', Icons.handshake_outlined, () => _push(QarzaHassanahPage(database: appDatabase)), color: const Color(0xFF1E66C8)),

          ], centerLast: true),

          const SizedBox(height: 8),

          _section('Record Expenditure'),

          _buttonGrid([

            _menu('Zakaat', Icons.volunteer_activism_outlined, () => _push(ZakaatExpenditurePage(database: appDatabase)), destructive: true),

            _menu('Sadqa-e-Fitr', Icons.card_giftcard_outlined, () => _push(FundExpensePage(database: appDatabase, title: 'Sadqa-e-Fitr Expenditure', adjustmentType: 'SADQA_EXPENSE', prefix: 'SF-OUT', fundLabel: 'Sadqa-e-Fitr')), destructive: true),

            _menu('Other Expense', Icons.receipt_long_outlined, () => _push(FundExpensePage(database: appDatabase, title: 'Other Expense', adjustmentType: 'OTHER_EXPENSE', prefix: 'EX', fundLabel: 'Donations')), destructive: true),

          ]),

          const SizedBox(height: 6),

          _section("Today's Received"),

          Row(
            children: [
              Expanded(child: _miniAmount('Cash', s.todayCash)),
              const SizedBox(width: 8),
              Expanded(child: _miniAmount('Bank Transfer', s.todayBank)),
              const SizedBox(width: 8),
              Expanded(child: _miniAmount('Total Collected', s.todayCash + s.todayBank, emphasize: true)),
            ],
          ),

        ]);

  Widget _screenTwo(_FinancialSummary s) =>
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [

          _section('Funds Ledgers'),

          _fund('Donations', s.donationFund, () => _push(DonationsAccountsPage(database: appDatabase))),

          _fund('Zakaat', s.zakaat, () => _push(LedgerPage(database: appDatabase, title: 'Zakaat', account: 'ZAKAAT'))),

          _fund('Sadqa-e-Fitr', s.sadqaFitr, () => _push(LedgerPage(database: appDatabase, title: 'Sadqa-e-Fitr', account: 'SADQA_FITR'))),

          _fund('Total Available Funds', s.expectedTotal, () => _push(LedgerPage(database: appDatabase, title: 'Total Available Funds', account: 'TOTAL'))),

        ]);

  Widget _screenThree(_FinancialSummary s) {

    final actual = s.cashInHand + s.bankBalance;

    final difference = actual - s.expectedTotal;

    final balanced = difference.abs() < .005;

    final color = balanced ? kBrandGreen : (difference < 0 ? Colors.red.shade700 : Colors.green.shade700);

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [

        _section('Reconciliation'),

        _amountCard('Total Funds as per Ledgers', s.expectedTotal, showIcon: false),

        const SizedBox(height: 10),

        const Padding(

          padding: EdgeInsets.only(bottom: 8),

          child: Text(

            'Actual Cash & Bank',

            style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold),

          ),

        ),

        Row(

          children: [

            Expanded(

              child: _amountCard(

                'Cash in Hand',

                s.cashInHand,

                onTap: () => _editActualBalance(

                  'Cash in Hand',

                  s.cashInHand,

                  s.bankBalance,

                ),

                tapHint: 'Edit amount',

                showIcon: false,

              ),

            ),

            const SizedBox(width: 10),

            Expanded(

              child: _amountCard(

                'Bank Balance',

                s.bankBalance,

                onTap: () => _editActualBalance(

                  'Bank Balance',

                  s.bankBalance,

                  s.cashInHand,

                ),

                tapHint: 'Edit amount',

                showIcon: false,

              ),

            ),

          ],

        ),

        _amountCard('Actual Total', actual, showIcon: false),

        Card(

          child: Padding(

            padding: const EdgeInsets.all(16),

            child: Column(children: [

              Text(balanced ? 'BALANCED' : difference < 0 ? 'LESS THAN EXPECTED' : 'MORE THAN EXPECTED', style: TextStyle(color: color, fontSize: 19, fontWeight: FontWeight.bold)),

              const SizedBox(height: 6),

              Text(balanced ? '₹0.00' : '${difference > 0 ? '+' : '-'}₹${difference.abs().asAmount}', style: TextStyle(color: color, fontSize: 18, fontWeight: FontWeight.bold)),

            ]),

          ),

        ),

      ]);
  }

  Widget _singleScreen(_FinancialSummary s) => Column(
        children: [
          Expanded(
            child: PageView(
              controller: _pages,
              onPageChanged: (i) {
                if (mounted) setState(() => _index = i);
              },
              children: [
                _dashboardScrollable(s, _screenOne(s)),
                _dashboardScrollable(
                  s,
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _screenTwo(s),
                      const SizedBox(height: 14),
                      AppSectionHeader(title: 'Income & Expenses (Last 12 Months)', dense: true),
                      FinanceChartsLoader(database: appDatabase, reloadOn: _rev),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 2, bottom: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < 2; i++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: _index == i ? 18 : 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: _index == i ? kBrandGreen : Colors.black26,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                if (_index == 0) ...[
                  const SizedBox(width: 10),
                  const Text('Swipe left for Funds Ledgers \u203A', style: TextStyle(fontSize: 11, color: Colors.black54)),
                ],
              ],
            ),
          ),
        ],
      );

  void _drawerGo(VoidCallback action) {
    Navigator.of(context).pop();
    action();
  }

  Widget _drawerItem(IconData icon, String label, VoidCallback action) =>
      ListTile(
        dense: true,
        leading: Icon(icon, color: kBrandGreen),
        title: Text(label),
        onTap: () => _drawerGo(action),
      );

  Future<void> _choosePaperWidth() async {
    final choice = await showDialog<int>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Thermal receipt paper'),
        children: [
          for (final mm in const [58, 80])
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, mm),
              child: Text('$mm mm roll${PdfSupport.thermalWidthMm.round() == mm ? '  (current)' : ''}'),
            ),
        ],
      ),
    );
    if (choice == null) return;
    await PdfSupport.setThermalWidth(choice);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Receipts will now print for a $choice mm roll.')),
    );
  }

  void _openTotalFunds() => _push(_OwnerSummaryPage(
        owner: this,
        title: 'Total Funds',
        builder: (s) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _screenTwo(s),
            const SizedBox(height: 18),
            AppSectionHeader(title: 'Income & Expenses (Last 12 Months)'),
            FinanceChartsLoader(database: appDatabase, reloadOn: _rev),
          ],
        ),
      ));

  void _openReconciliation() => _push(_OwnerSummaryPage(
        owner: this,
        title: 'Reconciliation',
        builder: (s) => _screenThree(s),
      ));

  Widget _buildDrawer() {
    return Drawer(
      child: SafeArea(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(20, 20, 16, 16),
              color: kBrandGreen,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Al-Amin Baitul Maal',
                    style: TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    (currentUsername ?? '').trim().isEmpty ? 'User' : (currentUsername ?? '').trim(),
                    style: const TextStyle(color: Colors.white70),
                  ),
                ],
              ),
            ),
            ExpansionTile(
              leading: const Icon(Icons.menu_book_outlined, color: kBrandGreen),
              title: const Text('Funds Ledgers'),
              childrenPadding: const EdgeInsets.only(left: 16),
              children: [
                _drawerItem(Icons.account_balance_wallet_outlined, 'Donations', () => _push(DonationsAccountsPage(database: appDatabase))),
                _drawerItem(Icons.menu_book_outlined, 'Zakaat Ledger', () => _push(LedgerPage(database: appDatabase, title: 'Zakaat', account: 'ZAKAAT'))),
                _drawerItem(Icons.menu_book_outlined, 'Sadqa-e-Fitr Ledger', () => _push(LedgerPage(database: appDatabase, title: 'Sadqa-e-Fitr', account: 'SADQA_FITR'))),
              ],
            ),
            _drawerItem(Icons.summarize_outlined, 'Total Funds', _openTotalFunds),
            _drawerItem(Icons.balance_outlined, 'Reconciliation', _openReconciliation),
            _drawerItem(Icons.pending_actions_outlined, 'Unapproved Transactions', _showPendingApprovals),
            _drawerItem(Icons.bar_chart_rounded, 'Reports (Admin / Superuser)', () => _push(ReportsPage(database: appDatabase))),
            _drawerItem(Icons.verified_user_outlined, 'Change Approver (Superuser)', _changeApprover),
            const Divider(),
            _drawerItem(Icons.storage_outlined, 'Data Management', _openDataManagement),
            _drawerItem(Icons.sync_rounded, 'Sync & Refresh', _syncAndRefresh),
            _drawerItem(Icons.wifi_tethering, 'Wi-Fi Sync (Nearby Devices)', () => _push(WifiSyncPage(database: appDatabase, onChanged: _refresh))),
            _drawerItem(Icons.receipt_outlined, 'Receipt Paper (${PdfSupport.thermalWidthMm.round()} mm)', _choosePaperWidth),
            _drawerItem(Icons.switch_account_outlined, 'Switch User', _switchUser),
            _drawerItem(Icons.logout, 'Logout', _logout),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Widget _section(String text) => AppSectionHeader(title: text, dense: true);

  /// Buttons in rows of two (three on wide screens). With [centerLast], a
  /// lonely last button sits in the middle of its row.
  Widget _buttonGrid(List<Widget> children, {bool centerLast = false}) => LayoutBuilder(
        builder: (context, constraints) {
          final isDesktop = constraints.maxWidth >= 900;
          final columns = isDesktop ? 3 : 2;
          const gapX = 10.0;
          const gapY = 9.0;
          final itemWidth = (constraints.maxWidth - gapX * (columns - 1)) / columns;
          final itemHeight = itemWidth / (isDesktop ? 4.6 : 3.7);
          final rows = <Widget>[];
          for (var start = 0; start < children.length; start += columns) {
            final end = start + columns > children.length ? children.length : start + columns;
            final slice = children.sublist(start, end);
            final partial = slice.length < columns;
            rows.add(
              Padding(
                padding: const EdgeInsets.only(bottom: gapY),
                child: Row(
                  mainAxisAlignment: (partial && centerLast) ? MainAxisAlignment.center : MainAxisAlignment.start,
                  children: [
                    for (var i = 0; i < slice.length; i++) ...[
                      if (i > 0) const SizedBox(width: gapX),
                      SizedBox(width: itemWidth, height: itemHeight, child: slice[i]),
                    ],
                  ],
                ),
              ),
            );
          }
          return Column(children: rows);
        },
      );

  Widget _menu(
    String text,
    IconData icon,
    VoidCallback onTap, {
    bool destructive = false,
    Color? color,
  }) {
    return Action3DButton(
      title: text,
      icon: icon,
      onTap: onTap,
      destructive: destructive,
      accentColor: color,
    );
  }

  /// Small amount card for the three "Today's Received" figures; the amount
  /// shrinks to fit instead of being cut off.
  Widget _miniAmount(String title, double amount, {bool emphasize = false}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .96),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: kBrandGreen.withValues(alpha: emphasize ? .40 : .14)),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: .05), blurRadius: 6, offset: const Offset(0, 2)),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(title, maxLines: 1, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: Colors.black87)),
            ),
            const SizedBox(height: 3),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                '\u20B9${amount.asAmount}',
                maxLines: 1,
                style: TextStyle(color: kBrandGreen, fontSize: emphasize ? 16 : 15, fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
      );

  Widget _fund(String title, double amount, VoidCallback onTap) => AppBalanceCard(title: title, amount: amount, onTap: onTap, prominent: title == 'Total Available Funds');

  Widget _amountCard(

    String title,

    double amount, {

    VoidCallback? onTap,

    String tapHint = 'View ledger',

    bool showIcon = true,

  }) => AppBalanceCard(

        title: title,

        amount: amount,

        onTap: onTap,

        tapHint: tapHint,

        showIcon: showIcon,

      );

}

class _SwitchUserDialog extends StatefulWidget {

  final List<String> users;

  final String initialUser;

  const _SwitchUserDialog({required this.users, required this.initialUser});

  @override

  State<_SwitchUserDialog> createState() => _SwitchUserDialogState();

}

class _SwitchUserDialogState extends State<_SwitchUserDialog> {

  late String selected;

  late final TextEditingController passwordController;

  String? error;

  bool submitting = false;

  @override

  void initState() {

    super.initState();

    selected = widget.initialUser;

    passwordController = TextEditingController();

  }

  @override

  void dispose() {

    passwordController.dispose();

    super.dispose();

  }

  void _submit() {

    if (submitting) return;

    if (selected.isEmpty) {

      setState(() => error = 'Please select a user.');

      return;

    }

    if (!verifyUserPassword(selected, passwordController.text.trim())) {

      setState(() => error = 'Incorrect password.');

      return;

    }

    // Prevent a second submit while the text field is losing focus and the*

    // dialog route is being removed.*

    setState(() => submitting = true);

    FocusManager.instance.primaryFocus?.unfocus();

    WidgetsBinding.instance.addPostFrameCallback((_) {

      if (!mounted) return;

      Navigator.of(context, rootNavigator: true).pop(selected);

    });

  }

  @override

  Widget build(BuildContext context) {

    return AlertDialog(

      title: const Text('Switch User'),

      content: SizedBox(

        width: 420,

        child: SingleChildScrollView(

          child: Column(

            mainAxisSize: MainAxisSize.min,

            crossAxisAlignment: CrossAxisAlignment.stretch,

            children: [

              const Text('Select User', style: TextStyle(fontWeight: FontWeight.w700)),

              const SizedBox(height: 6),

              if (widget.users.isEmpty)

                const Text('No users available.')

              else

                ConstrainedBox(

                  constraints: const BoxConstraints(maxHeight: 190),

                  child: ListView.builder(

                    shrinkWrap: true,

                    itemCount: widget.users.length,

                    itemBuilder: (_, index) {

                      final user = widget.users[index];

                      return SimpleRadioTile<String>(

                        dense: true,

                        contentPadding: EdgeInsets.zero,

                        title: Text(user),

                        value: user,

                        groupValue: selected,

                        onChanged: submitting

                            ? null

                            : (value) {

                                if (value == null) return;

                                setState(() {

                                  selected = value;

                                  error = null;

                                  passwordController.clear();

                                });

                              },

                      );

                    },

                  ),

                ),

              const SizedBox(height: 10),

              TextField(

                controller: passwordController,

                enabled: !submitting,

                obscureText: true,

                maxLength: 4,

                keyboardType: TextInputType.number,

                textInputAction: TextInputAction.done,

                onSubmitted: (_) => _submit(),

                decoration: InputDecoration(

                  labelText: 'Password',

                  errorText: error,

                  border: const OutlineInputBorder(),

                  counterText: '',

                ),

              ),

            ],

          ),

        ),

      ),

      actions: [

        TextButton(

          onPressed: submitting ? null : () {

            FocusManager.instance.primaryFocus?.unfocus();

            Navigator.of(context, rootNavigator: true).pop();

          },

          child: const Text('Cancel'),

        ),

        FilledButton(

          onPressed: submitting ? null : _submit,

          child: Text(submitting ? 'Switching...' : 'Switch'),

        ),

      ],

    );

  }

}

class _FinancialSummary {

  final double monthlyDonation;

  final double generalDonation;

  final double boxCollection;

  final double otherIncome;

  final double zakaat;

  final double sadqaFitr;

  final double qarzaNet;

  final double todayCash;

  final double todayBank;

  final double cashInHand;

  final double bankBalance;

  final double donationFund;

  final double expectedTotal;

  const _FinancialSummary({

    required this.monthlyDonation,

    required this.generalDonation,

    required this.boxCollection,

    required this.otherIncome,

    required this.zakaat,

    required this.sadqaFitr,

    required this.qarzaNet,

    required this.todayCash,

    required this.todayBank,

    required this.cashInHand,

    required this.bankBalance,

    required this.donationFund,

    required this.expectedTotal,

  });

  _FinancialSummary copyWith({double? cashInHand, double? bankBalance}) =>
      _FinancialSummary(
        monthlyDonation: monthlyDonation,
        generalDonation: generalDonation,
        boxCollection: boxCollection,
        otherIncome: otherIncome,
        zakaat: zakaat,
        sadqaFitr: sadqaFitr,
        qarzaNet: qarzaNet,
        todayCash: todayCash,
        todayBank: todayBank,
        cashInHand: cashInHand ?? this.cashInHand,
        bankBalance: bankBalance ?? this.bankBalance,
        donationFund: donationFund,
        expectedTotal: expectedTotal,
      );

}

/// Full-page view of a dashboard section (Total Funds, Reconciliation).
/// It reloads whenever the dashboard refreshes, e.g. after editing Cash or Bank.
class _OwnerSummaryPage extends StatefulWidget {
  final _DashboardPageState owner;
  final String title;
  final Widget Function(_FinancialSummary summary) builder;

  const _OwnerSummaryPage({
    required this.owner,
    required this.title,
    required this.builder,
  });

  @override
  State<_OwnerSummaryPage> createState() => _OwnerSummaryPageState();
}

class _OwnerSummaryPageState extends State<_OwnerSummaryPage> {
  late Future<_FinancialSummary> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.owner._load();
    widget.owner._rev.addListener(_reload);
  }

  @override
  void dispose() {
    widget.owner._rev.removeListener(_reload);
    super.dispose();
  }

  void _reload() {
    if (!mounted) return;
    setState(() => _future = widget.owner._load());
  }

  Widget _content(_FinancialSummary summary) => SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: widget.builder(summary),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: IslamicBackground(
        // The latest figures are shown at once and update in place; the spinner
        // only appears the very first time, before anything has loaded.
        child: ValueListenableBuilder<_FinancialSummary?>(
          valueListenable: widget.owner._live,
          builder: (context, live, _) {
            if (live != null) return _content(live);
            return FutureBuilder<_FinancialSummary>(
              future: _future,
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snap.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('Could not load ${widget.title}:\n${snap.error}', textAlign: TextAlign.center),
                          const SizedBox(height: 12),
                          FilledButton.icon(
                            onPressed: _reload,
                            icon: const Icon(Icons.refresh),
                            label: const Text('RETRY'),
                          ),
                        ],
                      ),
                    ),
                  );
                }
                return _content(snap.data!);
              },
            );
          },
        ),
      ),
    );
  }
}
