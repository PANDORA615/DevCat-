import 'package:flutter/material.dart';

class StudyButton extends StatefulWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final Color? color;
  const StudyButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.color,
  });
  @override
  State<StudyButton> createState() => _StudyButtonState();
}

class _StudyButtonState extends State<StudyButton> {
  bool pressed = false;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final enabled = widget.onPressed != null;
    final color = enabled
        ? widget.color ?? scheme.primary
        : scheme.surfaceContainerHighest;
    final foreground = enabled ? scheme.onPrimary : scheme.onSurfaceVariant;
    final duration = Duration(
      milliseconds: MediaQuery.of(context).disableAnimations ? 0 : 110,
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: AnimatedContainer(
        duration: duration,
        transform: Matrix4.translationValues(0, pressed ? 4 : 0, 0),
        constraints: const BoxConstraints(minHeight: 54),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(17),
          boxShadow: [
            BoxShadow(
              color: Color.lerp(color, Colors.black, .22)!,
              offset: Offset(0, pressed ? 0 : 5),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: widget.onPressed,
            onTapDown: enabled ? (_) => setState(() => pressed = true) : null,
            onTapUp: (_) => setState(() => pressed = false),
            onTapCancel: () => setState(() => pressed = false),
            borderRadius: BorderRadius.circular(17),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (widget.icon != null) ...[
                    Icon(widget.icon, color: foreground, size: 21),
                    const SizedBox(width: 9),
                  ],
                  Flexible(
                    child: Text(
                      widget.label,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 15,
                        letterSpacing: .5,
                        fontWeight: FontWeight.w800,
                        color: foreground,
                      ),
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

class StudyOption extends StatelessWidget {
  final String text;
  final int number;
  final bool selected, enabled;
  final VoidCallback onTap;
  const StudyOption({
    super.key,
    required this.text,
    required this.number,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Semantics(
        button: true,
        selected: selected,
        enabled: enabled,
        child: Material(
          color: selected ? scheme.primaryContainer : scheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: BorderSide(
              color: selected ? scheme.primary : scheme.outlineVariant,
              width: 2,
            ),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: enabled ? onTap : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 17),
              child: Row(
                children: [
                  Container(
                    width: 29,
                    height: 29,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: selected
                            ? scheme.primary
                            : scheme.outlineVariant,
                        width: 2,
                      ),
                    ),
                    child: selected
                        ? Icon(
                            Icons.check_rounded,
                            size: 18,
                            color: scheme.primary,
                          )
                        : Text(
                            '$number',
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                  ),
                  const SizedBox(width: 15),
                  Expanded(
                    child: Text(
                      text,
                      style: TextStyle(
                        fontSize: 17,
                        height: 1.45,
                        fontWeight: selected
                            ? FontWeight.w800
                            : FontWeight.w600,
                      ),
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

class StudyCode extends StatelessWidget {
  final String code;
  const StudyCode(this.code, {super.key});
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    margin: const EdgeInsets.symmetric(vertical: 12),
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
    ),
    child: SelectableText(
      code,
      style: const TextStyle(
        fontFamily: 'JetBrainsMono',
        fontSize: 14,
        height: 1.65,
      ),
    ),
  );
}

class StudyMetric extends StatelessWidget {
  final IconData icon;
  final String value, label;
  final Color? color;
  const StudyMetric(this.icon, this.value, this.label, {super.key, this.color});
  @override
  Widget build(BuildContext context) => Semantics(
    label: '$value $label',
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          color: color ?? Theme.of(context).colorScheme.primary,
          size: 23,
        ),
        const SizedBox(width: 6),
        Text(
          value,
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
        ),
      ],
    ),
  );
}
