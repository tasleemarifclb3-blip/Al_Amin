import 'package:flutter/material.dart';
import '../domain/format.dart';

import 'brand.dart';

class AppPageHeader extends StatelessWidget {

  final String title;

  final String? subtitle;

  final IconData? icon;

  final Widget? trailing;

  /// Slim one-row header (logo left, title right) that leaves more room for content.
  final bool compact;


  const AppPageHeader({

    super.key,

    required this.title,

    this.subtitle,

    this.icon,

    this.trailing,
    this.compact = false,

  });

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF2E806F), Color(0xFF4A9A88)],
          ),
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: kBrandGreen.withValues(alpha: .18),
              blurRadius: 12,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            const Positioned.fill(child: CustomPaint(painter: _IslamicHeaderPatternPainter())),
            Row(
              children: [
                BrandLogo(size: 38),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800),
                      ),
                      if (subtitle != null)
                        Text(
                          subtitle!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: Colors.white.withValues(alpha: .82), fontSize: 10.5),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF2E806F),
            Color(0xFF4A9A88),
          ],
        ),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: kBrandGreen.withValues(alpha: .18),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          const Positioned.fill(child: CustomPaint(painter: _IslamicHeaderPatternPainter())),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
          BrandLogo(size: 50),
          const SizedBox(height: 7),
          Text(
            title,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 3),
            Text(
              subtitle!,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white.withValues(alpha: .82),
                fontSize: 11.5,
              ),
            ),
          ],
          if (icon != null || trailing != null) ...[
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (icon != null)
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: .14),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(icon, color: Colors.white, size: 21),
                  ),
                if (icon != null && trailing != null)
                  const SizedBox(width: 8),
                if (trailing != null) trailing!,
              ],
            ),
          ],
            ],
          ),
        ],
      ),
    );
  }
}

class _IslamicHeaderPatternPainter extends CustomPainter {
  const _IslamicHeaderPatternPainter();
  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()..color = Colors.white.withValues(alpha: .12)..style = PaintingStyle.stroke..strokeWidth = 1;
    const step = 30.0;
    for (double y = -step; y < size.height + step; y += step) {
      for (double x = -step; x < size.width + step; x += step) {
        final path = Path()
          ..moveTo(x, y - step / 2)
          ..lineTo(x + step / 2, y)
          ..lineTo(x, y + step / 2)
          ..lineTo(x - step / 2, y)
          ..close();
        canvas.drawPath(path, line);
        canvas.drawCircle(Offset(x, y), 3.5, line);
      }
    }
  }
  @override
  bool shouldRepaint(covariant _IslamicHeaderPatternPainter oldDelegate) => false;
}

class AppSectionHeader extends StatelessWidget {

  final String title;

  final String? subtitle;

  /// Tighter spacing for dense screens.
  final bool dense;

  const AppSectionHeader({super.key, required this.title, this.subtitle, this.dense = false});

  @override

  Widget build(BuildContext context) {

    return Padding(

      padding: EdgeInsets.only(bottom: dense ? 6 : 10, top: dense ? 0 : 4),

      child: Row(

        crossAxisAlignment: CrossAxisAlignment.end,

        children: [

          Expanded(

            child: Column(

              crossAxisAlignment: CrossAxisAlignment.start,

              children: [

                Text(

                  title,

                  style: const TextStyle(

                    color: kBrandGreen,

                    fontSize: 18,

                    fontWeight: FontWeight.w800,

                  ),

                ),

                if (subtitle != null) ...[

                  const SizedBox(height: 2),

                  Text(subtitle!, style: const TextStyle(color: Colors.black54, fontSize: 12)),

                ],

              ],

            ),

          ),

          Container(width: 42, height: 3, decoration: BoxDecoration(color: kBrandGold, borderRadius: BorderRadius.circular(3))),

        ],

      ),

    );

  }

}

class AppActionCard extends StatelessWidget {

  final String title;

  final String? subtitle;

  final IconData icon;

  final VoidCallback onTap;

  final bool destructive;

  const AppActionCard({

    super.key,

    required this.title,

    required this.icon,

    required this.onTap,

    this.subtitle,

    this.destructive = false,

  });

