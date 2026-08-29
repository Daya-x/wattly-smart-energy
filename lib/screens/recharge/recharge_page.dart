import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../providers/dashboard_provider.dart';
import '../../services/hardware/esp32_service.dart';
import '../../widgets/common/app_shell.dart';

class RechargePage extends StatefulWidget {
  const RechargePage({super.key});

  @override
  State<RechargePage> createState() => _RechargePageState();
}

class _RechargePageState extends State<RechargePage> {
  final _amountController = TextEditingController(text: '500');
  double amount = 500;
  bool processing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<DashboardProvider>().loadRechargeHistory();
    });
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  void _selectAmount(double value) {
    setState(() {
      amount = value;
      _amountController.text = value.toStringAsFixed(0);
    });
  }

  Future<void> _recharge(double minimum) async {
    final entered = double.tryParse(_amountController.text.trim());
    if (entered == null || entered < minimum) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Enter at least Rs. ${minimum.toStringAsFixed(0)}'),
        ),
      );
      return;
    }
    amount = entered;
    final paymentConfirmed = await showDialog<bool>(
      context: context,
      builder: (context) => _DemoCardDialog(amount: amount),
    );
    if (paymentConfirmed != true || !mounted) return;
    setState(() => processing = true);
    try {
      final receipt = await context.read<DashboardProvider>().recharge(amount);
      if (!mounted) return;
      setState(() {
        processing = false;
      });
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          icon: const Icon(
            Icons.check_circle_rounded,
            color: AppColors.neonGreen,
            size: 46,
          ),
          title: const Text('Demo payment successful'),
          content: Text(
            'Receipt: ${receipt.id}\n'
            'Added: Rs. ${receipt.amountLkr.toStringAsFixed(2)}\n'
            'Balance: Rs. ${receipt.balanceLkr.toStringAsFixed(2)}',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Done'),
            ),
          ],
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => processing = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _setDemoZeroBalance(bool enabled) async {
    if (enabled) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          icon: const Icon(
            Icons.power_settings_new_rounded,
            color: AppColors.warningOrange,
            size: 44,
          ),
          title: const Text('Start zero-balance safety test?'),
          content: const Text(
            'This will temporarily show Rs. 0, send an OFF command to the '
            'physical relay, and block both dashboard and meter-button ON '
            'actions. Your real balance is kept safely and restores after '
            '5 minutes.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Start safe test'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }

    try {
      final status = await context.read<DashboardProvider>().setDemoZeroBalance(
        enabled,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(status.message)));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<DashboardProvider>();
    final balance = provider.sensor.balance;
    final minimum = provider.minimumRechargeLkr;
    final firstRecharge = !provider.hasRecharged;
    final receipts = provider.rechargeReceipts;
    final quickAmounts = [
      100,
      500,
      1000,
      2000,
      5000,
    ].where((value) => value >= minimum).toList();
    return AppShell(
      selectedIndex: 3,
      title: firstRecharge ? 'Activate meter' : 'Recharge',
      subtitle: firstRecharge
          ? 'Complete the first demo payment to activate prepaid credit.'
          : 'Top up your prepaid meter and review transactions.',
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 760;
          final recharge = SurfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  firstRecharge
                      ? 'First recharge • minimum Rs. 500'
                      : 'Choose or enter an amount • minimum Rs. 100',
                  style: const TextStyle(
                    color: AppColors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 18),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: quickAmounts
                      .map(
                        (value) => ChoiceChip(
                          label: Text('Rs. $value'),
                          selected: amount == value,
                          onSelected: (_) => _selectAmount(value.toDouble()),
                        ),
                      )
                      .toList(),
                ),
                const SizedBox(height: 18),
                TextField(
                  controller: _amountController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Manual amount (LKR)',
                    prefixText: 'Rs. ',
                    prefixIcon: Icon(Icons.payments_outlined),
                  ),
                  onChanged: (value) =>
                      setState(() => amount = double.tryParse(value) ?? 0),
                ),
                const SizedBox(height: 22),
                SizedBox(
                  width: double.infinity,
                  child: AppButton(
                    label: processing
                        ? 'Processing…'
                        : firstRecharge
                        ? 'Activate with demo payment'
                        : 'Continue to demo payment',
                    icon: Icons.lock_outline_rounded,
                    onPressed: processing ? null : () => _recharge(minimum),
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'DEMO ONLY • Never enter a real card number • No money is charged',
                  style: TextStyle(
                    color: AppColors.warningOrange,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          );
          final current = Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.neonGreen, Color(0xFF8FD740)],
              ),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'AVAILABLE BALANCE',
                  style: TextStyle(
                    color: AppColors.darkNavy,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.3,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Rs. ${balance.toStringAsFixed(2)}',
                  style: const TextStyle(
                    color: AppColors.darkNavy,
                    fontSize: 34,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  provider.demoZeroBalance
                      ? 'Temporary safety demonstration • real credit is safe'
                      : firstRecharge
                      ? 'Recharge to activate this meter'
                      : 'Credit reduces with measured energy usage',
                  style: const TextStyle(color: AppColors.darkNavy),
                ),
              ],
            ),
          );
          final zeroBalanceDemo = SurfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      provider.demoZeroBalance
                          ? Icons.lock_rounded
                          : Icons.science_outlined,
                      color: provider.demoZeroBalance
                          ? AppColors.warningRed
                          : AppColors.warningOrange,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        provider.demoZeroBalance
                            ? 'ZERO-BALANCE DEMO ACTIVE'
                            : 'Presentation safety test',
                        style: TextStyle(
                          color: provider.demoZeroBalance
                              ? AppColors.warningRed
                              : AppColors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  provider.demoZeroBalance
                      ? 'Displayed balance is Rs. 0. Relay ON is locked. '
                            'Your saved balance is Rs. '
                            '${provider.actualBalanceLkr.toStringAsFixed(2)}.'
                      : 'Temporarily demonstrate the Rs. 0 lockout without '
                            'changing the real prepaid balance.',
                  style: const TextStyle(color: AppColors.textGrey),
                ),
                if (provider.demoZeroBalance &&
                    provider.demoBalanceExpiresAt != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Automatic restore at '
                    '${DateFormat('h:mm a').format(provider.demoBalanceExpiresAt!)}',
                    style: const TextStyle(
                      color: AppColors.warningOrange,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
                if (provider.demoBalanceError != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    provider.demoBalanceError!,
                    style: const TextStyle(color: AppColors.warningRed),
                  ),
                ],
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: AppButton(
                    label: provider.demoBalanceInProgress
                        ? 'Updating…'
                        : provider.demoZeroBalance
                        ? 'Restore real balance'
                        : 'Test zero-balance lockout',
                    icon: provider.demoZeroBalance
                        ? Icons.restore_rounded
                        : Icons.lock_clock_outlined,
                    onPressed:
                        provider.demoBalanceInProgress ||
                            (!provider.demoZeroBalance &&
                                provider.actualBalanceLkr <= 0)
                        ? null
                        : () => _setDemoZeroBalance(!provider.demoZeroBalance),
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'DEMO ONLY • Restoring credit never turns the relay ON automatically',
                  style: TextStyle(
                    color: AppColors.warningOrange,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          );
          return Column(
            children: [
              compact
                  ? Column(
                      children: [current, const SizedBox(height: 16), recharge],
                    )
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: current),
                        const SizedBox(width: 16),
                        Expanded(flex: 2, child: recharge),
                      ],
                    ),
              const SizedBox(height: 18),
              zeroBalanceDemo,
              const SizedBox(height: 18),
              _Transactions(
                receipts: receipts,
                loading:
                    provider.rechargeHistoryStatus == ForecastStatus.loading,
                error: provider.rechargeHistoryError,
              ),
            ],
          );
        },
      ),
    );
  }
}

