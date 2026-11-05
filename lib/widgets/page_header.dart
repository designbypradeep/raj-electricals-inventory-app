import 'package:flutter/material.dart';
import 'dart:ui' as ui;
import '../theme/ui_tokens.dart';

class PageHeaderStat {
  final String label;
  final String value;
  final String description;

  PageHeaderStat({
    required this.label,
    required this.value,
    required this.description,
  });
}

class PageHeaderAction {
  final String label;
  final String shortLabel;
  final IconData icon;
  final Color color;
  final Color? foregroundColor;
  final bool pill;
  final VoidCallback? onPressed;

  PageHeaderAction({
    required this.label,
    required this.shortLabel,
    required this.icon,
    required this.color,
    this.foregroundColor,
    this.pill = false,
    this.onPressed,
  });
}

class PageHeaderBreadcrumb {
  final String label;
  final String icon;
  final String? href;
  final bool current;

  PageHeaderBreadcrumb({
    required this.label,
    required this.icon,
    this.href,
    this.current = false,
  });
}

class PageHeader extends StatelessWidget {
  final String title;
  final String description;
  final String icon;
  final bool showBackButton;
  final String? backLabel;
  final VoidCallback? onBackPressed;
  final List<PageHeaderBreadcrumb> breadcrumbs;
  final List<PageHeaderStat> stats;
  final List<PageHeaderAction> actions;
  final bool wrapInSafeArea;

