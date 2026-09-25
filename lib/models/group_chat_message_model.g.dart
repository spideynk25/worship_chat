// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'group_chat_message_model.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class GroupChatMessageModelAdapter extends TypeAdapter<GroupChatMessageModel> {
  @override
  final int typeId = 2;

  @override
  GroupChatMessageModel read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return GroupChatMessageModel(
      senderId: fields[0] as String? ?? '',
      receiverIds: (fields[1] as List?)?.cast<String>() ?? <String>[],
      text: fields[3] as String? ?? '',
      messageType: fields[4] as String? ?? 'text',
      timeSent: fields[5] as DateTime? ?? DateTime.now(),
      messageId: fields[6] as String? ?? '',
      isSeen: fields[7] as bool? ?? false,
      fileMessageData: fields[8] as String?,
      repliedMessage: fields[9] as String? ?? '',
      repliedTo: fields[10] as String? ?? '',
      repliedMessageType: fields[11] as String? ?? 'text',
      groupId: fields[2] as String? ?? '',
      isDelivered: fields[12] as bool? ?? false,
    );
  }

  @override
  void write(BinaryWriter writer, GroupChatMessageModel obj) {
    writer
      ..writeByte(13)
      ..writeByte(0)
      ..write(obj.senderId)
      ..writeByte(1)
      ..write(obj.receiverIds)
      ..writeByte(2)
      ..write(obj.groupId)
      ..writeByte(3)
      ..write(obj.text)
      ..writeByte(4)
      ..write(obj.messageType)
      ..writeByte(5)
      ..write(obj.timeSent)
      ..writeByte(6)
      ..write(obj.messageId)
      ..writeByte(7)
      ..write(obj.isSeen)
      ..writeByte(8)
      ..write(obj.fileMessageData)
      ..writeByte(9)
      ..write(obj.repliedMessage)
      ..writeByte(10)
      ..write(obj.repliedTo)
      ..writeByte(11)
      ..write(obj.repliedMessageType)
      ..writeByte(12)
      ..write(obj.isDelivered);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GroupChatMessageModelAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