  @override
  Widget build(BuildContext context) {
    final accent = destructive ? const Color(0xFFB23A3A) : kBrandGreen;
    final accentSoft = destructive
        ? const Color(0x10B23A3A)
        : const Color(0x101F7A68);

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white,
                Color(0xFFF0F4F2),
              ],
            ),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: accent.withValues(alpha: .18)),
            boxShadow: [
              BoxShadow(
                color: accent.withValues(alpha: .10),
                blurRadius: 0,
                offset: const Offset(0, 4),
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: .08),
                blurRadius: 14,
                offset: const Offset(0, 7),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      accentSoft,
                      accent.withValues(alpha: .16),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: accent.withValues(alpha: .10)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.white.withValues(alpha: .95),
                      blurRadius: 2,
                      offset: const Offset(-1, -1),
                    ),
                  ],
                ),
                child: Icon(icon, color: accent, size: 20),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: accent,
                        fontWeight: FontWeight.w800,
                        fontSize: 14.5,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.black54,
                          fontSize: 11.5,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.chevron_right_rounded, color: Colors.black38),
            ],
          ),
        ),
      ),
    );
  }
}

class AppBalanceCard extends StatelessWidget {

  final String title;
  final double amount;
  final VoidCallback? onTap;
  final bool prominent;
  final String tapHint;
  final bool showIcon;

  const AppBalanceCard({
    super.key,
    required this.title,
    required this.amount,
    this.onTap,
    this.prominent = false,
    this.tapHint = 'View ledger',
    this.showIcon = true,
  });

  @override
  Widget build(BuildContext context) {
    final amountStyle = TextStyle(
      color: kBrandGreen,
      fontSize: prominent ? 20 : 17,
      fontWeight: FontWeight.w800,
    );

    final amountRow = Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Flexible(
          child: Text(
            '₹${amount.asAmount}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: amountStyle,
          ),
        ),
        if (onTap != null) ...[
          const SizedBox(width: 4),
          const Icon(Icons.chevron_right_rounded, color: Colors.black38, size: 20),
        ],
      ],
    );

    final content = Container(
      padding: EdgeInsets.symmetric(
        horizontal: prominent ? 16 : 12,
        vertical: prominent ? 15 : 12,
      ),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .96),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: kBrandGreen.withValues(alpha: .12)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .045),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: showIcon
          ? Row(
              children: [
                Container(
                  width: prominent ? 46 : 38,
                  height: prominent ? 46 : 38,
                  decoration: BoxDecoration(
                    color: kBrandGreen.withValues(alpha: .09),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.account_balance_wallet_outlined,
                    color: kBrandGreen,
                    size: prominent ? 24 : 20,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: prominent ? 15 : 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 3),
                      amountRow,
                      if (onTap != null)
                        Text(
                          tapHint,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.black45, fontSize: 10),
                        ),
                    ],
                  ),
                ),
              ],
            )
          : Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: prominent ? 15 : 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                amountRow,
                if (onTap != null) ...[
                  const SizedBox(height: 1),
                  Text(
                    tapHint,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.black45, fontSize: 10),
                  ),
                ],
              ],
            ),
    );

    return onTap == null
        ? content
        : InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(18),
            child: content,
          );
  }
}

class AppFormSection extends StatelessWidget {

  final String title;

  final IconData icon;

  final Widget child;

  const AppFormSection({super.key, required this.title, required this.icon, required this.child});

  @override

  Widget build(BuildContext context) {

    return Container(

      margin: const EdgeInsets.only(bottom: 10),

      padding: const EdgeInsets.fromLTRB(12, 11, 12, 12),

      decoration: BoxDecoration(

        color: Colors.white.withValues(alpha: .92),

        borderRadius: BorderRadius.circular(20),

        border: Border.all(color: Colors.black.withValues(alpha: .06)),

      ),

      child: Column(

        crossAxisAlignment: CrossAxisAlignment.stretch,

        children: [

          Row(

            children: [

              Container(width: 30, height: 30, decoration: BoxDecoration(color: kBrandGreen.withValues(alpha: .10), borderRadius: BorderRadius.circular(9)), child: Icon(icon, color: kBrandGreen, size: 17)),

              const SizedBox(width: 8),

              Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: kBrandGreen)),

            ],

          ),

          const SizedBox(height: 9),

          child,

        ],

      ),

    );

  }

}



class AppDesktopShell extends StatelessWidget {

  final String selected;

  final Widget child;

  final VoidCallback? onDashboard;

  final VoidCallback? onReceive;

  final VoidCallback? onIssueQarza;

  final VoidCallback? onReports;

  final VoidCallback? onSettings;

