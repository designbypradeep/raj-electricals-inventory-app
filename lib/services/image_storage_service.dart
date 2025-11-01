import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;

class ImageStorageService {
  static const String _imagesFolder = 'product_images';

  /// Get the directory where product images are stored
  static Future<Directory> _getImagesDirectory() async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final imagesDir = Directory(path.join(appDir.path, _imagesFolder));

      if (kDebugMode) {
        print('Attempting to create images directory: ${imagesDir.path}');
      }

      if (!await imagesDir.exists()) {
        await imagesDir.create(recursive: true);
        if (kDebugMode) {
          print('Created images directory: ${imagesDir.path}');
        }
      } else {
        if (kDebugMode) {
          print('Images directory already exists: ${imagesDir.path}');
        }
      }

      return imagesDir;
    } catch (e) {
      if (kDebugMode) {
        print('Error creating images directory: $e');
      }
      // Fallback to app support directory if documents directory fails
      try {
        final appDir = await getApplicationSupportDirectory();
        final imagesDir = Directory(path.join(appDir.path, _imagesFolder));

        if (kDebugMode) {
          print(
            'Fallback: Attempting to create images directory: ${imagesDir.path}',
          );
        }

        if (!await imagesDir.exists()) {
          await imagesDir.create(recursive: true);
          if (kDebugMode) {
            print('Created fallback images directory: ${imagesDir.path}');
          }
        }

        return imagesDir;
      } catch (fallbackError) {
        if (kDebugMode) {
          print('Fallback also failed: $fallbackError');
        }
        rethrow;
      }
    }
  }

  /// Save images for a product and return list of saved file paths or URLs
  static Future<List<String>> saveProductImages(
    List<dynamic> images,
    int productId,
  ) async {
    if (images.isEmpty) return [];

    final imagesDir = await _getImagesDirectory();
    final savedPaths = <String>[];

    for (int i = 0; i < images.length; i++) {
      try {
        final image = images[i];

        if (image is String) {
          // If it's a URL string, store it directly
          savedPaths.add(image);
          if (kDebugMode) {
            print('Stored URL: $image');
          }
        } else if (image is File) {
          // If it's a File, copy it to local storage
          final extension = path.extension(image.path);
          final fileName = 'product_${productId}_image_${i + 1}$extension';
          final targetPath = path.join(imagesDir.path, fileName);

          // Copy the image to the app directory
          await image.copy(targetPath);
          savedPaths.add(targetPath);
          if (kDebugMode) {
            print('Saved local file: $targetPath');
          }
        } else {
          if (kDebugMode) {
            print('Unknown image type: ${image.runtimeType}');
          }
        }
      } catch (e) {
        if (kDebugMode) {
          print('Error saving image ${i + 1}: $e');
        }
        // Continue with other images even if one fails
      }
    }

    return savedPaths;
  }

  /// Convert list of image paths to JSON string for database storage
  static String imagePathsToJson(List<String> paths) {
    return jsonEncode(paths);
  }

  /// Convert JSON string from database to list of image paths
  static List<String> imagePathsFromJson(String? jsonString) {
    if (jsonString == null || jsonString.isEmpty) return [];

    try {
      final List<dynamic> decoded = jsonDecode(jsonString);
      return decoded.cast<String>();
    } catch (e) {
      if (kDebugMode) {
        print('Error parsing image paths JSON: $e');
      }
      return [];
    }
  }

  /// Get mixed File objects and URLs from stored paths (for display)
  static List<dynamic> getImageFiles(String? jsonString) {
    final paths = imagePathsFromJson(jsonString);
    return paths
        .map((path) {
          if (path.startsWith('http')) {
            // Return URL string for network images
            return path;
          } else {
            // Return File object for local images, but only if it exists
            final file = File(path);
            return file.existsSync() ? file : null;
          }
        })
        .where((item) => item != null)
        .toList();
  }

  /// Delete all images for a product
  static Future<void> deleteProductImages(String? jsonString) async {
    final paths = imagePathsFromJson(jsonString);

    for (final path in paths) {
      try {
        final file = File(path);
        if (await file.exists()) {
          await file.delete();
        }
      } catch (e) {
        if (kDebugMode) {
          print('Error deleting image $path: $e');
        }
      }
    }
  }

  /// Get all image paths for a specific product
  static Future<List<String>> getProductImages(int productId) async {
    try {
      final imagesDir = await _getImagesDirectory();
      final allFiles = await imagesDir.list().toList();
      final productImages = <String>[];

      for (final entity in allFiles) {
        if (entity is File) {
          final fileName = path.basename(entity.path);
          if (fileName.startsWith('product_${productId}_image_')) {
            productImages.add(entity.path);
          }
        }
      }

      // Sort by image number for consistent ordering
      productImages.sort((a, b) {
        final aNum = _extractImageNumber(a);
        final bNum = _extractImageNumber(b);
        return aNum.compareTo(bNum);
      });

      return productImages;
    } catch (e) {
      if (kDebugMode) {
        print('Error getting product images: $e');
      }
      return [];
    }
  }

  /// Extract image number from filename for sorting
  static int _extractImageNumber(String filePath) {
    try {
      final fileName = path.basename(filePath);
      final regex = RegExp(r'product_\d+_image_(\d+)');
      final match = regex.firstMatch(fileName);
      if (match != null) {
        return int.parse(match.group(1)!);
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error extracting image number: $e');
      }
    }
    return 0;
  }

  /// Clean up orphaned images (images not referenced by any product)
  static Future<void> cleanupOrphanedImages(
    List<String> allProductImagePaths,
  ) async {
    try {
      final imagesDir = await _getImagesDirectory();
      final allFiles = await imagesDir.list().toList();

      for (final entity in allFiles) {
        if (entity is File) {
          final isReferenced = allProductImagePaths.contains(entity.path);
          if (!isReferenced) {
            await entity.delete();
            if (kDebugMode) {
              print('Deleted orphaned image: ${entity.path}');
            }
          }
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error during cleanup: $e');
      }
    }
  }
}
