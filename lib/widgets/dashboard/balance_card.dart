import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import '../../providers/dashboard_provider.dart';

class BalanceCard extends StatelessWidget {
  const BalanceCard({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<DashboardProvider>();
    final balance = provider.sensor.balance;
    final noCredit = balance <= 0.01;
    final lowBalance = !noCredit && balance < 500;
    final gradientColors = noCredit
        ? const [Color(0xFFFF7A7A), Color(0xFFE84D58)]
        : lowBalance
        ? const [Color(0xFFFFC65C), Color(0xFFF09A3E)]
        : const [Color(0xFFB8F24A), Color(0xFF8FD740)];
    return Container(
      constraints: const BoxConstraints(minHeight: 170),
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: gradientColors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(
                Icons.account_balance_wallet_outlined,
                color: AppColors.darkNavy,
                size: 22,
              ),
              SizedBox(width: 9),
              Text(
                "Available balance",
                style: TextStyle(
                  color: AppColors.darkNavy,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Spacer(),
              Icon(
                Icons.arrow_outward_rounded,
                color: AppColors.darkNavy,
                size: 20,
              ),
            ],
          ),
          const SizedBox(height: 22),

          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              "Rs. ${balance.toStringAsFixed(2)}",
              style: const TextStyle(
                fontSize: 36,
                fontWeight: FontWeight.w800,
                color: AppColors.darkNavy,
                letterSpacing: -1,
              ),
            ),
          ),

          const SizedBox(height: 8),

          Row(
            children: [
              const Icon(
                Icons.receipt_long_outlined,
                color: AppColors.darkNavy,
                size: 15,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Current usage cost: Rs. ${provider.actualUsageCostLkr.toStringAsFixed(2)}',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.darkNavy,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          if (noCredit || lowBalance) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(
                  noCredit
                      ? Icons.power_off_rounded
                      : Icons.warning_amber_rounded,
                  color: AppColors.darkNavy,
                  size: 16,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    noCredit
                        ? 'No credit — recharge to restore power'
                        : 'Low balance — recharge soon',
                    style: const TextStyle(
                      color: AppColors.darkNavy,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
