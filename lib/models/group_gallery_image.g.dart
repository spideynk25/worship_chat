// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'group_gallery_image.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class GroupGalleryImageAdapter extends TypeAdapter<GroupGalleryImage> {
  @override
  final int typeId = 10;

  @override
  GroupGalleryImage read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return GroupGalleryImage(
      imageId: fields[0] as String,
      groupId: fields[1] as String,
      imageUrl: fields[2] as String,
      uploadedBy: fields[3] as String,
      uploadedByName: fields[4] as String,
      uploadedAt: fields[5] as DateTime,
      caption: fields[6] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, GroupGalleryImage obj) {
    writer
      ..writeByte(7)
      ..writeByte(0)
      ..write(obj.imageId)
      ..writeByte(1)
      ..write(obj.groupId)
      ..writeByte(2)
      ..write(obj.imageUrl)
      ..writeByte(3)
      ..write(obj.uploadedBy)
      ..writeByte(4)
      ..write(obj.uploadedByName)
      ..writeByte(5)
      ..write(obj.uploadedAt)
      ..writeByte(6)
      ..write(obj.caption);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GroupGalleryImageAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
