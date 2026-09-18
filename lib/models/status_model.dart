class Status {
  final String uid;
  final String username;
  final String email;
  final List<String> photoUrl;
  final DateTime createdAt;
  final String profilePic;
  final String statusId;
  final List<String> whoCanSee;

  Status({
    required this.uid,
    required this.username,
    required this.email,
    required this.photoUrl,
    required this.createdAt,
    required this.profilePic,
    required this.statusId,
    required this.whoCanSee,
  });

  factory Status.fromJson(Map<String, dynamic> json) {
    return Status(
      uid: json['uid'] ?? '',
      username: json['username'] ?? '',
      email: json['email'] ?? '',
      photoUrl: List<String>.from(json['photoUrl']),
      createdAt: DateTime.fromMillisecondsSinceEpoch(json['createdAt']),
      profilePic: json['profilePic'],
      statusId: json['statusId'] as String,
      whoCanSee: List<String>.from(json['whoCanSee']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'uid': uid,
      'username': username,
      'email': email,
      'photoUrl': photoUrl,
      'createdAt': createdAt.toIso8601String(),
      'profilePic': profilePic,
      'statusId': statusId,
      'whoCanSee': whoCanSee,
    };
  }
}
