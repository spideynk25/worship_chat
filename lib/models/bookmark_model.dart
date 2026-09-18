class BookmarkModel {
  final String bookmarkId;
  final String userId;
  final String userName;
  final String userProfilePic;
  final String imageUrl;
  final String groupId;
  final String groupName;
  final DateTime bookmarkedAt;

  BookmarkModel({
    required this.bookmarkId,
    required this.userId,
    required this.userName,
    required this.userProfilePic,
    required this.imageUrl,
    required this.groupId,
    required this.groupName,
    required this.bookmarkedAt,
  });

  Map<String, dynamic> toMap() => {
        'bookmarkId': bookmarkId,
        'userId': userId,
        'userName': userName,
        'userProfilePic': userProfilePic,
        'imageUrl': imageUrl,
        'groupId': groupId,
        'groupName': groupName,
        'bookmarkedAt': bookmarkedAt.millisecondsSinceEpoch,
      };

  factory BookmarkModel.fromMap(Map<String, dynamic> map) => BookmarkModel(
        bookmarkId: map['bookmarkId'] ?? '',
        userId: map['userId'] ?? '',
        userName: map['userName'] ?? '',
        userProfilePic: map['userProfilePic'] ?? '',
        imageUrl: map['imageUrl'] ?? '',
        groupId: map['groupId'] ?? '',
        groupName: map['groupName'] ?? '',
        bookmarkedAt: DateTime.fromMillisecondsSinceEpoch(
          map['bookmarkedAt'] ?? 0,
        ),
      );
}