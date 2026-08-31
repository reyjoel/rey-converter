import 'dart:io';
import 'dart:async';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:printing/printing.dart';

import 'ordering.dart';
import 'pdf_service.dart';

class ConverterPage extends StatefulWidget {
  const ConverterPage({super.key});

  @override
  State<ConverterPage> createState() => _ConverterPageState();
}

class _ConverterPageState extends State<ConverterPage> {
  final _picker = ImagePicker();
  final _pdfService = PdfService();
  final List<XFile> _images = [];

  PdfImageQuality _quality = PdfImageQuality.balanced;
  Uint8List? _generatedPdf;
  String _pdfName = 'images.pdf';
  bool _isGenerating = false;
  int _completedPages = 0;

  Future<void> _selectImages() async {
    try {
      final picked = await _picker.pickMultiImage();
      if (picked.isEmpty || !mounted) return;
      setState(() {
        _images.addAll(picked);
        _generatedPdf = null;
      });
    } catch (error) {
      _showError('Images could not be opened: $error');
    }
  }

  void _reorder(int oldIndex, int newIndex) {
    setState(() {
      final reordered = moveItem(_images, oldIndex, newIndex);
      _images
        ..clear()
        ..addAll(reordered);
      _generatedPdf = null;
    });
  }

  void _remove(int index) {
    setState(() {
      _images.removeAt(index);
      _generatedPdf = null;
    });
  }

  Future<void> _createPdf() async {
    if (_images.isEmpty || _isGenerating) return;
    final name = await _askForFilename();
    if (name == null || !mounted) return;

    setState(() {
      _isGenerating = true;
      _completedPages = 0;
      _pdfName = name;
    });

    try {
      final bytes = await _pdfService.createPdf(
        images: List<XFile>.of(_images),
        quality: _quality,
        onProgress: (completed, _) {
          if (mounted) setState(() => _completedPages = completed);
        },
      );
      if (!mounted) return;
      setState(() => _generatedPdf = bytes);
      _showStatusPopup('${_images.length}-page PDF is ready.', isError: false);
    } catch (error) {
      _showError('The PDF could not be created: $error');
    } finally {
      if (mounted) setState(() => _isGenerating = false);
    }
  }

  Future<String?> _askForFilename() async {
    final result = await showDialog<String>(
      context: context,
      builder: (_) => _FilenameDialog(
        initialName: _pdfName.replaceFirst(
          RegExp(r'\.pdf$', caseSensitive: false),
          '',
        ),
      ),
    );
    if (result == null) return null;

    final safeName = result
        .trim()
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
        .replaceAll(RegExp(r'\.+$'), '');
    return '${safeName.isEmpty ? 'images' : safeName}.pdf';
  }

  Future<void> _savePdf() async {
    final bytes = _generatedPdf;
    if (bytes == null) return;
    try {
      final uri = await FilePicker.saveFile(
        dialogTitle: 'Save PDF',
        fileName: _pdfName,
        mimeType: 'application/pdf',
        type: FileType.custom,
        allowedExtensions: const ['pdf'],
        bytes: bytes,
      );
      if (uri != null && mounted) {
        _showStatusPopup('PDF saved successfully.', isError: false);
      }
    } catch (error) {
      _showError('The PDF could not be saved: $error');
    }
  }

