import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:path/path.dart' as p;

enum AttachmentType {
  image,
  file,
}

class ChatAttachment {
  final String id;
  final String name;
  final AttachmentType type;
  final int size;
  final String? path;
  final Uint8List? bytes;
  final String? mimeType;
  final String? textContent;

  const ChatAttachment({
    required this.id,
    required this.name,
    required this.type,
    required this.size,
    this.path,
    this.bytes,
    this.mimeType,
    this.textContent,
  });

  bool get isImage => type == AttachmentType.image;

  String get formattedSize {
    if (size <= 0) return '';
    if (size < 1024) return '$size B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)} KB';
    return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  /// Base64 data URL for multimodal LLM vision ingestion
  String? get dataUrl {
    if (bytes == null || bytes!.isEmpty) return null;
    final mime = mimeType ?? _guessMimeType(name);
    final b64 = base64Encode(bytes!);
    return 'data:$mime;base64,$b64';
  }

  static String _guessMimeType(String filename) {
    final ext = p.extension(filename).toLowerCase();
    switch (ext) {
      case '.png':
        return 'image/png';
      case '.webp':
        return 'image/webp';
      case '.gif':
        return 'image/gif';
      case '.bmp':
        return 'image/bmp';
      case '.jpg':
      case '.jpeg':
      default:
        return 'image/jpeg';
    }
  }

  /// Create image attachment from in-memory bytes (e.g. clipboard screenshot)
  static ChatAttachment fromImageBytes(Uint8List bytes, {String? customName}) {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final name = customName ?? 'screenshot_$timestamp.png';
    return ChatAttachment(
      id: 'att_$timestamp',
      name: name,
      type: AttachmentType.image,
      size: bytes.length,
      bytes: bytes,
      mimeType: _guessMimeType(name),
    );
  }

  /// Create image attachment from a file (e.g. camera photo or gallery pick)
  static Future<ChatAttachment> fromFile(File file, {bool isImageOverride = false}) async {
    final ext = p.extension(file.path).toLowerCase();
    final isImg = isImageOverride || const ['.png', '.jpg', '.jpeg', '.webp', '.gif', '.bmp'].contains(ext);
    final size = await file.length();
    final bytes = await file.readAsBytes();
    final filename = p.basename(file.path);

    String? textContent;
    if (!isImg) {
      // If it's a code / text file under 500KB, read utf-8 content to inject to prompt
      const textExtensions = [
        '.txt', '.md', '.py', '.dart', '.js', '.ts', '.jsx', '.tsx',
        '.json', '.yaml', '.yml', '.xml', '.html', '.css', '.sh',
        '.bash', '.c', '.cpp', '.h', '.hpp', '.rs', '.go', '.java',
        '.kt', '.swift', '.sql', '.log', '.env', '.conf', '.ini'
      ];
      if (textExtensions.contains(ext) && size <= 500 * 1024) {
        try {
          final raw = await file.readAsString();
          textContent = raw.length > 25000 ? '${raw.substring(0, 25000)}\n...[文件过长已节略]...' : raw;
        } catch (_) {}
      }
    }

    return ChatAttachment(
      id: 'att_${DateTime.now().millisecondsSinceEpoch}_${filename.hashCode}',
      name: filename,
      type: isImg ? AttachmentType.image : AttachmentType.file,
      size: size,
      path: file.path,
      bytes: bytes,
      mimeType: isImg ? _guessMimeType(filename) : 'application/octet-stream',
      textContent: textContent,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'type': type == AttachmentType.image ? 'image' : 'file',
      'size': size,
      'path': path,
      'mime_type': mimeType,
      'text_content': textContent,
    };
  }

  factory ChatAttachment.fromJson(Map<String, dynamic> json) {
    return ChatAttachment(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? 'attachment',
      type: json['type'] == 'image' ? AttachmentType.image : AttachmentType.file,
      size: json['size'] is int ? json['size'] as int : 0,
      path: json['path']?.toString(),
      mimeType: json['mime_type']?.toString(),
      textContent: json['text_content']?.toString(),
    );
  }
}
