import 'package:hive/hive.dart';

part 'group_gallery_image.g.dart';

@HiveType(typeId: 10)
class GroupGalleryImage extends HiveObject {
  @HiveField(0)
  final String imageId;

  @HiveField(1)
  final String groupId;

  @HiveField(2)
  final String imageUrl;

  @HiveField(3)
  final String uploadedBy;       // uid
  
  @HiveField(4)
  final String uploadedByName;

  @HiveField(5)
  final DateTime uploadedAt;

  @HiveField(6)
  final String? caption;

  @HiveField(7)
  final String mediaType; // 'image' or 'video'

  GroupGalleryImage({
    required this.imageId,
    required this.groupId,
    required this.imageUrl,
    required this.uploadedBy,
    required this.uploadedByName,
    required this.uploadedAt,
    this.caption,
    this.mediaType = 'image',
  });

  bool get isVideo =>
      mediaType == 'video' ||
      imageUrl.contains('/video/upload') ||
      imageUrl.toLowerCase().endsWith('.mp4') ||
      imageUrl.toLowerCase().endsWith('.mov') ||
      imageUrl.toLowerCase().endsWith('.webm') ||
      imageUrl.toLowerCase().endsWith('.m4v') ||
      imageUrl.toLowerCase().endsWith('.avi') ||
      imageUrl.toLowerCase().endsWith('.mkv');

  bool get isImage => !isVideo;

  Map<String, dynamic> toMap() {
    return {
      'imageId': imageId,
      'groupId': groupId,
      'imageUrl': imageUrl,
      'uploadedBy': uploadedBy,
      'uploadedByName': uploadedByName,
      'uploadedAt': uploadedAt.millisecondsSinceEpoch,
      'caption': caption,
      'mediaType': mediaType,
    };
  }

  factory GroupGalleryImage.fromMap(Map<String, dynamic> map) {
    final url = map['imageUrl'] as String? ?? '';
    final detectedIsVideo = url.contains('/video/upload') ||
        url.toLowerCase().endsWith('.mp4') ||
        url.toLowerCase().endsWith('.mov') ||
        url.toLowerCase().endsWith('.webm') ||
        url.toLowerCase().endsWith('.m4v');

    return GroupGalleryImage(
      imageId: map['imageId'] ?? '',
      groupId: map['groupId'] ?? '',
      imageUrl: url,
      uploadedBy: map['uploadedBy'] ?? '',
      uploadedByName: map['uploadedByName'] ?? '',
      uploadedAt: map['uploadedAt'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['uploadedAt'])
          : DateTime.now(),
      caption: map['caption'],
      mediaType: map['mediaType'] ?? (detectedIsVideo ? 'video' : 'image'),
    );
  }

  GroupGalleryImage copyWith({
    String? imageId,
    String? groupId,
    String? imageUrl,
    String? uploadedBy,
    String? uploadedByName,
    DateTime? uploadedAt,
    String? caption,
    String? mediaType,
  }) {
    return GroupGalleryImage(
      imageId: imageId ?? this.imageId,
      groupId: groupId ?? this.groupId,
      imageUrl: imageUrl ?? this.imageUrl,
      uploadedBy: uploadedBy ?? this.uploadedBy,
      uploadedByName: uploadedByName ?? this.uploadedByName,
      uploadedAt: uploadedAt ?? this.uploadedAt,
      caption: caption ?? this.caption,
      mediaType: mediaType ?? this.mediaType,
    );
  }
}