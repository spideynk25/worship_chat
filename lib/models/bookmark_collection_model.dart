class BookmarkCollectionModel {
  final String id;
  final String userId;
  final String name;
  final String? coverImageUrl;
  final List<String> bookmarkIds;
  final DateTime createdAt;
  final DateTime updatedAt;

  const BookmarkCollectionModel({
    required this.id,
    required this.userId,
    required this.name,
    this.coverImageUrl,
    required this.bookmarkIds,
    required this.createdAt,
    required this.updatedAt,
  });

  int get count => bookmarkIds.length;

  bool containsBookmark(String bookmarkId) => bookmarkIds.contains(bookmarkId);

  Map<String, dynamic> toMap() => {
        'id': id,
        'userId': userId,
        'name': name,
        'coverImageUrl': coverImageUrl,
        'bookmarkIds': bookmarkIds,
        'createdAt': createdAt.millisecondsSinceEpoch,
        'updatedAt': updatedAt.millisecondsSinceEpoch,
      };

  factory BookmarkCollectionModel.fromMap(Map<String, dynamic> map) {
    return BookmarkCollectionModel(
      id: map['id'] ?? '',
      userId: map['userId'] ?? '',
      name: map['name'] ?? '',
      coverImageUrl: map['coverImageUrl'] as String?,
      bookmarkIds: (map['bookmarkIds'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          <String>[],
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        map['createdAt'] is int ? map['createdAt'] : 0,
      ),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(
        map['updatedAt'] is int
            ? map['updatedAt']
            : (map['createdAt'] is int ? map['createdAt'] : 0),
      ),
    );
  }

  BookmarkCollectionModel copyWith({
    String? id,
    String? userId,
    String? name,
    String? coverImageUrl,
    List<String>? bookmarkIds,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return BookmarkCollectionModel(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      name: name ?? this.name,
      coverImageUrl: coverImageUrl ?? this.coverImageUrl,
      bookmarkIds: bookmarkIds ?? this.bookmarkIds,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

