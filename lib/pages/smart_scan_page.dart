import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:image/image.dart' as img;

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:google_mlkit_image_labeling/google_mlkit_image_labeling.dart';
import 'package:google_mlkit_object_detection/google_mlkit_object_detection.dart';
import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';

class SmartScanPage extends StatefulWidget {
  const SmartScanPage({super.key});

  @override
  State<SmartScanPage> createState() => _SmartScanPageState();
}

class _SmartScanPageState extends State<SmartScanPage>
    with WidgetsBindingObserver {
  CameraController? _controller;
  List<CameraDescription> _cameras = const [];
  bool _initializing = true;
  bool _capturing = false;
  bool _flashOn = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initCamera();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return;
    }
    if (state == AppLifecycleState.inactive) {
      controller.dispose();
    } else if (state == AppLifecycleState.resumed) {
      _initCamera(selected: controller.description);
    }
  }

  Future<void> _initCamera({CameraDescription? selected}) async {
    try {
      _cameras = await availableCameras();
      final cam = selected ?? (_cameras.isNotEmpty ? _cameras.first : null);
      if (cam == null) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('No camera found')));
        }
        setState(() => _initializing = false);
        return;
      }
      final controller = CameraController(
        cam,
        ResolutionPreset.medium, // Changed from high to medium for stability
        imageFormatGroup: Platform.isAndroid
            ? ImageFormatGroup.jpeg
            : ImageFormatGroup.bgra8888,
        enableAudio: false,
      );
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _controller = controller;
        _initializing = false;
      });
    } catch (e) {
      debugPrint('Camera init error: $e');
      if (mounted) {
        setState(() => _initializing = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Camera error: $e')));
      }
    }
  }

  Future<void> _toggleFlash() async {
    final c = _controller;
    if (c == null) return;
    try {
      _flashOn = !_flashOn;
      await c.setFlashMode(_flashOn ? FlashMode.torch : FlashMode.off);
      setState(() {});
    } catch (_) {}
  }

  Future<void> _switchCamera() async {
    final c = _controller;
    if (c == null || _cameras.isEmpty) return;
    final current = c.description;
    final nextIndex = (_cameras.indexOf(current) + 1) % _cameras.length;
    await _initCamera(selected: _cameras[nextIndex]);
  }

  Future<void> _pickFromGallery() async {
    final x = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (x == null) return;
    await _processAndReturn(x.path);
  }

  Future<void> _capture() async {
    final c = _controller;
    if (c == null || !c.value.isInitialized || _capturing) return;
    try {
      setState(() => _capturing = true);
      final file = await c.takePicture();
      await _processAndReturn(file.path);
    } catch (_) {
    } finally {
      if (mounted) setState(() => _capturing = false);
    }
  }

  Future<void> _processAndReturn(String path) async {
    // Trim small border to avoid device watermarks at edges
    final bytes = await File(path).readAsBytes();
    final original = img.decodeImage(bytes);
    String inputPath = path;
    if (original != null) {
      final bw = (original.width * 0.03).round();
      final bh = (original.height * 0.05).round();
      final w = original.width - 2 * bw;
      final h = original.height - 2 * bh;
      if (w > 32 && h > 32) {
        final trimmed = img.copyCrop(
          original,
          x: bw,
          y: bh,
          width: w,
          height: h,
        );
        final tmp = await getTemporaryDirectory();
        final newPath =
            '${tmp.path}/scan_${DateTime.now().millisecondsSinceEpoch}.jpg';
        await File(newPath).writeAsBytes(img.encodeJpg(trimmed, quality: 92));
        inputPath = newPath;
      }
    }

    final inputImage = InputImage.fromFilePath(inputPath);

    // Run all ML tasks
    final futures = <Future>[];

    final labeler = ImageLabeler(
      options: ImageLabelerOptions(confidenceThreshold: 0.35),
    );
    late final Future<List<ImageLabel>> fLabels = labeler.processImage(
      inputImage,
    );
    futures.add(fLabels);

    final objectDetector = ObjectDetector(
      options: ObjectDetectorOptions(
        mode: DetectionMode.single,
        classifyObjects: true,
        multipleObjects: true,
      ),
    );
    late final Future<List<DetectedObject>> fObjects = objectDetector
        .processImage(inputImage);
    futures.add(fObjects);

    final textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);
    late final Future<RecognizedText> fText = textRecognizer.processImage(
      inputImage,
    );
    futures.add(fText);

    final barcodeScanner = BarcodeScanner();
    late final Future<List<Barcode>> fCodes = barcodeScanner.processImage(
      inputImage,
    );
    futures.add(fCodes);

    await Future.wait(futures);

    final labels = await fLabels;
    final objects = await fObjects;
    final recognized = await fText;
    final codes = await fCodes;
    await labeler.close();
    await objectDetector.close();
    await textRecognizer.close();
    await barcodeScanner.close();

    // Crop up to 3 largest objects and relabel + OCR on crops
    List<ImageLabel> cropLabels = [];
    final List<String> cropOcrWords = [];
    if (objects.isNotEmpty && original != null) {
      // sort objects by area desc
      final objs = [...objects];
      objs.sort(
        (a, b) => (b.boundingBox.width * b.boundingBox.height).compareTo(
          a.boundingBox.width * a.boundingBox.height,
        ),
      );
      final top = objs.take(3);
      for (final best in top) {
        try {
          int x = best.boundingBox.left.round().clamp(0, original.width);
          int y = best.boundingBox.top.round().clamp(0, original.height);
          int w = best.boundingBox.width.round();
          int h = best.boundingBox.height.round();
          if (x + w > original.width) w = original.width - x;
          if (y + h > original.height) h = original.height - y;
          if (w <= 10 || h <= 10) continue;
          final cropped = img.copyCrop(
            original,
            x: x,
            y: y,
            width: w,
            height: h,
          );
          final tmp = await getTemporaryDirectory();
          final cropPath =
              '${tmp.path}/crop_${DateTime.now().millisecondsSinceEpoch}_${x}_$y.jpg';
          await File(
            cropPath,
          ).writeAsBytes(img.encodeJpg(cropped, quality: 92));
          final cropInput = InputImage.fromFilePath(cropPath);

          // labels on crop
          final cropLabeler = ImageLabeler(
            options: ImageLabelerOptions(confidenceThreshold: 0.35),
          );
          final cropLs = await cropLabeler.processImage(cropInput);
          await cropLabeler.close();
          cropLabels.addAll(cropLs);

          // OCR on crop
          final cropText = TextRecognizer(script: TextRecognitionScript.latin);
          final cropRt = await cropText.processImage(cropInput);
          await cropText.close();
          final bufCrop = StringBuffer();
          for (final b in cropRt.blocks) {
            for (final line in b.lines) {
              bufCrop.write('${line.text} ');
            }
          }
          final cropStr = bufCrop.toString().toLowerCase();
          cropOcrWords.addAll(
            cropStr.split(RegExp(r'[^a-z0-9\-]+')).where((w) => w.length >= 3),
          );
        } catch (_) {}
      }
    }

    // Build tokens
    final ordered = <String>[];

    // 1. Barcodes are highest priority
    if (codes.isNotEmpty) {
      ordered.addAll(
        codes
            .map((b) => (b.rawValue ?? '').trim())
            .where((s) => s.isNotEmpty)
            .take(2),
      );
    }

    // 2. Crop OCR Words (Brands/Model numbers)
    ordered.addAll(cropOcrWords);

    // 3. Filtered Labels (Crop)
    // Filter out hallucinations common in basic ML models for electrical items
    final ignoredLabels = {
      'musical instrument',
      'guitar',
      'piano',
      'drum',
      'furniture',
      'clothing',
      'shoe',
      'plant',
      'animal',
      'food',
      'vehicle',
      'art',
      'toy',
      'room',
    };

    // Priority labels: If we find these, boost them to the TOP!
    final priorityLabels = {
      'switch',
      'socket',
      'bulb',
      'screwdriver',
      'plier',
      'screw',
      'plug',
      'pipe',
      'glue',
      'light',
      'tape',
      'wire',
      'cable',
      'fan',
      'motor',
      'board',
      'box',
      'control',
      'power',
      'electric',
      'hardware',
      'tool',
      'cutter',
      'drill',
      'lamp',
      'led',
      'holder',
    };

    // Generic materials to deprioritize (only use if nothing else found)
    final genericLabels = {
      'metal',
      'plastic',
      'wood',
      'glass',
      'rectangle',
      'square',
      'circle',
      'material',
      'pattern',
      'technology',
      'electronic device',
      'gadget',
    };

    bool isRelevantLabel(String label) {
      final l = label.toLowerCase();
      if (ignoredLabels.any((bad) => l.contains(bad))) return false;
      return true;
    }

    bool isPriority(String label) {
      final l = label.toLowerCase();
      return priorityLabels.any((p) => l.contains(p));
    }

    cropLabels.sort((a, b) => b.confidence.compareTo(a.confidence));

    final validCropLabels = cropLabels
        .map((l) => l.label.toLowerCase())
        .where(isRelevantLabel)
        .toList();

    // Insert Priority Labels First
    ordered.addAll(validCropLabels.where((l) => isPriority(l)));
    // Then Specific Non-Priority
    ordered.addAll(
      validCropLabels.where(
        (l) => !isPriority(l) && !genericLabels.contains(l),
      ),
    );
    // Then Generic (Last)
    ordered.addAll(validCropLabels.where((l) => genericLabels.contains(l)));

    // 4. Object Labels (Filtered)
    final objLabels = objects
        .expand((o) => o.labels.map((l) => l.text.toLowerCase()))
        .where(isRelevantLabel)
        .toList();
    ordered.addAll(objLabels.where((l) => isPriority(l)));
    ordered.addAll(
      objLabels.where((l) => !isPriority(l) && !genericLabels.contains(l)),
    );
    ordered.addAll(objLabels.where((l) => genericLabels.contains(l)));

    // 5. Full Image Labels (Filtered, Lower Priority)
    final fullLabels = [...labels]
      ..sort((a, b) => b.confidence.compareTo(a.confidence));

    final validFullLabels = fullLabels
        .map((l) => l.label.toLowerCase())
        .where(isRelevantLabel)
        .take(8)
        .toList();

    ordered.addAll(validFullLabels.where((l) => isPriority(l)));
    ordered.addAll(
      validFullLabels.where(
        (l) => !isPriority(l) && !genericLabels.contains(l),
      ),
    );
    // Don't add generic full-image labels if we have anything else.
    if (ordered.isEmpty) {
      ordered.addAll(validFullLabels.where((l) => genericLabels.contains(l)));
    }

    // 6. Full OCR (Fallback)
    final buf = StringBuffer();
    for (final b in recognized.blocks) {
      for (final line in b.lines) {
        buf.write('${line.text} ');
      }
    }
    final ocr = buf.toString().toLowerCase();
    final ocrWords = ocr
        .split(RegExp(r'[^a-z0-9\-]+'))
        .where((w) => w.length >= 3);
    ordered.addAll(ocrWords);

    // Return compact query
    final tokens = ordered.where((w) => w.isNotEmpty).toSet().toList();
    final query = tokens.take(8).join(' ');
    if (!mounted) return;
    Navigator.of(context).pop(query.isEmpty ? null : query);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            // Camera Preview
            Positioned.fill(
              child: _initializing
                  ? const Center(child: CircularProgressIndicator())
                  : _controller != null && _controller!.value.isInitialized
                  ? CameraPreview(_controller!)
                  : Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.error_outline,
                            color: Colors.white,
                            size: 48,
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'Camera Unavailable',
                            style: TextStyle(color: Colors.white),
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton(
                            onPressed: () {
                              setState(() => _initializing = true);
                              _initCamera();
                            },
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    ),
            ),

            // Top bar
            Positioned(
              top: 8,
              left: 12,
              right: 12,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Lens',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Row(
                    children: [
                      IconButton(
                        icon: Icon(
                          _flashOn ? Icons.flash_on : Icons.flash_off,
                          color: Colors.white,
                        ),
                        onPressed: _toggleFlash,
                      ),
                      IconButton(
                        icon: const Icon(
                          Icons.help_outline,
                          color: Colors.white,
                        ),
                        onPressed: () {
                          showDialog(
                            context: context,
                            builder: (c) => AlertDialog(
                              title: const Text('Smart Scan help'),
                              content: const Text(
                                'Point the camera at a product. After capture, we detect codes, text, and objects to search your catalog.',
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(c),
                                  child: const Text('OK'),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Hint
            Positioned(
              bottom: 140,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'Take a photo to search products',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ),
            ),

            // Bottom controls
            Positioned(
              bottom: 24,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  // Gallery
                  IconButton(
                    iconSize: 28,
                    color: Colors.white,
                    icon: const Icon(Icons.photo_library_outlined),
                    onPressed: _pickFromGallery,
                  ),
                  // Capture
                  GestureDetector(
                    onTap: _capture,
                    child: Container(
                      width: 76,
                      height: 76,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 4),
                      ),
                      alignment: Alignment.center,
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 150),
                        child: _capturing
                            ? const SizedBox(
                                key: ValueKey('prog'),
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(
                                Icons.camera,
                                color: Colors.white,
                                key: ValueKey('icon'),
                              ),
                      ),
                    ),
                  ),
                  // Switch camera
                  IconButton(
                    iconSize: 28,
                    color: Colors.white,
                    icon: const Icon(Icons.cameraswitch),
                    onPressed: _switchCamera,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
