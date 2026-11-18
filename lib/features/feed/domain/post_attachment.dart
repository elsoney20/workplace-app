/// A file attached to a post. Stored in the private `post-media` bucket at
/// `<post_id>/<file>`; shown through short-lived signed links.
class PostAttachment {
  const PostAttachment({
    required this.id,
    required this.storagePath,
    required this.kind,
    required this.sizeBytes,
    this.mimeType,
    this.fileName,
    this.width,
    this.height,
  });

  factory PostAttachment.fromJson(Map<String, dynamic> json) => PostAttachment(
    id: json['id'] as String,
    storagePath: json['storage_path'] as String,
    kind: AttachmentKind.fromName(json['kind'] as String?),
    sizeBytes: (json['size_bytes'] as num?)?.toInt() ?? 0,
    mimeType: json['mime_type'] as String?,
    fileName: json['file_name'] as String?,
    width: (json['width'] as num?)?.toInt(),
    height: (json['height'] as num?)?.toInt(),
  );

  final String id;
  final String storagePath;
  final AttachmentKind kind;
  final int sizeBytes;
  final String? mimeType;
  final String? fileName;
  final int? width;
  final int? height;

  String get displayName => fileName ?? storagePath.split('/').last;
}

enum AttachmentKind {
  image,
  video,
  file;

  static AttachmentKind fromName(String? name) =>
      values.firstWhere((k) => k.name == name, orElse: () => file);
}

/// Human readable size, e.g. "3.4 MB".
String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}