  Future<void> _sharePdf() async {
    final bytes = _generatedPdf;
    if (bytes == null) return;
    try {
      await Printing.sharePdf(bytes: bytes, filename: _pdfName);
    } catch (error) {
      _showError('The PDF could not be shared: $error');
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    _showStatusPopup(message, isError: true);
  }

  void _showStatusPopup(String message, {required bool isError}) {
    if (!mounted) return;
    showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Close notification',
      barrierColor: Colors.black38,
      transitionDuration: const Duration(milliseconds: 250),
      pageBuilder: (_, _, _) =>
          _StatusPopup(message: message, isError: isError),
      transitionBuilder: (_, animation, _, child) => FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: Curves.easeInOut),
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('REY Converter'),
        actions: [
          if (_images.isNotEmpty)
            IconButton(
              tooltip: 'Clear all',
              onPressed: _isGenerating
                  ? null
                  : () => setState(() {
                      _images.clear();
                      _generatedPdf = null;
                    }),
              icon: const Icon(Icons.delete_sweep_outlined),
            ),
          IconButton(
            tooltip: 'About REY Converter',
            onPressed: _showAbout,
            icon: const Icon(Icons.info_outline),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            _buildIntro(),
            Expanded(
              child: _images.isEmpty ? _buildEmptyState() : _buildImageList(),
            ),
            if (_images.isNotEmpty) _buildBottomPanel(),
          ],
        ),
      ),
    );
  }

  void _showAbout() {
    showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) => Dialog(
        alignment: Alignment.center,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: Image.asset(
                    'assets/branding/rey_pdf_icon.png',
                    width: 80,
                    height: 80,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'REY Converter',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                const Text('Developed by Rey Sagutam'),
                const SizedBox(height: 4),
                const Text('Version 1.0.0'),
                const SizedBox(height: 12),
                const Text(
                  'Convert multiple images into one PDF entirely on your device.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    child: const Text('Close'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildIntro() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: const Text(
        'The displayed number is the PDF page order. Hold and drag a row to rearrange it.',
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.photo_library_outlined,
              size: 72,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 20),
            Text(
              'Select images to begin',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            const Text(
              'Everything stays on your phone. No account or internet connection is needed.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _selectImages,
              icon: const Icon(Icons.add_photo_alternate_outlined),
              label: const Text('Choose images'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImageList() {
    return ReorderableListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 100),
      buildDefaultDragHandles: false,
      itemCount: _images.length,
      onReorderItem: _isGenerating ? (_, _) {} : _reorder,
      proxyDecorator: (child, _, animation) => Material(
        elevation: 6 * animation.value,
        borderRadius: BorderRadius.circular(16),
        child: child,
      ),
      itemBuilder: (context, index) {
        final image = _images[index];
        return Card(
          key: ValueKey(image),
          clipBehavior: Clip.antiAlias,
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 10,
              vertical: 6,
            ),
            leading: Stack(
              clipBehavior: Clip.none,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.file(
                    File(image.path),
                    width: 64,
                    height: 64,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => Container(
                      width: 64,
                      height: 64,
                      color: Theme.of(context)
                          .colorScheme
                          .surfaceContainerHighest,
                      child: const Icon(Icons.image_not_supported_outlined),
                    ),
                  ),
                ),
                Positioned(
                  left: -6,
                  top: -6,
                  child: CircleAvatar(
                    radius: 14,
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Theme.of(context).colorScheme.onPrimary,
                    child: Text(
                      '${index + 1}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            title: Text('Page ${index + 1}'),
            subtitle: const Text('Hold and drag to reorder'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: 'Remove page ${index + 1}',
                  onPressed: _isGenerating ? null : () => _remove(index),
                  icon: const Icon(Icons.close),
                ),
                ReorderableDragStartListener(
                  index: index,
                  enabled: !_isGenerating,
                  child: const Padding(
                    padding: EdgeInsets.all(12),
                    child: Icon(Icons.drag_handle),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildBottomPanel() {
    return Material(
      elevation: 12,
      color: Theme.of(context).colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _isGenerating ? null : _selectImages,
                    icon: const Icon(Icons.add_photo_alternate_outlined),
                    label: const Text('Add images'),
                  ),
                ),
                const SizedBox(width: 12),
                DropdownButton<PdfImageQuality>(
                  value: _quality,
                  onChanged: _isGenerating
                      ? null
                      : (value) {
                          if (value != null) {
                            setState(() {
                              _quality = value;
                              _generatedPdf = null;
                            });
                          }
                        },
                  items: PdfImageQuality.values
                      .map(
                        (value) => DropdownMenuItem(
                          value: value,
                          child: Text(value.label),
                        ),
                      )
                      .toList(),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (_isGenerating) ...[
              LinearProgressIndicator(value: _completedPages / _images.length),
              const SizedBox(height: 8),
              Text('Creating page $_completedPages of ${_images.length}…'),
            ] else if (_generatedPdf == null)
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _createPdf,
                  icon: const Icon(Icons.picture_as_pdf_outlined),
                  label: Text('Create ${_images.length}-page PDF'),
                ),
              )
            else
              Row(
                children: [
                  Expanded(
                    child: FilledButton.tonalIcon(
                      onPressed: _savePdf,
                      icon: const Icon(Icons.download_outlined),
                      label: const Text('Save'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _sharePdf,
                      icon: const Icon(Icons.share_outlined),
                      label: const Text('Share'),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _FilenameDialog extends StatefulWidget {
  const _FilenameDialog({required this.initialName});

  final String initialName;

  @override
  State<_FilenameDialog> createState() => _FilenameDialogState();
}

class _FilenameDialogState extends State<_FilenameDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialName);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() => Navigator.of(context).pop(_controller.text);

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Name your PDF'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLength: 80,
        decoration: const InputDecoration(
          labelText: 'Filename',
          suffixText: '.pdf',
        ),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Create')),
      ],
    );
  }
}

class _StatusPopup extends StatefulWidget {
  const _StatusPopup({required this.message, required this.isError});

  final String message;
  final bool isError;

  @override
  State<_StatusPopup> createState() => _StatusPopupState();
}

class _StatusPopupState extends State<_StatusPopup> {
  Timer? _dismissTimer;

  @override
  void initState() {
    super.initState();
    _dismissTimer = Timer(const Duration(seconds: 3), _close);
  }

  @override
  void dispose() {
    _dismissTimer?.cancel();
    super.dispose();
  }

  void _close() {
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final background = widget.isError
        ? Colors.red.shade700
        : Colors.green.shade700;
    final icon = widget.isError
        ? Icons.error_outline
        : Icons.check_circle_outline;

    return Dialog(
      alignment: Alignment.center,
      backgroundColor: background,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: Colors.white, size: 48),
              const SizedBox(height: 14),
              Text(
                widget.message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: _close,
                  style: TextButton.styleFrom(foregroundColor: Colors.white),
                  child: const Text('Close'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
