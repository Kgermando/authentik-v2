import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../../core/theme.dart';

/// Carte de contenu : fond clair, filet fin, coins arrondis.
class Panel extends StatelessWidget {
  const Panel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.color,
    this.borderColor,
  });

  final Widget child;
  final EdgeInsets padding;
  final Color? color;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? p.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: borderColor ?? p.line),
      ),
      child: child,
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text.toUpperCase(),
              style: TextStyle(
                fontSize: 11.5,
                letterSpacing: 1.3,
                fontWeight: FontWeight.w700,
                color: p.muted,
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

class PageHeader extends StatelessWidget {
  const PageHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontFamilyFallback: kSerif,
                    fontSize: 30,
                    fontWeight: FontWeight.w600,
                    height: 1.1,
                    color: p.ink,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    subtitle!,
                    style: TextStyle(color: p.muted, fontSize: 14, height: 1.4),
                  ),
                ],
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

class StatTile extends StatefulWidget {
  const StatTile({
    super.key,
    required this.label,
    required this.value,
    this.color,
    this.icon,
    this.onTap,
    this.linkLabel,
  });

  final String label;
  final String value;
  final Color? color;
  final IconData? icon;

  /// Lien vers la page concernée (null : tuile non cliquable).
  final VoidCallback? onTap;

  /// Texte du lien, affiché sous la valeur (par exemple « Voir la liste »).
  final String? linkLabel;

  @override
  State<StatTile> createState() => _StatTileState();
}

class _StatTileState extends State<StatTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final StatTile(:label, :value, :icon, :onTap, :linkLabel) = widget;
    final c = widget.color ?? p.ink;
    final content = Panel(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
      color: _hover ? p.accentSoft.withValues(alpha: 0.35) : null,
      borderColor: _hover ? p.accent.withValues(alpha: 0.6) : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: 15, color: p.muted),
                const SizedBox(width: 6),
              ],
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: p.muted, fontSize: 12.5),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontFamilyFallback: kSerif,
              fontSize: 30,
              fontWeight: FontWeight.w600,
              color: c,
              height: 1,
            ),
          ),
          if (onTap != null) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Flexible(
                  child: Text(
                    linkLabel ?? 'Voir',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: p.accent,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Icon(Icons.arrow_forward_rounded, size: 14, color: p.accent),
              ],
            ),
          ],
        ],
      ),
    );
    if (onTap == null) return content;
    return Tooltip(
      message: linkLabel ?? label,
      waitDuration: const Duration(milliseconds: 600),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          onHover: (h) => setState(() => _hover = h),
          borderRadius: BorderRadius.circular(18),
          mouseCursor: SystemMouseCursors.click,
          child: content,
        ),
      ),
    );
  }
}

class VerdictChip extends StatelessWidget {
  const VerdictChip(this.verdict, {super.key, this.big = false});

  final Verdict verdict;
  final bool big;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final c = p.verdictColor(verdict);
    final icon = switch (verdict) {
      Verdict.authentic => Icons.verified_outlined,
      Verdict.review => Icons.visibility_outlined,
      Verdict.suspect => Icons.gpp_maybe_outlined,
      Verdict.inconclusive => Icons.help_outline_rounded,
    };
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: big ? 14 : 10,
        vertical: big ? 8 : 5,
      ),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: big ? 18 : 14, color: c),
          SizedBox(width: big ? 8 : 5),
          Text(
            big ? verdict.label : verdict.short,
            style: TextStyle(
              color: c,
              fontWeight: FontWeight.w700,
              fontSize: big ? 14 : 12,
            ),
          ),
        ],
      ),
    );
  }
}

class Pill extends StatelessWidget {
  const Pill(this.text, {super.key, this.color, this.icon});

  final String text;
  final Color? color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final c = color ?? p.muted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: c),
            const SizedBox(width: 4),
          ],
          Text(
            text,
            style: TextStyle(
              color: c,
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

String formatDate(DateTime d) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(d.day)}/${two(d.month)}/${d.year} ${two(d.hour)}:${two(d.minute)}';
}

String shortHash(String h) =>
    h.length > 14 ? '${h.substring(0, 8)}…${h.substring(h.length - 6)}' : h;
