import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fl_chart/fl_chart.dart';
import '../theme/status_colors.dart';

class DashboardCharts {
  static StatusColors _statusColors(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? StatusColors.dark
        : StatusColors.light;
  }

  // Charts Section
  static Widget buildChartsSection({
    required List<Map<String, dynamic>> dailySales,
    required List<Map<String, dynamic>> categorySales,
    required List<Map<String, dynamic>> dailyProfits,
    required Map<String, dynamic> inventoryAging,
    required bool isLoading,
  }) {
    if (isLoading) {
      return Container(
        padding: const EdgeInsets.all(48),
        child: const Center(child: CircularProgressIndicator()),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Builder(
          builder: (context) => Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: Theme.of(
                    context,
                  ).colorScheme.primary.withValues(alpha: 0.1),
                  border: Border.all(
                    color: Theme.of(
                      context,
                    ).colorScheme.primary.withValues(alpha: 0.2),
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.bar_chart,
                  size: 16,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'Analytics & Insights',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
        Builder(
          builder: (ctx) =>
              SizedBox(height: MediaQuery.of(ctx).size.width < 480 ? 12 : 16),
        ),
        LayoutBuilder(
          builder: (context, constraints) {
            final isDesktop = constraints.maxWidth > 768;
            return Column(
              children: [
                // Row 1: Revenue Charts
                isDesktop
                    ? Row(
                        children: [
                          Expanded(child: _buildDailySalesChart(dailySales)),
                          const SizedBox(width: 16),
                          Expanded(child: _buildProfitChart(dailyProfits)),
                        ],
                      )
                    : Column(
                        children: [
                          _buildDailySalesChart(dailySales),
                          SizedBox(
                            height: MediaQuery.of(context).size.width < 480
                                ? 12
                                : 16,
                          ),
                          _buildProfitChart(dailyProfits),
                        ],
                      ),
                const SizedBox(height: 16),
                // Row 2: Category & Inventory Charts
                isDesktop
                    ? Row(
                        children: [
                          Expanded(
                            child: _buildCategorySalesChart(categorySales),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: _buildInventoryAgingChart(inventoryAging),
                          ),
                        ],
                      )
                    : Column(
                        children: [
                          _buildCategorySalesChart(categorySales),
                          const SizedBox(height: 16),
                          _buildInventoryAgingChart(inventoryAging),
                        ],
                      ),
              ],
            );
          },
        ),
      ],
    );
  }

  // Tabbed Analytics Section
  static Widget buildTabbedAnalytics({
    required int selectedTab,
    required ValueChanged<int> onTabChanged,
    required List<Map<String, dynamic>> dailySales,
    required List<Map<String, dynamic>> categorySales,
    required List<Map<String, dynamic>> dailyProfits,
    required Map<String, dynamic> inventoryAging,
    required Map<String, dynamic> realtimeStats,
    required Map<String, dynamic> growthData,
    required bool isLoading,
  }) {
    if (isLoading) {
      return Container(
        height: 240,
        alignment: Alignment.center,
        child: const CircularProgressIndicator(),
      );
    }

    final tabs = [
      {'title': 'Revenue & Profit', 'icon': Icons.trending_up},
      {'title': 'Categories', 'icon': Icons.pie_chart_outline},
      {'title': 'Stock Health', 'icon': Icons.inventory_2_outlined},
      {'title': 'Live & Growth', 'icon': Icons.bolt},
    ];

    return Builder(
      builder: (context) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary.withAlpha(26),
                    border: Border.all(
                      color: Theme.of(context).colorScheme.primary.withAlpha(51),
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.insights_rounded,
                    size: 16,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 10),
                const Text(
                  'Analytics & Insights',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: List.generate(tabs.length, (index) {
                  final isSelected = selectedTab == index;
                  final item = tabs[index];
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () {
                          HapticFeedback.selectionClick();
                          onTabChanged(index);
                        },
                        borderRadius: BorderRadius.circular(20),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? Theme.of(context).colorScheme.primary
                                : Theme.of(context).cardColor,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: isSelected
                                  ? Theme.of(context).colorScheme.primary
                                  : Theme.of(context).dividerColor.withAlpha(40),
                            ),
                            boxShadow: isSelected
                                ? [
                                    BoxShadow(
                                      color: Theme.of(context).colorScheme.primary.withAlpha(77),
                                      blurRadius: 10,
                                      offset: const Offset(0, 4),
                                    ),
                                  ]
                                : null,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                item['icon'] as IconData,
                                size: 15,
                                color: isSelected
                                    ? Theme.of(context).colorScheme.onPrimary
                                    : Theme.of(context).colorScheme.onSurfaceVariant,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                item['title'] as String,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                  color: isSelected
                                      ? Theme.of(context).colorScheme.onPrimary
                                      : Theme.of(context).colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ),
            const SizedBox(height: 16),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              child: KeyedSubtree(
                key: ValueKey<int>(selectedTab),
                child: Builder(
                  builder: (context) {
                    switch (selectedTab) {
                      case 0:
                        return LayoutBuilder(
                          builder: (context, c) {
                            if (c.maxWidth > 768) {
                              return Row(
                                children: [
                                  Expanded(child: _buildDailySalesChart(dailySales)),
                                  const SizedBox(width: 16),
                                  Expanded(child: _buildProfitChart(dailyProfits)),
                                ],
                              );
                            }
                            return Column(
                              children: [
                                _buildDailySalesChart(dailySales),
                                const SizedBox(height: 14),
                                _buildProfitChart(dailyProfits),
                              ],
                            );
                          },
                        );
                      case 1:
                        return _buildCategorySalesChart(categorySales);
                      case 2:
                        return _buildInventoryAgingChart(inventoryAging);
                      case 3:
                        return Column(
                          children: [
                            buildRealtimeMetrics(stats: realtimeStats, isLoading: false),
                            const SizedBox(height: 14),
                            buildGrowthAnalytics(growthData: growthData, isLoading: false),
                          ],
                        );
                      default:
                        return const SizedBox.shrink();
                    }
                  },
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  static String _formatAxisValue(double value) {
    if (value == 0) return '₹0';
    final absVal = value.abs();
    if (absVal >= 100000) {
      final inLakh = value / 100000;
      return '₹${inLakh.toStringAsFixed(1)}L';
    } else if (absVal >= 1000) {
      final inK = value / 1000;
      return inK % 1 == 0
          ? '₹${inK.toStringAsFixed(0)}k'
          : '₹${inK.toStringAsFixed(1)}k';
    } else {
      return '₹${value.toStringAsFixed(0)}';
    }
  }

  static Widget _buildDailySalesChart(List<Map<String, dynamic>> data) {
    return Builder(
      builder: (context) => _HoverCard(
        duration: const Duration(milliseconds: 200),
        builder: (hovered) => Container(
          padding: EdgeInsets.all(
            MediaQuery.of(context).size.width < 480 ? 12 : 16,
          ),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: Theme.of(
                context,
              ).dividerColor.withValues(alpha: hovered ? 0.2 : 0.1),
            ),
            boxShadow: [
              BoxShadow(
                color: Theme.of(
                  context,
                ).shadowColor.withValues(alpha: hovered ? 0.12 : 0.05),
                blurRadius: hovered ? 14 : 10,
                offset: Offset(0, hovered ? 6 : 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Daily Sales Revenue',
                    style: TextStyle(
                      fontSize: MediaQuery.of(context).size.width < 480
                          ? 14
                          : 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Icon(
                    Icons.currency_rupee,
                    color: Theme.of(
                      context,
                    ).textTheme.bodyMedium?.color?.withValues(alpha: 0.6),
                    size: 20,
                  ),
                ],
              ),
              Builder(
                builder: (context) => SizedBox(
                  height: MediaQuery.of(context).size.width < 480 ? 12 : 16,
                ),
              ),
              SizedBox(
                height: _chartHeight(context),
                child: data.isEmpty
                    ? _buildEmptyState(
                        context,
                        'No sales data available',
                        Icons.bar_chart_rounded,
                      )
                    : BarChart(
                        BarChartData(
                          alignment: BarChartAlignment.spaceAround,
                          maxY:
                              data
                                  .map((e) => e['revenue'] as double)
                                  .reduce((a, b) => a > b ? a : b) *
                              1.2,
                          barTouchData: BarTouchData(enabled: true),
                          titlesData: FlTitlesData(
                            show: true,
                            bottomTitles: AxisTitles(
                              sideTitles: SideTitles(
                                showTitles: true,
                                getTitlesWidget: (value, meta) {
                                  if (value.toInt() < data.length) {
                                    return Text(
                                      data[value.toInt()]['date'],
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: Theme.of(
                                          context,
                                        ).textTheme.bodySmall?.color,
                                      ),
                                    );
                                  }
                                  return const Text('');
                                },
                              ),
                            ),
                            leftTitles: AxisTitles(
                              sideTitles: SideTitles(
                                showTitles: true,
                                reservedSize: 46,
                                getTitlesWidget: (value, meta) {
                                  return Text(
                                    _formatAxisValue(value),
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: Theme.of(
                                        context,
                                      ).textTheme.bodySmall?.color,
                                    ),
                                  );
                                },
                              ),
                            ),
                            topTitles: const AxisTitles(
                              sideTitles: SideTitles(showTitles: false),
                            ),
                            rightTitles: const AxisTitles(
                              sideTitles: SideTitles(showTitles: false),
                            ),
                          ),
                          borderData: FlBorderData(show: false),
                          barGroups: data.asMap().entries.map((entry) {
                            return BarChartGroupData(
                              x: entry.key,
                              barRods: [
                                BarChartRodData(
                                  toY: entry.value['revenue'],
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.primary.withValues(alpha: 0.9),
                                  width: 16,
                                  borderRadius: const BorderRadius.only(
                                    topLeft: Radius.circular(4),
                                    topRight: Radius.circular(4),
                                  ),
                                ),
                              ],
                            );
                          }).toList(),
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Widget _buildProfitChart(List<Map<String, dynamic>> data) {
    return Builder(
      builder: (context) => _HoverCard(
        duration: const Duration(milliseconds: 200),
        builder: (hovered) => Container(
          padding: EdgeInsets.all(
            MediaQuery.of(context).size.width < 480 ? 12 : 16,
          ),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: Theme.of(
                context,
              ).dividerColor.withValues(alpha: hovered ? 0.2 : 0.1),
            ),
            boxShadow: [
              BoxShadow(
                color: Theme.of(
                  context,
                ).shadowColor.withValues(alpha: hovered ? 0.12 : 0.05),
                blurRadius: hovered ? 14 : 10,
                offset: Offset(0, hovered ? 6 : 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Daily Profit/Loss Trend',
                    style: TextStyle(
                      fontSize: MediaQuery.of(context).size.width < 480
                          ? 14
                          : 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Builder(
                    builder: (context) => Icon(
                      Icons.trending_up,
                      color: Theme.of(context).colorScheme.secondary,
                      size: 20,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: _chartHeight(context),
                child: data.isEmpty
                    ? _buildEmptyState(
                        context,
                        'No profit data available',
                        Icons.trending_up_rounded,
                      )
                    : LineChart(
                        LineChartData(
                          gridData: const FlGridData(show: true),
                          titlesData: FlTitlesData(
                            bottomTitles: AxisTitles(
                              sideTitles: SideTitles(
                                showTitles: true,
                                getTitlesWidget: (value, meta) {
                                  if (value.toInt() < data.length) {
                                    return Text(
                                      data[value.toInt()]['date'],
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: Theme.of(
                                          context,
                                        ).textTheme.bodySmall?.color,
                                      ),
                                    );
                                  }
                                  return const Text('');
                                },
                              ),
                            ),
                            leftTitles: AxisTitles(
                              sideTitles: SideTitles(
                                showTitles: true,
                                reservedSize: 46,
                                getTitlesWidget: (value, meta) {
                                  return Text(
                                    _formatAxisValue(value),
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: Theme.of(
                                        context,
                                      ).textTheme.bodySmall?.color,
                                    ),
                                  );
                                },
                              ),
                            ),
                            topTitles: const AxisTitles(
                              sideTitles: SideTitles(showTitles: false),
                            ),
                            rightTitles: const AxisTitles(
                              sideTitles: SideTitles(showTitles: false),
                            ),
                          ),
                          borderData: FlBorderData(show: true),
                          lineBarsData: [
                            LineChartBarData(
                              spots: data.asMap().entries.map((entry) {
                                return FlSpot(
                                  entry.key.toDouble(),
                                  entry.value['profit'],
                                );
                              }).toList(),
                              isCurved: true,
                              color: Theme.of(context).colorScheme.secondary,
                              barWidth: 3,
                              dotData: const FlDotData(show: true),
                              belowBarData: BarAreaData(
                                show: true,
                                color: Theme.of(
                                  context,
                                ).colorScheme.secondary.withValues(alpha: 0.12),
                              ),
                            ),
                          ],
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Widget _buildCategorySalesChart(List<Map<String, dynamic>> data) {
    return Builder(
      builder: (context) => _HoverCard(
        duration: const Duration(milliseconds: 200),
        builder: (hovered) => Container(
          padding: EdgeInsets.all(
            MediaQuery.of(context).size.width < 480 ? 12 : 16,
          ),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: Theme.of(
                context,
              ).dividerColor.withValues(alpha: hovered ? 0.2 : 0.1),
            ),
            boxShadow: [
              BoxShadow(
                color: Theme.of(
                  context,
                ).shadowColor.withValues(alpha: hovered ? 0.12 : 0.05),
                blurRadius: hovered ? 14 : 10,
                offset: Offset(0, hovered ? 6 : 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Inventory Value by Category',
                    style: TextStyle(
                      fontSize: MediaQuery.of(context).size.width < 480
                          ? 14
                          : 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Icon(
                    Icons.pie_chart,
                    color: Theme.of(
                      context,
                    ).textTheme.bodyMedium?.color?.withValues(alpha: 0.6),
                    size: 20,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: _chartHeight(context),
                child: data.isEmpty
                    ? _buildEmptyState(
                        context,
                        'No category data available',
                        Icons.pie_chart_rounded,
                      )
                    : Builder(
                        builder: (context) {
                          final status = _statusColors(context);
                          final colors = [
                            Theme.of(context).colorScheme.primary,
                            Theme.of(context).colorScheme.secondary,
                            status.warning,
                            status.success,
                            Theme.of(context).colorScheme.error,
                            status.info,
                          ];
                          final total = data.fold<double>(
                            0.0,
                            (sum, e) =>
                                sum +
                                (e['revenue'] is num
                                    ? (e['revenue'] as num).toDouble()
                                    : (e['revenue'] ?? 0.0) as double),
                          );

                          final sections = data.asMap().entries.map((entry) {
                            final valueNum = entry.value['revenue'];
                            final value = valueNum is num
                                ? valueNum.toDouble()
                                : (valueNum ?? 0.0) as double;
                            final pct = total > 0 ? (value / total) * 100 : 0;
                            return PieChartSectionData(
                              value: value,
                              // Show only % on chart to avoid long labels overlapping
                              title: pct >= 8
                                  ? '${pct.toStringAsFixed(0)}%'
                                  : '',
                              color: colors[entry.key % colors.length],
                              radius: 64,
                              titleStyle: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            );
                          }).toList();

                          return Stack(
                            alignment: Alignment.center,
                            children: [
                              PieChart(
                                PieChartData(
                                  sections: sections,
                                  centerSpaceRadius: 50,
                                  sectionsSpace: 4,
                                ),
                              ),
                              // Center summary
                              Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    'Total',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.color
                                          ?.withValues(alpha: 0.7),
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '₹${total.toStringAsFixed(0)}',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                      color: Theme.of(
                                        context,
                                      ).textTheme.titleMedium?.color,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          );
                        },
                      ),
              ),
              const SizedBox(height: 12),
              if (data.isNotEmpty) _buildCategoryLegend(context, data),
            ],
          ),
        ),
      ),
    );
  }

  static Widget _buildInventoryAgingChart(Map<String, dynamic> data) {
    final fresh = data['fresh'] ?? 0;
    final aging = data['aging'] ?? 0;
    final dead = data['dead'] ?? 0;
    final total = fresh + aging + dead;

    return Builder(
      builder: (context) => _HoverCard(
        duration: const Duration(milliseconds: 200),
        builder: (hovered) => Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: Theme.of(
                context,
              ).dividerColor.withValues(alpha: hovered ? 0.2 : 0.1),
            ),
            boxShadow: [
              BoxShadow(
                color: Theme.of(
                  context,
                ).shadowColor.withValues(alpha: hovered ? 0.12 : 0.05),
                blurRadius: hovered ? 14 : 10,
                offset: Offset(0, hovered ? 6 : 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Inventory Aging Analysis',
                    style: TextStyle(
                      fontSize: MediaQuery.of(context).size.width < 480
                          ? 14
                          : 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Icon(
                    Icons.access_time,
                    color: Theme.of(
                      context,
                    ).textTheme.bodyMedium?.color?.withValues(alpha: 0.6),
                    size: 20,
                  ),
                ],
              ),
              SizedBox(
                height: MediaQuery.of(context).size.width < 480 ? 12 : 16,
              ),
              SizedBox(
                height: _chartHeight(context),
                child: total == 0
                    ? _buildEmptyState(
                        context,
                        'No inventory data available',
                        Icons.inventory_2_rounded,
                      )
                    : PieChart(
                        PieChartData(
                          sections: [
                            PieChartSectionData(
                              value: fresh.toDouble(),
                              title: fresh > 0
                                  ? '${((fresh / total) * 100).toStringAsFixed(0)}%'
                                  : '',
                              color: _statusColors(context).success,
                              radius: 60,
                              titleStyle: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                              titlePositionPercentageOffset: 0.55,
                            ),
                            PieChartSectionData(
                              value: aging.toDouble(),
                              title: aging > 0 && (aging / total) >= 0.08
                                  ? '${((aging / total) * 100).toStringAsFixed(0)}%'
                                  : '',
                              color: _statusColors(context).warning,
                              radius: 60,
                              titleStyle: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                              titlePositionPercentageOffset: 0.55,
                            ),
                            PieChartSectionData(
                              value: dead.toDouble(),
                              title: dead > 0 && (dead / total) >= 0.08
                                  ? '${((dead / total) * 100).toStringAsFixed(0)}%'
                                  : '',
                              color: Theme.of(context).colorScheme.error,
                              radius: 60,
                              titleStyle: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                              titlePositionPercentageOffset: 0.55,
                            ),
                          ],
                          centerSpaceRadius: 40,
                          sectionsSpace: 2,
                        ),
                      ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildAgingSummary(
                    'Fresh (0-30d)',
                    fresh,
                    _statusColors(context).success,
                    context,
                  ),
                  _buildAgingSummary(
                    'Aging (31-60d)',
                    aging,
                    _statusColors(context).warning,
                    context,
                  ),
                  _buildAgingSummary(
                    'Dead (60+d)',
                    dead,
                    Theme.of(context).colorScheme.error,
                    context,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Widget _buildAgingSummary(
    String label,
    num value,
    Color color,
    BuildContext context,
  ) {
    return Column(
      children: [
        Text(
          value is int || value == value.roundToDouble()
              ? value.toInt().toString()
              : value.toStringAsFixed(1),
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(
              context,
            ).textTheme.bodyMedium?.color?.withValues(alpha: 0.6),
          ),
        ),
      ],
    );
  }

  // Real-time Metrics Section
  static Widget buildRealtimeMetrics({
    required Map<String, dynamic> stats,
    required bool isLoading,
  }) {
    if (isLoading) {
      return Container(
        padding: const EdgeInsets.all(48),
        child: const Center(child: CircularProgressIndicator()),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Builder(
          builder: (context) => Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: _statusColors(context).success.withValues(alpha: 0.1),
                  border: Border.all(
                    color: _statusColors(
                      context,
                    ).success.withValues(alpha: 0.2),
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.show_chart,
                  size: 16,
                  color: _statusColors(context).success,
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'Live Business Metrics',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: _statusColors(context).success,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Live',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(
                        context,
                      ).textTheme.bodyMedium?.color?.withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        Builder(
          builder: (ctx) =>
              SizedBox(height: MediaQuery.of(ctx).size.width < 480 ? 12 : 24),
        ),
        LayoutBuilder(
          builder: (context, constraints) {
            final crossAxisCount = constraints.maxWidth > 1024
                ? 4
                : constraints.maxWidth > 640
                ? 3
                : 2;
            final isMobile = constraints.maxWidth < 480;
            return GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: crossAxisCount,
              crossAxisSpacing: isMobile ? 12 : 16,
              mainAxisSpacing: isMobile ? 12 : 16,
              childAspectRatio: isMobile ? 1.35 : 1.2,
              children: [
                _buildRealtimeCard(
                  'Today\'s Sales',
                  '${stats['todaysSales'] ?? 0}',
                  'transactions',
                  Icons.flash_on,
                  Theme.of(context).colorScheme.secondary,
                  '₹${(stats['todaysRevenue'] ?? 0).toStringAsFixed(0)} revenue',
                ),
                _buildRealtimeCard(
                  'Items Sold Today',
                  '${stats['itemsSold'] ?? 0}',
                  'units',
                  Icons.inventory,
                  _statusColors(context).success,
                  'Moving inventory',
                ),
                _buildRealtimeCard(
                  'Out of Stock',
                  '${stats['outOfStock'] ?? 0}',
                  'items',
                  Icons.warning,
                  Theme.of(context).colorScheme.error,
                  'Need restocking',
                ),
                _buildRealtimeCard(
                  'Top Seller',
                  stats['topSeller'] ?? 'No data',
                  '',
                  Icons.star,
                  Theme.of(context).colorScheme.primary,
                  'Best performing',
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  static Widget _buildRealtimeCard(
    String title,
    String value,
    String unit,
    IconData icon,
    Color color,
    String subtitle,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color.withValues(alpha: 0.1), color.withValues(alpha: 0.05)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: color,
                ),
              ),
              Icon(icon, color: color, size: 20),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Flexible(
                child: Text(
                  value,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: color,
                    height: 1.2,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (unit.isNotEmpty) ...[
                const SizedBox(width: 4),
                Text(unit, style: TextStyle(fontSize: 12, color: color)),
              ],
            ],
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: TextStyle(fontSize: 10, color: color.withValues(alpha: 0.8)),
          ),
        ],
      ),
    );
  }

  // Growth Analytics Section
  static Widget buildGrowthAnalytics({
    required Map<String, dynamic> growthData,
    required bool isLoading,
  }) {
    if (isLoading) {
      return Container(
        padding: const EdgeInsets.all(48),
        child: const Center(child: CircularProgressIndicator()),
      );
    }

    // Growth values are consumed inside the specific cards; no local vars needed here.

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Builder(
          builder: (context) => Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: Theme.of(
                    context,
                  ).colorScheme.primary.withValues(alpha: 0.1),
                  border: Border.all(
                    color: Theme.of(
                      context,
                    ).colorScheme.primary.withValues(alpha: 0.2),
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.trending_up,
                  size: 16,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'Growth Analytics',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        LayoutBuilder(
          builder: (context, constraints) {
            final isDesktop = constraints.maxWidth > 768;
            return isDesktop
                ? Row(
                    children: [
                      Expanded(child: _buildRevenueGrowthCard(growthData)),
                      const SizedBox(width: 16),
                      Expanded(child: _buildSalesGrowthCard(growthData)),
                    ],
                  )
                : Column(
                    children: [
                      _buildRevenueGrowthCard(growthData),
                      const SizedBox(height: 16),
                      _buildSalesGrowthCard(growthData),
                    ],
                  );
          },
        ),
      ],
    );
  }

  static Widget _buildRevenueGrowthCard(Map<String, dynamic> data) {
    final growth = data['revenueGrowth'] ?? 0.0;
    final current = data['currentRevenue'] ?? 0.0;
    final previous = data['previousRevenue'] ?? 0.0;

    return Builder(
      builder: (context) => _HoverCard(
        duration: const Duration(milliseconds: 200),
        builder: (hovered) => Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: Theme.of(
                context,
              ).dividerColor.withValues(alpha: hovered ? 0.2 : 0.1),
            ),
            boxShadow: [
              BoxShadow(
                color: Theme.of(
                  context,
                ).shadowColor.withValues(alpha: hovered ? 0.12 : 0.05),
                blurRadius: hovered ? 14 : 10,
                offset: Offset(0, hovered ? 6 : 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Monthly Revenue Growth',
                    style: TextStyle(
                      fontSize: MediaQuery.of(context).size.width < 480
                          ? 14
                          : 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Icon(
                    growth >= 0 ? Icons.trending_up : Icons.trending_down,
                    color: growth >= 0
                        ? _statusColors(context).success
                        : Theme.of(context).colorScheme.error,
                    size: 20,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Current Month:'),
                  Text('₹${current.toStringAsFixed(0)}'),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Previous Month:'),
                  Text('₹${previous.toStringAsFixed(0)}'),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Growth Rate:'),
                  Text(
                    '${growth >= 0 ? '+' : ''}${growth.toStringAsFixed(1)}%',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: growth >= 0 ? Colors.green : Colors.red,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: (growth.abs() / 100).clamp(0.0, 1.0),
                backgroundColor: Theme.of(
                  context,
                ).dividerColor.withValues(alpha: 0.3),
                valueColor: AlwaysStoppedAnimation<Color>(
                  growth >= 0 ? Colors.green : Colors.red,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Widget _buildSalesGrowthCard(Map<String, dynamic> data) {
    final growth = data['salesGrowth'] ?? 0.0;

    return Builder(
      builder: (context) => _HoverCard(
        duration: const Duration(milliseconds: 200),
        builder: (hovered) => Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: Theme.of(
                context,
              ).dividerColor.withValues(alpha: hovered ? 0.2 : 0.1),
            ),
            boxShadow: [
              BoxShadow(
                color: Theme.of(
                  context,
                ).shadowColor.withValues(alpha: hovered ? 0.12 : 0.05),
                blurRadius: hovered ? 14 : 10,
                offset: Offset(0, hovered ? 6 : 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Sales Volume Growth',
                    style: TextStyle(
                      fontSize: MediaQuery.of(context).size.width < 480
                          ? 14
                          : 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Icon(
                    growth >= 0 ? Icons.trending_up : Icons.trending_down,
                    color: growth >= 0 ? Colors.green : Colors.red,
                    size: 20,
                  ),
                ],
              ),
              SizedBox(
                height: MediaQuery.of(context).size.width < 480 ? 12 : 16,
              ),
              Center(
                child: Column(
                  children: [
                    Text(
                      '${growth >= 0 ? '+' : ''}${growth.toStringAsFixed(1)}%',
                      style: TextStyle(
                        fontSize: MediaQuery.of(context).size.width < 480
                            ? 28
                            : 32,
                        fontWeight: FontWeight.bold,
                        color: growth >= 0 ? Colors.green : Colors.red,
                      ),
                    ),
                    Text(
                      'Sales count change',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(
                          context,
                        ).textTheme.bodyMedium?.color?.withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(
                height: MediaQuery.of(context).size.width < 480 ? 12 : 16,
              ),
              Center(
                child: SizedBox(
                  width: MediaQuery.of(context).size.width < 480 ? 72 : 80,
                  height: MediaQuery.of(context).size.width < 480 ? 72 : 80,
                  child: CircularProgressIndicator(
                    value: (growth.abs() / 100).clamp(0.0, 1.0),
                    strokeWidth: 8,
                    backgroundColor: Theme.of(
                      context,
                    ).dividerColor.withValues(alpha: 0.3),
                    valueColor: AlwaysStoppedAnimation<Color>(
                      growth >= 0 ? Colors.green : Colors.red,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Enhanced empty state widget with icon and styled messaging
  static Widget _buildEmptyState(
    BuildContext context,
    String message,
    IconData icon,
  ) {
    final color = Theme.of(
      context,
    ).textTheme.bodyMedium?.color?.withValues(alpha: 0.5);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(
                context,
              ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 32, color: color),
          ),
          const SizedBox(height: 12),
          Text(
            message,
            style: TextStyle(
              fontSize: 14,
              color: color,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Record transactions to see data here',
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(
                context,
              ).textTheme.bodySmall?.color?.withValues(alpha: 0.4),
            ),
          ),
        ],
      ),
    );
  }

  /// Category legend with "Show More" functionality
  static Widget _buildCategoryLegend(
    BuildContext context,
    List<Map<String, dynamic>> data,
  ) {
    const int visibleLimit = 6;
    final showAll = ValueNotifier<bool>(data.length <= visibleLimit);
    final status = _statusColors(context);
    final colors = [
      Theme.of(context).colorScheme.primary,
      Theme.of(context).colorScheme.secondary,
      status.warning,
      status.success,
      Theme.of(context).colorScheme.error,
      status.info,
    ];
    final total = data.fold<double>(
      0.0,
      (sum, e) =>
          sum +
          (e['revenue'] is num
              ? (e['revenue'] as num).toDouble()
              : (e['revenue'] ?? 0.0) as double),
    );

    Widget buildLegendItem(int index, Map<String, dynamic> entry) {
      final valueNum = entry['revenue'];
      final value = valueNum is num
          ? valueNum.toDouble()
          : (valueNum ?? 0.0) as double;
      final pct = total > 0 ? (value / total) * 100 : 0;
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: Theme.of(context).dividerColor.withValues(alpha: 0.2),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: colors[index % colors.length],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              entry['category'] ?? 'Unknown',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).textTheme.bodyMedium?.color,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              '₹${value.toStringAsFixed(0)} (${pct.toStringAsFixed(0)}%)',
              style: TextStyle(
                fontSize: 11,
                color: Theme.of(
                  context,
                ).textTheme.bodySmall?.color?.withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
      );
    }

    return ValueListenableBuilder<bool>(
      valueListenable: showAll,
      builder: (context, expanded, _) {
        final visibleData = expanded ? data : data.take(visibleLimit).toList();
        final hiddenCount = data.length - visibleLimit;
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ...visibleData.asMap().entries.map(
              (e) => buildLegendItem(e.key, e.value),
            ),
            if (!expanded && hiddenCount > 0)
              GestureDetector(
                onTap: () => showAll.value = true,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Theme.of(
                        context,
                      ).colorScheme.primary.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.expand_more,
                        size: 16,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Show $hiddenCount more',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  // Responsive chart heights to mirror Svelte's h-64 sm:h-72 lg:h-80
  static double _chartHeight(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    if (width >= 1024) return 320; // lg:h-80
    if (width >= 640) return 288; // sm:h-72
    if (width >= 360) return 240; // slightly shorter on mobile
    return 220; // very small screens
  }
}

// Local hover card wrapper for chart cards
class _HoverCard extends StatefulWidget {
  final Widget Function(bool hovered) builder;
  final Duration duration;
  const _HoverCard({
    required this.builder,
    this.duration = const Duration(milliseconds: 200),
  });

  @override
  State<_HoverCard> createState() => _HoverCardState();
}

class _HoverCardState extends State<_HoverCard> {
  bool _hovered = false;
  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: widget.duration,
        curve: Curves.easeOut,
        child: widget.builder(_hovered),
      ),
    );
  }
}
