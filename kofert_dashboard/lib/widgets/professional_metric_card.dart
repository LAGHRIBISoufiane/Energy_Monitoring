import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class ProfessionalMetricCard extends StatefulWidget {
  final String title;
  final String value;
  final String unit;
  final IconData icon;
  final Color color;
  final String? subtitle;
  final String? status;
  final Color? statusColor;
  final double? minValue;
  final double? maxValue;
  final double? currentValue;
  final Function()? onTap;

  const ProfessionalMetricCard({
    super.key,
    required this.title,
    required this.value,
    required this.unit,
    required this.icon,
    required this.color,
    this.subtitle,
    this.status,
    this.statusColor,
    this.minValue,
    this.maxValue,
    this.currentValue,
    this.onTap,
  });

  @override
  State<ProfessionalMetricCard> createState() => _ProfessionalMetricCardState();
}

class _ProfessionalMetricCardState extends State<ProfessionalMetricCard> with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.02).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  void _onHover(bool isHovering) {
    if (isHovering) {
      _animationController.forward();
    } else {
      _animationController.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scaleAnimation,
      child: MouseRegion(
        onEnter: (_) => _onHover(true),
        onExit: (_) => _onHover(false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: Card(
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Colors.white,
                    Colors.grey[50]!,
                  ],
                ),
                border: Border.all(color: Colors.grey[200]!, width: 1),
              ),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Top section: Icon and Title
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.title,
                                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                  color: AppTheme.darkGray,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              if (widget.subtitle != null) ...[
                                const SizedBox(height: 4),
                                Text(
                                  widget.subtitle!,
                                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                    color: AppTheme.darkGray.withValues(alpha: 0.7),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        Container(
                          decoration: BoxDecoration(
                            color: widget.color.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          padding: const EdgeInsets.all(12),
                          child: Icon(
                            widget.icon,
                            size: 24,
                            color: widget.color,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    // Middle section: Value and Unit
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(
                          widget.value,
                          style: Theme.of(context).textTheme.displaySmall?.copyWith(
                            color: widget.color,
                            fontWeight: FontWeight.w700,
                            fontSize: 28,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          widget.unit,
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: widget.color.withValues(alpha: 0.7),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    // Bottom section: Progress bar and Status
                    if (widget.minValue != null && widget.maxValue != null && widget.currentValue != null) ...[
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: LinearProgressIndicator(
                          minHeight: 6,
                          value: widget.currentValue == 0 
                            ? 0 
                            : (widget.currentValue! - widget.minValue!) / 
                              (widget.maxValue! - widget.minValue!),
                          backgroundColor: Colors.grey[300],
                          valueColor: AlwaysStoppedAnimation<Color>(widget.color),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    if (widget.status != null)
                      Container(
                        decoration: BoxDecoration(
                          color: (widget.statusColor ?? widget.color).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        child: Text(
                          widget.status!,
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: widget.statusColor ?? widget.color,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// Legacy MetricCard for backward compatibility
class MetricCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;
  final String? subtitle;

  const MetricCard({
    super.key,
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return ProfessionalMetricCard(
      title: title,
      value: value.replaceAll(RegExp(r'\s.*'), ''),
      unit: value.contains(' ') ? value.substring(value.lastIndexOf(' ') + 1) : '',
      icon: icon,
      color: color,
      subtitle: subtitle,
    );
  }
}
