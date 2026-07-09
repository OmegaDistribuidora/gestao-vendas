import 'package:flutter/material.dart';

class CompactMetricTile extends StatelessWidget {
  const CompactMetricTile({
    super.key,
    required this.title,
    required this.value,
    this.subtitle,
    required this.icon,
    required this.accentColor,
    required this.accentBackgroundColor,
  });

  final String title;
  final String value;
  final String? subtitle;
  final IconData icon;
  final Color accentColor;
  final Color accentBackgroundColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFDDE4F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    title,
                    maxLines: 1,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: const Color(0xFF5E6A7C),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: accentBackgroundColor,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: accentColor, size: 18),
              ),
            ],
          ),
          SizedBox(height: subtitle == null ? 8 : 6),
          SizedBox(
            height: subtitle == null ? 28 : 24,
            width: double.infinity,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                maxLines: 1,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: accentColor,
                  fontWeight: FontWeight.w900,
                  height: 1,
                ),
              ),
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(
              subtitle!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: const Color(0xFF64748B),
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