  const AppDesktopShell({

    super.key,

    required this.selected,

    required this.child,

    this.onDashboard,

    this.onReceive,

    this.onIssueQarza,

    this.onReports,

    this.onSettings,

  });

  @override

  Widget build(BuildContext context) {

    return LayoutBuilder(

      builder: (context, constraints) {

        final wide = constraints.maxWidth >= 900;

        if (!wide) return child;

        return Row(

          crossAxisAlignment: CrossAxisAlignment.stretch,

          children: [

            AppDesktopSidebar(

              selected: selected,

              onDashboard: onDashboard,

              onReceive: onReceive,

              onIssueQarza: onIssueQarza,

              onReports: onReports,

              onSettings: onSettings,

            ),

            Expanded(child: child),

          ],

        );

      },

    );

  }

}

class AppCompactField extends StatelessWidget {

  final String label;

  final Widget child;

  final Color fillColor;

  final double minHeight;

  const AppCompactField({

    super.key,

    required this.label,

    required this.child,

    this.fillColor = const Color(0xFFF3F7F5),

    this.minHeight = 48,

  });

  @override

  Widget build(BuildContext context) {

    return Container(

      constraints: BoxConstraints(minHeight: minHeight),

      decoration: BoxDecoration(

        color: fillColor,

        borderRadius: BorderRadius.circular(10),

        border: Border.all(color: const Color(0xFF8B9994).withValues(alpha: .45)),

      ),

      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),

      child: child,

    );

  }

}

/// Compact desktop navigation panel used by form pages.
/// It intentionally stays narrow so the form remains the primary focus.
class AppDesktopSidebar extends StatelessWidget {

  final String selected;

  final VoidCallback? onDashboard;

  final VoidCallback? onReceive;

  final VoidCallback? onIssueQarza;

  final VoidCallback? onReports;

  final VoidCallback? onSettings;

  const AppDesktopSidebar({

    super.key,

    required this.selected,

    this.onDashboard,

    this.onReceive,

    this.onIssueQarza,

    this.onReports,

    this.onSettings,

  });

  @override

  Widget build(BuildContext context) {

    return Container(

      width: 78,

      margin: const EdgeInsets.fromLTRB(8, 8, 8, 8),

      decoration: BoxDecoration(

        color: const Color(0xFFF2F7F5),

        borderRadius: BorderRadius.circular(18),

        border: Border.all(color: kBrandGreen.withValues(alpha: .08)),

        boxShadow: [

          BoxShadow(

            color: Colors.black.withValues(alpha: .045),

            blurRadius: 12,

            offset: const Offset(2, 4),

          ),

        ],

      ),

      child: Column(

        children: [

          const SizedBox(height: 12),

          _item(context, 'Dashboard', Icons.home_outlined, onDashboard),

          _item(context, 'Receive\nPayment', Icons.account_balance_wallet_outlined, onReceive),

          _item(context, 'Issue Qarza', Icons.handshake_outlined, onIssueQarza),

          _item(context, 'Reports', Icons.bar_chart_outlined, onReports),

          const Spacer(),

          _item(context, 'Settings', Icons.settings_outlined, onSettings),

          const SizedBox(height: 12),

        ],

      ),

    );

  }

  Widget _item(BuildContext context, String label, IconData icon, VoidCallback? onTap) {

    final active = selected == label;

    return Padding(

      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),

      child: Material(

        color: active ? kBrandGreen.withValues(alpha: .12) : Colors.transparent,

        borderRadius: BorderRadius.circular(12),

        child: InkWell(

          onTap: onTap,

          borderRadius: BorderRadius.circular(12),

          child: SizedBox(

            height: 68,

            child: Column(

              mainAxisAlignment: MainAxisAlignment.center,

              children: [

                Container(

                  width: 34,

                  height: 34,

                  decoration: BoxDecoration(

                    color: active ? kBrandGreen : Colors.transparent,

                    borderRadius: BorderRadius.circular(10),

                  ),

                  child: Icon(

                    icon,

                    size: 19,

                    color: active ? Colors.white : kBrandGreen,

                  ),

                ),

                const SizedBox(height: 4),

                Text(

                  label,

                  textAlign: TextAlign.center,

                  maxLines: 2,

                  overflow: TextOverflow.ellipsis,

                  style: TextStyle(

                    fontSize: 9.5,

                    height: 1.05,

                    fontWeight: active ? FontWeight.w700 : FontWeight.w500,

                    color: active ? kBrandGreen : Colors.black54,

                  ),

                ),

              ],

            ),

          ),

        ),

      ),

    );

  }

}

