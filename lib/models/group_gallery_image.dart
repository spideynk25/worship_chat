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

  GroupGalleryImage({
    required this.imageId,
    required this.groupId,
    required this.imageUrl,
    required this.uploadedBy,
    required this.uploadedByName,
    required this.uploadedAt,
    this.caption,
  });

  Map<String, dynamic> toMap() {
    return {
      'imageId': imageId,
      'groupId': groupId,
      'imageUrl': imageUrl,
      'uploadedBy': uploadedBy,
      'uploadedByName': uploadedByName,
      'uploadedAt': uploadedAt.millisecondsSinceEpoch,
      'caption': caption,
    };
  }

  factory GroupGalleryImage.fromMap(Map<String, dynamic> map) {
    return GroupGalleryImage(
      imageId: map['imageId'] ?? '',
      groupId: map['groupId'] ?? '',
      imageUrl: map['imageUrl'] ?? '',
      uploadedBy: map['uploadedBy'] ?? '',
      uploadedByName: map['uploadedByName'] ?? '',
      uploadedAt: map['uploadedAt'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['uploadedAt'])
          : DateTime.now(),
      caption: map['caption'],
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
  }) {
    return GroupGalleryImage(
      imageId: imageId ?? this.imageId,
      groupId: groupId ?? this.groupId,
      imageUrl: imageUrl ?? this.imageUrl,
      uploadedBy: uploadedBy ?? this.uploadedBy,
      uploadedByName: uploadedByName ?? this.uploadedByName,
      uploadedAt: uploadedAt ?? this.uploadedAt,
      caption: caption ?? this.caption,
    );
  }
}