# REY Converter

An offline Flutter application that converts multiple images into one PDF.

## Current features

- Select multiple images from the phone gallery.
- Scan one or more paper pages with the phone camera.
- Show a numbered badge reflecting each image's PDF page number.
- Hold and drag images to rearrange the PDF page order.
- Remove images with automatic renumbering.
- Rotate individual pages and apply original, grayscale, or high-contrast document filters.
- Add, edit, move, resize, or delete text boxes on a page.
- Choose text colors, bold, italic, underline, and strikethrough styles.
- Set exact text sizes from 4 to 144 pt by slider or numeric entry.
- Cover printed text in a photo with a colored box, then add replacement text.
- Draw signatures with undo/clear, and move, resize, replace, or delete them.
- Change signature colors, and pick text, signature, or cover colors from the photo.
- Choose compact, balanced, or high image quality.
- Generate an A4 PDF entirely on the device.
- Save the PDF locally or share it through the system share sheet.

No login, cloud storage, server, or internet connection is required for conversion.

Developed by Rey Sagutam. Version 1.2.0.

Tap a page's edit button to add text, cover printed text, or draw a signature.
Select an item on the preview (or its chip) to move it, adjust its size, edit it,
or delete it. Apply keeps your edits; Back discards the current editing session.
The preview and PDF use the same image-relative positions. Printed text is
changed manually with a colored cover and replacement text; this is not OCR.
Rotate the image before adding items; rotation is disabled while a page has
text, covers, or signatures so printed-text covers cannot move off their text.
Covered pixels are replaced in the exported image rather than hidden behind a
removable PDF rectangle. Original photos are kept unchanged.

Select added text to change its color or toggle bold, italic, underline, and
strikethrough. The Text size slider and pt field set the actual exported PDF
point size; decimal values are accepted. Select a signature to recolor its ink.
For a cover, choose a preset/custom hex color or tap Pick from photo, then tap
nearby background in the image. The picker temporarily hides added items so
you can sample the photo underneath. Tap Cancel picker to keep the old color.
Each cover uses one solid color; textured or shaded backgrounds can still show
the covered area's outline.

Image previews use bounded decode sizes to keep large camera photos from
exhausting memory. PDF processing runs in a background isolate, and Android
recovers pending gallery/camera selections after an activity restart.

## Run

```sh
flutter pub get
flutter run
```

Run `flutter doctor -v` first and resolve the Android license warning if present.
