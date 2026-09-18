import 'package:hive/hive.dart';

part 'user_model.g.dart';

@HiveType(typeId: 0)
class UserModel {
  @HiveField(0)
  final String? userName;

  @HiveField(1)
  final String? name;

  @HiveField(2)
  final String? uid;

  @HiveField(3)
  final String? profilePic;

  @HiveField(4)
  final bool? isOnline;

  @HiveField(5)
  final String? email;

  @HiveField(6)
  final List<String>? groupId;
  
  @HiveField(7)
  final String? fcmToken;

  UserModel({
    this.userName,
    this.name,
    this.uid,
    this.profilePic,
    this.isOnline,
    this.email,
    this.groupId,
    this.fcmToken,
  });

  Map<String, dynamic> toMap() {
    return {
      'userName': userName,
      'name': name,
      'uid': uid,
      'profilePic': profilePic,
      'isOnline': isOnline,
      'email': email,
      'groupId': groupId,
      'fcmToken': fcmToken,
    };
  }

  factory UserModel.fromMap(Map<String, dynamic> map) {
    return UserModel(
      userName: map['userName'] ?? '',
      name: map['name'] ?? '',
      uid: map['uid'] ?? '',
      profilePic: map['profilePic'],
      isOnline: map['isOnline'] ?? false,
      email: map['email'] ?? '',
      groupId: List<String>.from(map['groupId'] ?? []),
      fcmToken: map['fcmToken'] ?? '',
    );
  }
}
