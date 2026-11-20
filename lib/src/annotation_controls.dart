import 'package:flutter/material.dart';

/// Shared opaque RGB colors for text, ink, and printed-text covers.
class AnnotationColorControl extends StatelessWidget {
  const AnnotationColorControl({
    super.key,
    required this.label,
    required this.color,
    required this.onChanged,
  });

  final String label;
  final int color;
  final ValueChanged<int> onChanged;

  static const _presets = <(String, int)>[
    ('Black', 0x000000),
    ('White', 0xffffff),
    ('Red', 0xd32f2f),
    ('Blue', 0x1565c0),
    ('Green', 0x2e7d32),
    ('Yellow', 0xfbc02d),
    ('Purple', 0x7b1fa2),
    ('Gray', 0x757575),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: Text(label)),
            Text('#${_hex(color)}', style: const TextStyle(fontSize: 12)),
          ],
        ),
        const SizedBox(height: 4),
        Wrap(
          spacing: 4,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (final (name, rgb) in _presets)
              Semantics(
                label: '$label: $name',
                button: true,
                selected: rgb == color,
                child: Tooltip(
                  message: name,
                  child: InkWell(
                    key: ValueKey('$label-color-${name.toLowerCase()}'),
                    onTap: () => onChanged(rgb),
                    borderRadius: BorderRadius.circular(24),
                    child: SizedBox(
                      width: 40,
                      height: 40,
                      child: Center(
                        child: Container(
                          width: 30,
                          height: 30,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Color(0xff000000 | rgb),
                            border: Border.all(
                              width: color == rgb ? 3 : 1,
                              color: color == rgb
                                  ? Theme.of(context).colorScheme.primary
                                  : Theme.of(context).colorScheme.outline,
                            ),
                          ),
                          child: rgb == color
                              ? Icon(Icons.check, size: 17, color: _inkOn(rgb))
                              : null,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            OutlinedButton.icon(
              key: ValueKey('$label-custom-color'),
              onPressed: () async {
                final result = await showDialog<int>(
                  context: context,
                  builder: (_) => _HexColorDialog(initialColor: color),
                );
                if (result != null && context.mounted) onChanged(result);
              },
              icon: const Icon(Icons.palette_outlined, size: 18),
              label: const Text('Custom'),
            ),
          ],
        ),
      ],
    );
  }
}

String _hex(int color) =>
    (color & 0xffffff).toRadixString(16).padLeft(6, '0').toUpperCase();

Color _inkOn(int color) => Color(0xff000000 | color).computeLuminance() > .45
    ? Colors.black
    : Colors.white;

class _HexColorDialog extends StatefulWidget {
  const _HexColorDialog({required this.initialColor});

  final int initialColor;

  @override
  State<_HexColorDialog> createState() => _HexColorDialogState();
}

class _HexColorDialogState extends State<_HexColorDialog> {
  late final _controller = TextEditingController(
    text: '#${_hex(widget.initialColor)}',
  );

  int? get _value {
    final text = _controller.text.trim();
    if (!RegExp(r'^#?[0-9a-fA-F]{6}$').hasMatch(text)) return null;
    return int.tryParse(text.replaceFirst('#', ''), radix: 16);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final value = _value;
    return AlertDialog(
      title: const Text('Custom color'),
      content: SizedBox(
        width: 280,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                key: const ValueKey('custom-color-hex'),
                controller: _controller,
                autofocus: true,
                textCapitalization: TextCapitalization.characters,
                maxLength: 7,
                decoration: InputDecoration(
                  labelText: 'Hex color',
                  hintText: '#RRGGBB',
                  errorText: value == null
                      ? 'Enter six hexadecimal digits.'
                      : null,
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                color: Color(0xff000000 | (value ?? widget.initialColor)),
                child: Text(
                  'Preview',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: _inkOn(value ?? widget.initialColor)),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: value == null
              ? null
              : () => Navigator.of(context).pop(value),
          child: const Text('Save'),
        ),
      ],
    );
  }
}

/// Point sizes use the PDF's actual point units, independent of screen density.
class PointSizeControl extends StatefulWidget {
  const PointSizeControl({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final double value;
  final ValueChanged<double> onChanged;

  static const minimum = 4.0;
  static const maximum = 144.0;

  @override
  State<PointSizeControl> createState() => _PointSizeControlState();
}

class _PointSizeControlState extends State<PointSizeControl> {
  late double _current = _safeValue(widget.value);
  late final _controller = TextEditingController(text: _format(_current));
  late final _focus = FocusNode()..addListener(_focusChanged);
  String? _error;

  static double _safeValue(double value) => value.isFinite
      ? value.clamp(PointSizeControl.minimum, PointSizeControl.maximum)
      : 12;

  static String _format(double value) {
    return value == value.roundToDouble()
        ? value.toInt().toString()
        : value.toString();
  }

  double? _parse(String input) {
    final text = input.trim();
    if (!RegExp(r'^(?:\d+(?:\.\d*)?|\.\d+)$').hasMatch(text)) return null;
    final value = double.tryParse(text);
    if (value == null ||
        !value.isFinite ||
        value < PointSizeControl.minimum ||
        value > PointSizeControl.maximum) {
      return null;
    }
    return value;
  }

  @override
  void didUpdateWidget(covariant PointSizeControl oldWidget) {
    super.didUpdateWidget(oldWidget);
    final incoming = _safeValue(widget.value);
    if ((incoming - _current).abs() > .00001) {
      _current = incoming;
      _controller.text = _format(incoming);
      _error = null;
    }
  }

  void _focusChanged() {
    if (!_focus.hasFocus) {
      setState(() {
        _controller.text = _format(_current);
        _error = null;
      });
    }
  }

  void _typeSize(String text) {
    final value = _parse(text);
    setState(() {
      _error = value == null && text.isNotEmpty
          ? 'Enter a size from 4 to 144 pt.'
          : null;
      if (value != null) _current = value;
    });
    if (value != null) widget.onChanged(value);
  }

  void _slideSize(double value) {
    final rounded = (value * 10).round() / 10;
    setState(() {
      _current = rounded;
      _controller.text = _format(rounded);
      _error = null;
    });
    widget.onChanged(rounded);
  }

  @override
  void dispose() {
    _focus.removeListener(_focusChanged);
    _focus.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Text size'),
        Row(
          children: [
            Expanded(
              child: Slider(
                key: const ValueKey('annotation-Text size'),
                value: _current,
                min: PointSizeControl.minimum,
                max: PointSizeControl.maximum,
                label: '${_format(_current)} pt',
                semanticFormatterCallback: (value) =>
                    '${_format(value)} points',
                onChanged: _slideSize,
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 96,
              child: TextField(
                key: const ValueKey('text-size-pt'),
                controller: _controller,
                focusNode: _focus,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                textInputAction: TextInputAction.done,
                decoration: const InputDecoration(
                  labelText: 'Size',
                  suffixText: 'pt',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                onChanged: _typeSize,
                onSubmitted: (_) => _focus.unfocus(),
              ),
            ),
          ],
        ),
        if (_error != null)
          Text(
            _error!,
            style: TextStyle(
              color: Theme.of(context).colorScheme.error,
              fontSize: 12,
            ),
          ),
      ],
    );
  }
}
