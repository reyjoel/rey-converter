import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'document_page.dart';
import 'document_preview.dart';
import 'annotation_controls.dart';
import 'page_annotation.dart';
import 'page_geometry.dart';
import 'signature_dialog.dart';

class PageEditor extends StatefulWidget {
  const PageEditor({super.key, required this.page});

  final DocumentPage page;

  @override
  State<PageEditor> createState() => _PageEditorState();
}

class _PageEditorState extends State<PageEditor> {
  late DocumentPage _edited = widget.page;
  String? _selectedId;
  double _aspectRatio = 1;
  bool _imageReady = false;
  String? _samplingAnnotationId;

  PageAnnotation? get _selected {
    for (final item in _edited.annotations) {
      if (item.id == _selectedId) return item;
    }
    return null;
  }

  void _update(PageAnnotation annotation) {
    setState(() {
      _edited = _edited.copyWith(
        annotations: [
          for (final item in _edited.annotations)
            if (item.id == annotation.id) annotation else item,
        ],
      );
    });
  }

  void _add(PageAnnotation annotation) {
    setState(() {
      _edited = _edited.copyWith(
        annotations: [..._edited.annotations, annotation],
      );
      _selectedId = annotation.id;
    });
  }

  Future<void> _addText() async {
    final cover = _selected;
    final text = await showDialog<String>(
      context: context,
      builder: (_) => const _TextDialog(),
    );
    if (text == null || !mounted) return;
    _add(
      TextAnnotation(
        text: text,
        fontSizePt: 16,
        x: cover is CoverAnnotation ? cover.x : .1,
        y: cover is CoverAnnotation ? cover.y : .1,
        width: cover is CoverAnnotation ? cover.width : .6,
        height: cover is CoverAnnotation ? cover.height : .12,
      ),
    );
  }

  Future<void> _editSelected() async {
    final selected = _selected;
    if (selected is TextAnnotation) {
      final text = await showDialog<String>(
        context: context,
        builder: (_) => _TextDialog(initialText: selected.text),
      );
      if (text != null && mounted) _update(selected.copyWith(text: text));
    } else if (selected is SignatureAnnotation) {
      final strokes = await showSignatureDialog(context);
      if (strokes != null && mounted) {
        _update(selected.copyWith(strokes: strokes));
      }
    }
  }

  Future<void> _addSignature() async {
    final strokes = await showSignatureDialog(context);
    if (strokes == null || !mounted) return;
    final height = (.5 * _aspectRatio / 3).clamp(.02, .8);
    _add(
      SignatureAnnotation(
        strokes: strokes,
        height: height,
        y: math.min(.65, 1 - height),
      ),
    );
  }

  void _coverText() {
    _add(CoverAnnotation());
  }

  void _changeColor(PageAnnotation item, int color) {
    _update(switch (item) {
      TextAnnotation() => item.copyWith(color: color),
      SignatureAnnotation() => item.copyWith(color: color),
      CoverAnnotation() => item.copyWith(color: color),
    });
  }

  void _sampledColor(int color) {
    final id = _samplingAnnotationId;
    if (id == null) return;
    for (final item in _edited.annotations) {
      if (item.id == id) {
        _changeColor(item, color);
        break;
      }
    }
    setState(() => _samplingAnnotationId = null);
  }

