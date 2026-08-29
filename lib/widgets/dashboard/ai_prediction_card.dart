import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../providers/dashboard_provider.dart';

class AIPredictionCard extends StatelessWidget {
  const AIPredictionCard({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<DashboardProvider>();
    final forecast = provider.energyForecast;
    final credit = provider.balanceDepletion;
    final loading = provider.forecastStatus == ForecastStatus.loading;
    final offline = provider.forecastStatus == ForecastStatus.offline;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.cardNavy,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.auto_awesome_rounded,
                color: AppColors.neonGreen,
                size: 22,
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'AI forecast sample',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppColors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 19,
                  ),
                ),
              ),
              if (loading)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          const SizedBox(height: 22),
          Wrap(
            spacing: 18,
            runSpacing: 18,
            children: [
              _item(
                'Public-dataset estimate',
                forecast == null
                    ? '—'
                    : '${forecast.predictionKwh.toStringAsFixed(2)} units (kWh)',
              ),
              _item(
                'Sample forecast cost',
                forecast == null
                    ? '—'
                    : 'Rs. ${forecast.estimatedCostLkr.toStringAsFixed(0)}',
              ),
              _item('Credit from recent usage', _creditText(credit)),
            ],
          ),
          const SizedBox(height: 22),
          const Divider(color: AppColors.border),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                offline ? Icons.cloud_off_outlined : Icons.auto_graph,
                color: offline ? AppColors.warningOrange : AppColors.neonGreen,
                size: 22,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  offline
                      ? 'AI API is offline. Start the local Python server and refresh.'
                      : forecast == null
                      ? 'Waiting for the trained forecasting model…'
                      : credit == null
                      ? 'Public forecast sample. Waiting for the recent meter-usage credit estimate.'
                      : credit.message,
                  style: const TextStyle(
                    color: AppColors.textGrey,
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _item(String title, String value) => SizedBox(
    width: 140,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            value,
            style: const TextStyle(
              color: AppColors.neonGreen,
              fontWeight: FontWeight.bold,
              fontSize: 24,
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          title,
          style: const TextStyle(color: AppColors.textGrey, fontSize: 13),
        ),
      ],
    ),
  );

  String _creditText(dynamic credit) {
    if (credit == null) return '—';
    if (credit.ready && credit.remainingDays != null) {
      final days = credit.remainingDays as double;
      return days >= 3650
          ? 'More than 10 years'
          : '${days.toStringAsFixed(1)} days';
    }
    if (credit.status == 'no_recent_usage') return 'No recent usage';
    return 'Collecting data';
  }
}
