import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

enum AlertType {
  error,
  warning,
  info,
  success,
}

class AlertBanner extends StatefulWidget {
  final String message;
  final AlertType type;
  final VoidCallback? onDismiss;
  final Duration dismissDuration;
  final bool dismissible;

  const AlertBanner({
    super.key,
    required this.message,
    this.type = AlertType.warning,
    this.onDismiss,
    this.dismissDuration = const Duration(seconds: 5),
    this.dismissible = false,
  });

  @override
  State<AlertBanner> createState() => _AlertBannerState();
}

class _AlertBannerState extends State<AlertBanner>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _slideAnimation;
  bool _isVisible = true;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );
    _slideAnimation = Tween<double>(begin: -1, end: 0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOutCubic),
    );
    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  void _dismiss() {
    _animationController.reverse().then((_) {
      if (mounted) {
        setState(() => _isVisible = false);
        widget.onDismiss?.call();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_isVisible) return const SizedBox.shrink();

    Color backgroundColor;
    Color borderColor;
    Color textColor;
    Color iconColor;
    IconData icon;

    switch (widget.type) {
      case AlertType.error:
        backgroundColor = const Color.fromARGB(12, 231, 76, 60);
        borderColor = AppTheme.errorRed.withValues(alpha: 0.3);
        textColor = AppTheme.errorRed;
        iconColor = AppTheme.errorRed;
        icon = Icons.error_outline;
        break;
      case AlertType.warning:
        backgroundColor = const Color.fromARGB(12, 243, 156, 18);
        borderColor = AppTheme.warningYellow.withValues(alpha: 0.3);
        textColor = AppTheme.warningYellow;
        iconColor = AppTheme.warningYellow;
        icon = Icons.warning_amber;
        break;
      case AlertType.info:
        backgroundColor = const Color.fromARGB(12, 52, 152, 219);
        borderColor = AppTheme.infoBlue.withValues(alpha: 0.3);
        textColor = AppTheme.infoBlue;
        iconColor = AppTheme.infoBlue;
        icon = Icons.info_outline;
        break;
      case AlertType.success:
        backgroundColor = const Color.fromARGB(12, 39, 174, 96);
        borderColor = AppTheme.successGreen.withValues(alpha: 0.3);
        textColor = AppTheme.successGreen;
        iconColor = AppTheme.successGreen;
        icon = Icons.check_circle_outline;
        break;
    }

    return SlideTransition(
      position: _slideAnimation.drive(
        Tween<Offset>(begin: const Offset(0, -1), end: Offset.zero),
      ),
      child: Container(
        margin: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: borderColor, width: 1.5),
          boxShadow: [
            BoxShadow(
              color: textColor.withValues(alpha: 0.1),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: iconColor.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  padding: const EdgeInsets.all(8),
                  child: Icon(
                    icon,
                    color: iconColor,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _getAlertTitle(),
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: textColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        widget.message,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: textColor.withValues(alpha: 0.9),
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                if (widget.dismissible) ...[
                  const SizedBox(width: 12),
                  IconButton(
                    onPressed: _dismiss,
                    icon: Icon(Icons.close, color: textColor, size: 20),
                    splashRadius: 20,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 32,
                      minHeight: 32,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _getAlertTitle() {
    switch (widget.type) {
      case AlertType.error:
        return 'Erreur';
      case AlertType.warning:
        return 'Avertissement';
      case AlertType.info:
        return 'Information';
      case AlertType.success:
        return 'Succès';
    }
  }
}