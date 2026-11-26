// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'one_to_one_message_model.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class OneToOneMessageModelAdapter extends TypeAdapter<OneToOneMessageModel> {
  @override
  final int typeId = 1;

  @override
  OneToOneMessageModel read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return OneToOneMessageModel(
      senderId: fields[0] as String? ?? '',
      receiverId: fields[1] as String? ?? '',
      text: fields[2] as String? ?? '',
      messageType: fields[3] as String? ?? 'text',
      timeSent: fields[4] as DateTime? ?? DateTime.now(),
      messageId: fields[5] as String? ?? '',
      isSeen: fields[6] as bool? ?? false,
      fileMessageData: fields[7] as String?,
      repliedMessage: fields[8] as String? ?? '',
      repliedTo: fields[9] as String? ?? '',
      repliedMessageType: fields[10] as String? ?? 'text',
      isDelivered: fields[11] as bool? ?? false,
      reactions: (fields[12] is Map)
          ? Map<String, String>.from(
              (fields[12] as Map).map(
                (k, v) => MapEntry(k.toString(), v.toString()),
              ),
            )
          : const {},
      isEdited: fields[13] as bool? ?? false,
      isDeleted: fields[14] as bool? ?? false,
      deletedFor: (fields[15] as List?)?.cast<String>() ?? const <String>[],
      isPinned: fields[16] as bool? ?? false,
      pinnedAt: fields[17] as DateTime?,
      pinnedBy: fields[18] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, OneToOneMessageModel obj) {
    writer
      ..writeByte(19)
      ..writeByte(0)
      ..write(obj.senderId)
      ..writeByte(1)
      ..write(obj.receiverId)
      ..writeByte(2)
      ..write(obj.text)
      ..writeByte(3)
      ..write(obj.messageType)
      ..writeByte(4)
      ..write(obj.timeSent)
      ..writeByte(5)
      ..write(obj.messageId)
      ..writeByte(6)
      ..write(obj.isSeen)
      ..writeByte(7)
      ..write(obj.fileMessageData)
      ..writeByte(8)
      ..write(obj.repliedMessage)
      ..writeByte(9)
      ..write(obj.repliedTo)
      ..writeByte(10)
      ..write(obj.repliedMessageType)
      ..writeByte(11)
      ..write(obj.isDelivered)
      ..writeByte(12)
      ..write(obj.reactions)
      ..writeByte(13)
      ..write(obj.isEdited)
      ..writeByte(14)
      ..write(obj.isDeleted)
      ..writeByte(15)
      ..write(obj.deletedFor)
      ..writeByte(16)
      ..write(obj.isPinned)
      ..writeByte(17)
      ..write(obj.pinnedAt)
      ..writeByte(18)
      ..write(obj.pinnedBy);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is OneToOneMessageModelAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