  void _samplingFailed() {
    setState(() => _samplingAnnotationId = null);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'This photo could not be sampled. Choose a color instead.',
        ),
      ),
    );
  }

  void _deleteSelected() {
    setState(() {
      _edited = _edited.copyWith(
        annotations: [
          for (final item in _edited.annotations)
            if (item.id != _selectedId) item,
        ],
      );
      _selectedId = null;
    });
  }

  void _rotate(int amount) {
    if (_edited.annotations.isNotEmpty) return;
    setState(() {
      _edited = _edited.copyWith(
        quarterTurns: (_edited.quarterTurns + amount + 4) % 4,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit page'),
        actions: [
          if (_samplingAnnotationId != null)
            TextButton(
              onPressed: () => setState(() => _samplingAnnotationId = null),
              child: const Text('Cancel picker'),
            ),
          TextButton(
            onPressed: _samplingAnnotationId == null
                ? () => Navigator.of(context).pop(_edited)
                : null,
            child: const Text('Apply'),
          ),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => Column(
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: ColoredBox(
                    color: Theme.of(context)
                        .colorScheme
                        .surfaceContainerHighest,
                    child: DocumentPreview(
                      page: _edited,
                      selectedAnnotationId: _selectedId,
                      onSelectionChanged: (id) =>
                          setState(() => _selectedId = id),
                      onAnnotationChanged: _update,
                      onAspectRatioChanged: (ratio) => setState(() {
                        _aspectRatio = ratio;
                        _imageReady = true;
                      }),
                      onColorSampled: _samplingAnnotationId == null
                          ? null
                          : (color) => _sampledColor(color),
                      onColorSamplingFailed: _samplingFailed,
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
                child: Text(
                  _samplingAnnotationId == null
                      ? 'Tap an item to select it. Drag it to move it.'
                      : 'Tap a color in the photo. For a cover, pick the nearby background.',
                ),
              ),
              Material(
                elevation: 8,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: constraints.maxHeight * .46,
                  ),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                    child: IgnorePointer(
                      ignoring: _samplingAnnotationId != null,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Wrap(
                            spacing: 8,
                            runSpacing: 4,
                            children: [
                              FilledButton.tonalIcon(
                                onPressed: _addText,
                                icon: const Icon(Icons.text_fields),
                                label: const Text('Add text'),
                              ),
                              FilledButton.tonalIcon(
                                onPressed: _addSignature,
                                icon: const Icon(Icons.draw_outlined),
                                label: const Text('Signature'),
                              ),
                              OutlinedButton.icon(
                                onPressed: _coverText,
                                icon: const Icon(
                                  Icons.format_color_fill_outlined,
                                ),
                                label: const Text('Cover printed text'),
                              ),
                            ],
                          ),
                          if (_selected case final selected?) ...[
                            const Divider(),
                            _selectionControls(selected),
                          ],
                          const Divider(),
                          Row(
                            children: [
                              IconButton(
                                tooltip: 'Rotate left',
                                onPressed: _edited.annotations.isEmpty
                                    ? () => _rotate(-1)
                                    : null,
                                icon: const Icon(Icons.rotate_left),
                              ),
                              IconButton(
                                tooltip: 'Rotate right',
                                onPressed: _edited.annotations.isEmpty
                                    ? () => _rotate(1)
                                    : null,
                                icon: const Icon(Icons.rotate_right),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: DropdownButton<ScanFilter>(
                                  isExpanded: true,
                                  value: _edited.filter,
                                  onChanged: (value) {
                                    if (value != null) {
                                      setState(
                                        () => _edited = _edited.copyWith(
                                          filter: value,
                                        ),
                                      );
                                    }
                                  },
                                  items: [
                                    for (final filter in ScanFilter.values)
                                      DropdownMenuItem(
                                        value: filter,
                                        child: Text(filter.label),
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          if (_edited.annotations.isNotEmpty)
                            const Text(
                              'Rotate the page before adding text, covers, or signatures.',
                              style: TextStyle(fontSize: 12),
                            ),
                          if (_edited.annotations.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Wrap(
                              spacing: 6,
                              children: [
                                for (
                                  var index = 0;
                                  index < _edited.annotations.length;
                                  index++
                                )
                                  ChoiceChip(
                                    label: Text(
                                      '${_label(_edited.annotations[index])} ${index + 1}',
                                    ),
                                    selected:
                                        _edited.annotations[index].id ==
                                        _selectedId,
                                    onSelected: (_) => setState(() {
                                      _selectedId =
                                          _edited.annotations[index].id;
                                    }),
                                  ),
                              ],
                            ),
                          ],
                        ],
                      ),
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

  String _label(PageAnnotation annotation) => switch (annotation) {
    TextAnnotation() => 'Text',
    SignatureAnnotation() => 'Signature',
    CoverAnnotation() => 'Cover',
  };

  Widget _selectionControls(PageAnnotation selected) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(child: Text('${_label(selected)} selected')),
            if (selected is! CoverAnnotation)
              TextButton.icon(
                onPressed: _editSelected,
                icon: const Icon(Icons.edit_outlined),
                label: const Text('Edit'),
              ),
            IconButton(
              tooltip: 'Delete selected item',
              onPressed: _deleteSelected,
              icon: const Icon(Icons.delete_outline),
            ),
          ],
        ),
        if (selected is CoverAnnotation)
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text(
              'Move the cover over printed text. Match its color to the background, then add replacement text if needed.',
            ),
          ),
        if (selected is TextAnnotation) ...[
          Wrap(
            spacing: 6,
            children: [
              FilterChip(
                label: const Text(
                  'Bold',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                selected: selected.bold,
                onSelected: (value) => _update(selected.copyWith(bold: value)),
              ),
              FilterChip(
                label: const Text(
                  'Italic',
                  style: TextStyle(fontStyle: FontStyle.italic),
                ),
                selected: selected.italic,
                onSelected: (value) =>
                    _update(selected.copyWith(italic: value)),
              ),
              FilterChip(
                label: const Text(
                  'Underline',
                  style: TextStyle(decoration: TextDecoration.underline),
                ),
                selected: selected.underline,
                onSelected: (value) =>
                    _update(selected.copyWith(underline: value)),
              ),
              FilterChip(
                label: const Text(
                  'Strikethrough',
                  style: TextStyle(decoration: TextDecoration.lineThrough),
                ),
                selected: selected.strikethrough,
                onSelected: (value) =>
                    _update(selected.copyWith(strikethrough: value)),
              ),
            ],
          ),
          PointSizeControl(
            key: ValueKey('text-size-${selected.id}'),
            value: selected
                .fontSizeForImageWidth(
                  imageWidthPointsForAspectRatio(_aspectRatio),
                )
                .clamp(4, 144),
            onChanged: (points) =>
                _update(selected.copyWith(fontSizePt: points)),
          ),
        ],
        const SizedBox(height: 8),
        AnnotationColorControl(
          label: '${_label(selected)} color',
          color: switch (selected) {
            TextAnnotation() => selected.color,
            SignatureAnnotation() => selected.color,
            CoverAnnotation() => selected.color,
          },
          onChanged: (color) => _changeColor(selected, color),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            key: const ValueKey('pick-color-from-photo'),
            onPressed: _imageReady
                ? () {
                    FocusScope.of(context).unfocus();
                    setState(() => _samplingAnnotationId = selected.id);
                  }
                : null,
            icon: const Icon(Icons.colorize_outlined),
            label: const Text('Pick from photo'),
          ),
        ),
        if (selected is SignatureAnnotation)
          _slider(
            'Size',
            selected.width,
            .08,
            math.min(1, selected.width / selected.height),
            (value) {
              final height = value * selected.height / selected.width;
              _update(
                selected.copyWith(
                  width: value,
                  height: height,
                  x: math.min(selected.x, 1 - value),
                  y: math.min(selected.y, 1 - height),
                ),
              );
            },
          )
        else ...[
          _slider('Width', selected.width, .05, 1, (value) {
            _update(
              selected.copyWith(
                width: value,
                x: math.min(selected.x, 1 - value),
              ),
            );
          }),
          _slider('Height', selected.height, .02, 1, (value) {
            _update(
              selected.copyWith(
                height: value,
                y: math.min(selected.y, 1 - value),
              ),
            );
          }),
        ],
      ],
    );
  }

  Widget _slider(
    String label,
    double value,
    double min,
    double max,
    ValueChanged<double> onChanged,
  ) {
    return Row(
      children: [
        SizedBox(width: 72, child: Text(label)),
        Expanded(
          child: Slider(
            key: ValueKey('annotation-$label'),
            label: '${(value * 100).round()}%',
            value: value.clamp(min, max),
            min: min,
            max: max,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}

class _TextDialog extends StatefulWidget {
  const _TextDialog({this.initialText = ''});

  final String initialText;

  @override
  State<_TextDialog> createState() => _TextDialogState();
}

class _TextDialogState extends State<_TextDialog> {
  late final _controller = TextEditingController(text: widget.initialText);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.initialText.isEmpty ? 'Add text' : 'Edit text'),
      content: SizedBox(
        width: 360,
        child: TextField(
          key: const ValueKey('page-text-input'),
          controller: _controller,
          autofocus: true,
          minLines: 2,
          maxLines: 5,
          maxLength: 500,
          decoration: const InputDecoration(labelText: 'Text'),
          onChanged: (_) => setState(() {}),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _controller.text.trim().isEmpty
              ? null
              : () => Navigator.of(context).pop(_controller.text.trim()),
          child: const Text('Done'),
        ),
      ],
    );
  }
}