  const PageHeader({
    super.key,
    required this.title,
    required this.description,
    required this.icon,
    this.showBackButton = false,
    this.backLabel,
    this.onBackPressed,
    this.breadcrumbs = const [],
    this.stats = const [],
    this.actions = const [],
    this.wrapInSafeArea = true,
  });

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isMobile = width < 480;
    final pad = EdgeInsets.only(
      top: isMobile ? 12 : 20,
      left: isMobile ? 20 : 24,
      right: isMobile ? 20 : 24,
      bottom: isMobile ? 12 : 20,
    );
    final titleSize = isMobile ? 22.0 : 28.0;
    final descSize = isMobile ? 13.0 : 16.0;
    final gapAfterNav = isMobile ? 8.0 : 16.0;
    final breadcrumbSize = isMobile ? 12.0 : 14.0;
    final headerContent = Padding(
      padding: pad,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Navigation & Breadcrumbs
          Row(
            children: [
              if (showBackButton) ...[
                IconButton(
                  onPressed: onBackPressed ?? () => Navigator.pop(context),
                  icon: Icon(
                    Icons.arrow_back,
                    color: Theme.of(context).colorScheme.onPrimary,
                  ),
                  style: IconButton.styleFrom(
                    backgroundColor: Theme.of(
                      context,
                    ).colorScheme.onPrimary.withValues(alpha: 0.1),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(UITokens.radius),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
              ],

              // Breadcrumbs (now as subtle pill chips for better mobile readability)
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (int i = 0; i < breadcrumbs.length; i++) ...[
                        Container(
                          margin: EdgeInsets.only(
                            right: i < breadcrumbs.length - 1 ? 8 : 0,
                          ),
                          padding: EdgeInsets.symmetric(
                            horizontal: isMobile ? 8 : 12,
                            vertical: isMobile ? 5 : 8,
                          ),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.onPrimary
                                .withValues(
                                  alpha: breadcrumbs[i].current ? 0.18 : 0.12,
                                ),
                            borderRadius: BorderRadius.circular(
                              UITokens.pillRadius,
                            ),
                            border: Border.all(
                              color: Theme.of(context).colorScheme.onPrimary
                                  .withValues(
                                    alpha: breadcrumbs[i].current ? 0.28 : 0.18,
                                  ),
                              width: 1,
                            ),
                          ),
                          child: Text(
                            '${breadcrumbs[i].icon} ${breadcrumbs[i].label}',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.onPrimary,
                              fontSize: breadcrumbSize,
                              fontWeight: breadcrumbs[i].current
                                  ? FontWeight.w600
                                  : FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),

              // Actions (scrollable on phones)
              if (actions.isNotEmpty)
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: actions
                        .map(
                          (action) => Padding(
                            padding: EdgeInsets.only(left: isMobile ? 8 : 12),
                            child: Builder(
                              builder: (context) {
                                final cs = Theme.of(context).colorScheme;
                                // Use tonal container variants on gradient
                                Color bg;
                                Color fg;
                                if (action.color == cs.secondary) {
                                  bg = cs.secondaryContainer;
                                  fg = cs.onSecondaryContainer;
                                } else if (action.color == cs.tertiary) {
                                  bg = cs.tertiaryContainer;
                                  fg = cs.onTertiaryContainer;
                                } else if (action.color == cs.primary) {
                                  bg = cs.primaryContainer;
                                  fg = cs.onPrimaryContainer;
                                } else {
                                  bg = action.color;
                                  fg =
                                      action.foregroundColor ??
                                      (action.color.computeLuminance() > 0.5
                                          ? Colors.black
                                          : Colors.white);
                                }

                                return ElevatedButton.icon(
                                  onPressed: action.onPressed,
                                  icon: Icon(
                                    action.icon,
                                    size: isMobile ? 16 : 18,
                                  ),
                                  label: Text(action.shortLabel),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: bg,
                                    foregroundColor:
                                        action.foregroundColor ?? fg,
                                    padding: EdgeInsets.symmetric(
                                      horizontal: isMobile ? 10 : 12,
                                      vertical: isMobile ? 8 : 10,
                                    ),
                                    textStyle: TextStyle(
                                      fontSize: isMobile ? 12 : 14,
                                      fontWeight: FontWeight.w600,
                                    ),
                                    elevation: isMobile ? 0 : 0.5,
                                    shadowColor: Colors.transparent,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(
                                        (action.pill || isMobile)
                                            ? UITokens.pillRadius
                                            : UITokens.radius,
                                      ),
                                      side: BorderSide(
                                        color: cs.onPrimary.withValues(
                                          alpha: isMobile ? 0.15 : 0.28,
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ),
            ],
          ),
          SizedBox(
            height: gapAfterNav,
          ), // Indent this line to fix minor formatting
          // Title and Description
          Row(
            children: [
              Container(
                padding: EdgeInsets.all(isMobile ? 10 : 12),
                decoration: BoxDecoration(
                  color: Theme.of(
                    context,
                  ).colorScheme.onPrimary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(icon, style: const TextStyle(fontSize: 24)),
              ),
              SizedBox(width: isMobile ? 12 : 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: titleSize,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.onPrimary,
                      ),
                    ),
                    SizedBox(height: isMobile ? 2 : 4),
                    Text(
                      description,
                      style: TextStyle(
                        fontSize: descSize,
                        fontWeight: FontWeight.w500,
                        color: Theme.of(
                          context,
                        ).colorScheme.onPrimary.withValues(alpha: 0.8),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          // Stats (avoid LayoutBuilder in scrollable context)
          if (stats.isNotEmpty) ...[
            SizedBox(height: isMobile ? 10 : 24),
            Builder(
              builder: (context) {
                final w = MediaQuery.of(context).size.width;
                final isDesktop = w > 768;
                if (!isDesktop) {
                  return SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    child: Row(
                      children: stats
                          .map(
                            (s) => Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: _buildCompactStatChip(context, s),
                            ),
                          )
                          .toList(),
                    ),
                  );
                }
                // Desktop: 2 columns using Rows of Expanded cards
                final rows = <Widget>[];
                for (int i = 0; i < stats.length; i += 2) {
                  final left = Expanded(
                    child: _buildStatCard(context, stats[i]),
                  );
                  final right = (i + 1 < stats.length)
                      ? Expanded(child: _buildStatCard(context, stats[i + 1]))
                      : const Expanded(child: SizedBox.shrink());
                  rows.add(
                    Padding(
                      padding: EdgeInsets.only(bottom: isMobile ? 12 : 16),
                      child: Row(
                        children: [left, const SizedBox(width: 16), right],
                      ),
                    ),
                  );
                }
                return Column(children: rows);
              },
            ),
          ],
        ],
      ),
    );

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Theme.of(context).colorScheme.primary,
            Theme.of(context).colorScheme.primary.withValues(alpha: 0.85),
          ],
        ),
      ),
      child: wrapInSafeArea
          ? SafeArea(top: true, bottom: false, child: headerContent)
          : headerContent,
    );
  }

  Widget _buildCompactStatChip(BuildContext context, PageHeaderStat stat) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.onPrimary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: Theme.of(context).colorScheme.onPrimary.withValues(alpha: 0.22),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            stat.value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.onPrimary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            stat.label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w500,
              color: Theme.of(context).colorScheme.onPrimary.withValues(alpha: 0.8),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(BuildContext context, PageHeaderStat stat) {
    final width = MediaQuery.of(context).size.width;
    final isMobile = width < 480;
    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: isMobile ? 380 : double.infinity),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 8, sigmaY: 8),
            child: Container(
              padding: EdgeInsets.all(isMobile ? 14 : 16),
              decoration: BoxDecoration(
                color: Theme.of(
                  context,
                ).colorScheme.onPrimary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: Theme.of(
                    context,
                  ).colorScheme.onPrimary.withValues(alpha: 0.16),
                  width: 1,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    stat.label,
                    style: TextStyle(
                      fontSize: isMobile ? 11 : 12,
                      color: Theme.of(
                        context,
                      ).colorScheme.onPrimary.withValues(alpha: 0.75),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    stat.value,
                    style: TextStyle(
                      fontSize: isMobile ? 16 : 18,
                      color: Theme.of(context).colorScheme.onPrimary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    stat.description,
                    style: TextStyle(
                      fontSize: isMobile ? 10 : 11,
                      color: Theme.of(
                        context,
                      ).colorScheme.onPrimary.withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