class _DemoCardDialog extends StatefulWidget {
  final double amount;

  const _DemoCardDialog({required this.amount});

  @override
  State<_DemoCardDialog> createState() => _DemoCardDialogState();
}

class _DemoCardDialogState extends State<_DemoCardDialog> {
  final _formKey = GlobalKey<FormState>();
  final _cardController = TextEditingController(text: '4242 4242 4242 4242');
  final _nameController = TextEditingController(text: 'WATTLY DEMO');
  final _expiryController = TextEditingController(text: '12/30');
  final _cvvController = TextEditingController(text: '123');

  @override
  void dispose() {
    _cardController.dispose();
    _nameController.dispose();
    _expiryController.dispose();
    _cvvController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Demo card payment'),
    content: SizedBox(
      width: 430,
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Pay Rs. ${widget.amount.toStringAsFixed(2)}',
                style: const TextStyle(
                  color: AppColors.neonGreen,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Use only the pre-filled test values. Card fields stay in this browser and are never sent or stored.',
                style: TextStyle(color: AppColors.textGrey, fontSize: 12),
              ),
              const SizedBox(height: 18),
              TextFormField(
                controller: _cardController,
                decoration: const InputDecoration(
                  labelText: 'Test card number',
                ),
                validator: (value) =>
                    value?.replaceAll(' ', '') == '4242424242424242'
                    ? null
                    : 'Use the Wattly test card number',
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Cardholder'),
                validator: (value) =>
                    value == null || value.trim().isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _expiryController,
                      decoration: const InputDecoration(labelText: 'Expiry'),
                      validator: (value) =>
                          value == '12/30' ? null : 'Use test expiry 12/30',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _cvvController,
                      obscureText: true,
                      decoration: const InputDecoration(labelText: 'Test CVV'),
                      validator: (value) =>
                          value == '123' ? null : 'Use test CVV 123',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context, false),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () {
          if (_formKey.currentState!.validate()) {
            Navigator.pop(context, true);
          }
        },
        child: const Text('Complete demo payment'),
      ),
    ],
  );
}

class _Transactions extends StatelessWidget {
  final List<DemoRechargeReceipt> receipts;
  final bool loading;
  final String? error;

  const _Transactions({
    required this.receipts,
    required this.loading,
    required this.error,
  });

  @override
  Widget build(BuildContext context) => SurfaceCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Recent demo transactions',
          style: TextStyle(
            color: AppColors.white,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 16),
        if (loading && receipts.isEmpty)
          const Text(
            'Loading transactions…',
            style: TextStyle(color: AppColors.textGrey),
          )
        else if (error != null && receipts.isEmpty)
          Text(error!, style: const TextStyle(color: AppColors.warningOrange))
        else if (receipts.isEmpty)
          const Text(
            'No demo payments recorded yet.',
            style: TextStyle(color: AppColors.textGrey),
          )
        else
          for (final receipt in receipts)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const CircleAvatar(
                backgroundColor: AppColors.lightCard,
                child: Icon(Icons.add_rounded, color: AppColors.neonGreen),
              ),
              title: Text(
                receipt.id,
                style: const TextStyle(color: AppColors.white),
              ),
              subtitle: Text(
                DateFormat('MMM d, yyyy • h:mm a').format(receipt.createdAt),
                style: const TextStyle(color: AppColors.textGrey),
              ),
              trailing: Text(
                '+ Rs. ${receipt.amountLkr.toStringAsFixed(2)}',
                style: const TextStyle(
                  color: AppColors.neonGreen,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
      ],
    ),
  );
}
