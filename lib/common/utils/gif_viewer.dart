// import 'dart:io';
// import 'dart:typed_data';
// import 'package:flutter/material.dart';
// import 'package:flutter/services.dart';
// import 'dart:developer';

// class GifViewer extends StatefulWidget {
//   final String uri;

//   const GifViewer({Key? key, required this.uri}) : super(key: key);

//   @override
//   State<GifViewer> createState() => _GifViewerState();
// }

// class _GifViewerState extends State<GifViewer> {
//   Uint8List? _gifData;
//   String? _filePath;
//   bool _isLoading = true;
//   String? _error;

//   @override
//   void initState() {
//     super.initState();
//     _loadGif();
//   }

//   Future<void> _loadGif() async {
//     log('🎬 Loading GIF from: ${widget.uri}');

//     try {
//       // Check if it's a content URI
//       if (widget.uri.startsWith('content://')) {
//         await _loadFromContentUri();
//       }
//       // Check if it's a file path
//       else if (widget.uri.startsWith('file://') ||
//           (!widget.uri.startsWith('http://') &&
//               !widget.uri.startsWith('https://'))) {
//         await _loadFromFile();
//       }
//       // Otherwise it's a network URL
//       else {
//         setState(() {
//           _isLoading = false;
//         });
//       }
//     } catch (e) {
//       log('❌ Error loading GIF: $e');
//       setState(() {
//         _error = e.toString();
//         _isLoading = false;
//       });
//     }
//   }

//   Future<void> _loadFromContentUri() async {
//     try {
//       const platform = MethodChannel('my.app/accounts');

//       // Try to read the content URI
//       final result = await platform.invokeMethod('readContentUri', {
//         'uri': widget.uri,
//       });

//       if (result != null) {
//         final bytes = Uint8List.fromList(List<int>.from(result));
//         setState(() {
//           _gifData = bytes;
//           _isLoading = false;
//         });
//         log('✅ GIF loaded from content URI (${bytes.length} bytes)');
//       } else {
//         throw Exception('No data returned from content URI');
//       }
//     } catch (e) {
//       log('❌ Failed to load from content URI: $e');

//       // Fallback: Try to get file path from content URI
//       try {
//         const platform = MethodChannel('my.app/accounts');
//         final path = await platform.invokeMethod('getFilePath', {
//           'uri': widget.uri,
//         });

//         if (path != null && path is String) {
//           setState(() {
//             _filePath = path;
//             _isLoading = false;
//           });
//           log('✅ Got file path from content URI: $path');
//         } else {
//           throw Exception('Could not get file path');
//         }
//       } catch (fallbackError) {
//         throw Exception('Failed to load GIF: $fallbackError');
//       }
//     }
//   }

//   Future<void> _loadFromFile() async {
//     String filePath = widget.uri;
//     if (filePath.startsWith('file://')) {
//       filePath = filePath.replaceFirst('file://', '');
//     }

//     final file = File(filePath);
//     if (await file.exists()) {
//       setState(() {
//         _filePath = filePath;
//         _isLoading = false;
//       });
//       log('✅ GIF loaded from file: $filePath');
//     } else {
//       throw Exception('File does not exist: $filePath');
//     }
//   }

//   @override
//   Widget build(BuildContext context) {
//     if (_isLoading) {
//       return Container(
//         color: Colors.grey[300],
//         child: const Center(child: CircularProgressIndicator()),
//       );
//     }

//     if (_error != null) {
//       return Container(
//         color: Colors.grey[300],
//         padding: const EdgeInsets.all(8),
//         child: Column(
//           mainAxisAlignment: MainAxisAlignment.center,
//           children: [
//             const Icon(Icons.error, color: Colors.red, size: 32),
//             const SizedBox(height: 8),
//             Text(
//               'Failed to load GIF',
//               style: const TextStyle(fontSize: 12, color: Colors.red),
//               textAlign: TextAlign.center,
//             ),
//           ],
//         ),
//       );
//     }

//     // Display from bytes
//     if (_gifData != null) {
//       return Image.memory(
//         _gifData!,
//         fit: BoxFit.contain,
//         errorBuilder: (context, error, stackTrace) {
//           return Container(
//             color: Colors.grey[300],
//             child: const Icon(Icons.error, color: Colors.red),
//           );
//         },
//       );
//     }

//     // Display from file path
//     if (_filePath != null) {
//       return Image.file(
//         File(_filePath!),
//         fit: BoxFit.contain,
//         errorBuilder: (context, error, stackTrace) {
//           return Container(
//             color: Colors.grey[300],
//             child: const Icon(Icons.error, color: Colors.red),
//           );
//         },
//       );
//     }

//     // Display from network URL
//     if (widget.uri.startsWith('http://') || widget.uri.startsWith('https://')) {
//       return Image.network(
//         widget.uri,
//         fit: BoxFit.contain,
//         loadingBuilder: (context, child, loadingProgress) {
//           if (loadingProgress == null) return child;
//           return Center(
//             child: CircularProgressIndicator(
//               value: loadingProgress.expectedTotalBytes != null
//                   ? loadingProgress.cumulativeBytesLoaded /
//                         loadingProgress.expectedTotalBytes!
//                   : null,
//             ),
//           );
//         },
//         errorBuilder: (context, error, stackTrace) {
//           return Container(
//             color: Colors.grey[300],
//             child: const Icon(Icons.error, color: Colors.red),
//           );
//         },
//       );
//     }

//     // Fallback
//     return Container(
//       color: Colors.grey[300],
//       child: const Center(child: Text('Unsupported GIF format')),
//     );
//   }
// }