/// Compact 3D-style action button used on the home screen.
class Action3DButton extends StatefulWidget {
  final String title;
  final IconData icon;
  final VoidCallback onTap;
  final bool destructive;
  final Color? accentColor;

  const Action3DButton({
    super.key,
    required this.title,
    required this.icon,
    required this.onTap,
    this.destructive = false,
    this.accentColor,
  });

  @override
  State<Action3DButton> createState() => _Action3DButtonState();
}

class _Action3DButtonState extends State<Action3DButton> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed != value) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final accent = widget.accentColor ?? (widget.destructive ? const Color(0xFFB23A3A) : kBrandGreen);
    final edge = Color.lerp(accent, Colors.black, .25)!;
    final lift = _pressed ? 1.0 : 4.0;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _setPressed(true),
      onTapUp: (_) => _setPressed(false),
      onTapCancel: () => _setPressed(false),
      onTap: widget.onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 70),
        transform: Matrix4.translationValues(0, 4 - lift, 0),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.white,
              Color.lerp(Colors.white, accent, .10)!,
            ],
          ),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: accent.withValues(alpha: .28)),
          boxShadow: [
            // Solid lower edge gives the raised, 3D look.
            BoxShadow(color: edge.withValues(alpha: .55), offset: Offset(0, lift)),
            BoxShadow(
              color: Colors.black.withValues(alpha: .14),
              blurRadius: 8,
              offset: Offset(0, lift + 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color.lerp(accent, Colors.white, .30)!,
                    accent,
                  ],
                ),
                borderRadius: BorderRadius.circular(9),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: .22),
                    blurRadius: 2,
                    offset: const Offset(0, 1.5),
                  ),
                ],
              ),
              child: Icon(widget.icon, color: Colors.white, size: 17),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                widget.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: accent,
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                  height: 1.15,
                ),
              ),
            ),
            Icon(Icons.chevron_right_rounded,
                color: accent.withValues(alpha: .55), size: 18),
          ],
        ),
      ),
    );
  }
}

/// Soft green background with a faint eight-pointed-star lattice.
class IslamicBackground extends StatelessWidget {
  final Widget child;
  const IslamicBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFF6F9F6), Color(0xFFE6EFE9)],
        ),
      ),
      child: Stack(
        children: [
          const Positioned.fill(
            child: RepaintBoundary(
              child: CustomPaint(painter: _IslamicLatticePainter()),
            ),
          ),
          Positioned.fill(child: child),
        ],
      ),
    );
  }
}

class _IslamicLatticePainter extends CustomPainter {
  const _IslamicLatticePainter();

  @override
  void paint(Canvas canvas, Size size) {
    const tile = 72.0;
    final star = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1
      ..color = kBrandGreen.withValues(alpha: .10);
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = .9
      ..color = kBrandGreen.withValues(alpha: .06);
    final gold = Paint()
      ..style = PaintingStyle.fill
      ..color = const Color(0xFFC9A24A).withValues(alpha: .16);

    const a = tile * .26;
    final r = a * 1.41421356;
    final square = Path()
      ..moveTo(-a, -a)
      ..lineTo(a, -a)
      ..lineTo(a, a)
      ..lineTo(-a, a)
      ..close();
    final diamond = Path()
      ..moveTo(0, -r)
      ..lineTo(r, 0)
      ..lineTo(0, r)
      ..lineTo(-r, 0)
      ..close();

    for (var y = 0.0; y < size.height + tile; y += tile) {
      for (var x = 0.0; x < size.width + tile; x += tile) {
        canvas.save();
        canvas.translate(x + tile / 2, y + tile / 2);
        canvas.drawPath(square, star);
        canvas.drawPath(diamond, star);
        canvas.drawCircle(Offset.zero, r * 1.18, ring);
        canvas.restore();
        // Small gold diamond where four stars meet.
        canvas.save();
        canvas.translate(x + tile, y + tile);
        canvas.drawPath(
          Path()
            ..moveTo(0, -3.2)
            ..lineTo(3.2, 0)
            ..lineTo(0, 3.2)
            ..lineTo(-3.2, 0)
            ..close(),
          gold,
        );
        canvas.restore();
      }
    }
  }

  @override
  bool shouldRepaint(covariant _IslamicLatticePainter oldDelegate) => false;
}
