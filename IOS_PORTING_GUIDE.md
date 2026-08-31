# Future iOS Porting Guide

## Purpose

This project will initially be developed as a native Android application using Kotlin and Jetpack Compose. If an iPhone version is created later, it should remain a simple, offline utility that converts multiple images into one PDF file.

The iOS application should not require a login, account, server, cloud backup, or internet connection.

## Product behavior that must remain consistent

The Android and iOS versions should provide the same core workflow:

1. Select multiple images from the device photo library.
2. Assign a visible number to every selected image based on its selection order.
3. Use image 1 as PDF page 1, image 2 as PDF page 2, and so on.
4. Allow users to drag images into a different order.
5. Renumber all images after reordering or removing one.
6. Allow an image to be rotated or removed before conversion.
7. Let the user choose a PDF filename and image quality.
8. Generate the PDF entirely on the device.
9. Save, preview, open, or share the resulting PDF.

## Expected iOS technology

- Language: Swift
- UI: SwiftUI
- Photo selection: `PhotosPicker` from PhotosUI
- PDF creation: Core Graphics PDF APIs or `UIGraphicsPDFRenderer`
- Image processing: Core Image, Image I/O, and UIKit where necessary
- File saving and sharing: document picker, Files integration, and `UIActivityViewController`
- Concurrency: Swift concurrency with `async`/`await`

An iPhone build and App Store submission will require macOS, Xcode, and an Apple Developer account.

## What can be reused

Kotlin Android source code cannot normally be copied directly into a native Swift application. However, the following project assets and decisions can be reused:

- Product requirements and user flow
- Screen designs, icons, colors, and copy
- Rules for image numbering and ordering
- Page sizes, margins, compression levels, and filename rules
- Test images and expected PDF results
- Memory-management strategy
- Acceptance tests and edge-case definitions

## What must be rebuilt for iOS

- SwiftUI screens and navigation
- Photo-library selection
- Image decoding, rotation, scaling, and compression
- PDF page rendering
- Files integration and the share sheet
- iOS permissions and privacy descriptions
- Platform-specific automated tests

## Android architecture choices that will simplify the port

Keep business rules separate from Android framework code. In particular:

- Represent every selected image with a stable ID, URI, rotation, and order index.
- Keep ordering and renumbering logic in plain Kotlin classes rather than Compose UI code.
- Keep PDF options in a platform-neutral model.
- Isolate gallery access, bitmap decoding, PDF writing, saving, and sharing behind interfaces.
- Document page dimensions and image-fit calculations precisely.
- Avoid embedding Android-specific types in core conversion rules where practical.

A useful conceptual separation is:

```text
UI and navigation
        |
Selection and ordering rules
        |
Image-processing and PDF interfaces
        |
Android-specific implementations
```

The iOS application can reproduce the middle-layer rules in Swift and replace the Android-specific implementations with Apple frameworks.

## Image-order data model

Both applications should follow the same conceptual model:

```text
SelectedImage
- id: stable unique identifier
- source: platform-specific image reference
- position: zero-based internal list position
- displayNumber: position + 1
- rotationDegrees: 0, 90, 180, or 270
```

The ordered list must be the single source of truth. The displayed badge number and PDF page number should always be derived from the image's current list position, not stored independently.

## Memory and performance requirements

Phone photographs may be much larger than a PDF page requires. Both platforms should:

- Avoid decoding every full-resolution image at once.
- Generate the PDF one page at a time.
- Downsample each image to the required output resolution.
- Release temporary image data after its page is written.
- Run conversion away from the main UI thread.
- Report progress and allow failures to be handled without corrupting the output file.

## Porting checklist

When iOS development begins:

1. Confirm the Android product behavior and PDF settings.
2. Capture screenshots and acceptance tests for every screen.
3. Create the SwiftUI project and reproduce the selection/order model.
4. Implement PhotosPicker selection and numbered thumbnails.
5. Add drag-to-reorder, rotation, and removal.
6. Port the page-layout calculations and PDF settings.
7. Implement one-page-at-a-time PDF rendering.
8. Add Files saving, previewing, and sharing.
9. Compare PDFs from Android and iOS using the same test images.
10. Test large images, many-page documents, low storage, cancellation, and permission failures.

## Possible future alternative

If maintaining two native interfaces becomes expensive, Kotlin Multiplatform could later share selected business rules and tests. It should be evaluated only when the iOS work begins; it is not required for the initial Android application and does not eliminate the need for an iOS interface and Apple-specific file and photo integrations.
