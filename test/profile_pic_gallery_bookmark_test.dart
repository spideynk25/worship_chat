import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:worship_chat/common/widgets/set_as_profile_pic_sheet.dart';
import 'package:worship_chat/features/auth/controller/auth_controller.dart';
import 'package:worship_chat/features/auth/repository/auth_repository.dart';
import 'package:worship_chat/features/bookmark/controller/bookmark_controller.dart';
import 'package:worship_chat/features/group/controller/group_controller.dart';
import 'package:worship_chat/features/group/controller/group_gallery_controller.dart';
import 'package:worship_chat/features/group/repository/group_repository.dart';
import 'package:worship_chat/features/group/screens/edit_group_screen.dart';
import 'package:worship_chat/features/home/screens/profile_screen.dart';
import 'package:worship_chat/models/bookmark_collection_model.dart';
import 'package:worship_chat/models/bookmark_model.dart';
import 'package:worship_chat/models/group.dart';
import 'package:worship_chat/models/group_gallery_image.dart';
import 'package:worship_chat/models/user_model.dart';

class _FakeUser implements User {
  _FakeUser({
    required this.uid,
    String? displayName,
    String? photoURL,
    String? email,
  })  : _displayName = displayName,
        _photoURL = photoURL,
        _email = email ?? '$uid@example.com';

  @override
  final String uid;
  String? _displayName;
  String? _photoURL;
  final String? _email;

  @override
  String? get displayName => _displayName;

  @override
  String? get photoURL => _photoURL;

  @override
  String? get email => _email;

  @override
  Future<void> updateProfile({String? displayName, String? photoURL}) async {
    _displayName = displayName ?? _displayName;
    _photoURL = photoURL;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeAuth implements FirebaseAuth {
  _FakeAuth(this._user);
  final _FakeUser _user;

  @override
  User? get currentUser => _user;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// Firestore interfaces are replaced with isolated test doubles.
// ignore: subtype_of_sealed_class
class _FakeQueryDocumentSnapshot
    implements QueryDocumentSnapshot<Map<String, dynamic>> {
  _FakeQueryDocumentSnapshot(this._id, this._data, this._reference);
  final String _id;
  final Map<String, dynamic> _data;
  final DocumentReference<Map<String, dynamic>> _reference;

  @override
  String get id => _id;

  @override
  bool get exists => true;

  @override
  Map<String, dynamic> data() => _data;

  @override
  DocumentReference<Map<String, dynamic>> get reference => _reference;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// Firestore interfaces are replaced with isolated test doubles.
// ignore: subtype_of_sealed_class
class _FakeDocSnapshot implements DocumentSnapshot<Map<String, dynamic>> {
  _FakeDocSnapshot(this._id, this._data);
  final String _id;
  final Map<String, dynamic>? _data;

  @override
  String get id => _id;

  @override
  bool get exists => _data != null;

  @override
  Map<String, dynamic>? data() => _data;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// Firestore interfaces are replaced with isolated test doubles.
// ignore: subtype_of_sealed_class
class _FakeQuerySnapshot implements QuerySnapshot<Map<String, dynamic>> {
  _FakeQuerySnapshot(this._docs);
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> _docs;

  @override
  List<QueryDocumentSnapshot<Map<String, dynamic>>> get docs => _docs;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeWriteBatch implements WriteBatch {
  _FakeWriteBatch(this.store);
  final _FakeFirestore store;
  final List<({String path, Map<String, dynamic> data})> _ops = [];

  @override
  void update(DocumentReference<Object?> document, Map<String, dynamic> data) {
    final docRef = document as _FakeDocRef;
    _ops.add((path: docRef.pathKey, data: Map<String, dynamic>.from(data)));
  }

  @override
  Future<void> commit() async {
    for (final op in _ops) {
      final existing = Map<String, dynamic>.from(store.docs[op.path] ?? {});
      existing.addAll(op.data);
      store.docs[op.path] = existing;
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// Firestore interfaces are replaced with isolated test doubles.
// ignore: subtype_of_sealed_class
class _FakeDocRef implements DocumentReference<Map<String, dynamic>> {
  _FakeDocRef(this.pathKey, this.store);
  final String pathKey;
  final _FakeFirestore store;

  @override
  Future<DocumentSnapshot<Map<String, dynamic>>> get([GetOptions? options]) async {
    return _FakeDocSnapshot(pathKey.split('/').last, store.docs[pathKey]);
  }

  @override
  Future<void> set(Map<String, dynamic> data, [SetOptions? options]) async {
    if (options?.merge == true) {
      final existing = Map<String, dynamic>.from(store.docs[pathKey] ?? {});
      existing.addAll(data);
      store.docs[pathKey] = existing;
    } else {
      store.docs[pathKey] = Map<String, dynamic>.from(data);
    }
  }

  @override
  Future<void> update(Map<Object, Object?> data) async {
    final existing = Map<String, dynamic>.from(store.docs[pathKey] ?? {});
    data.forEach((k, v) {
      existing[k.toString()] = v;
    });
    store.docs[pathKey] = existing;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// Firestore interfaces are replaced with isolated test doubles.
// ignore: subtype_of_sealed_class
class _FakeCollection implements CollectionReference<Map<String, dynamic>> {
  _FakeCollection(this.name, this.store);
  final String name;
  final _FakeFirestore store;

  @override
  DocumentReference<Map<String, dynamic>> doc([String? path]) {
    final id = path ?? 'doc_${store.docs.length}';
    return _FakeDocRef('$name/$id', store);
  }

  @override
  Query<Map<String, dynamic>> where(
    Object field, {
    Object? isEqualTo,
    Object? isNotEqualTo,
    Object? isLessThan,
    Object? isLessThanOrEqualTo,
    Object? isGreaterThan,
    Object? isGreaterThanOrEqualTo,
    Object? arrayContains,
    Iterable<Object?>? arrayContainsAny,
    Iterable<Object?>? whereIn,
    Iterable<Object?>? whereNotIn,
    bool? isNull,
  }) =>
      this;

  @override
  Future<QuerySnapshot<Map<String, dynamic>>> get([GetOptions? options]) async {
    final prefix = '$name/';
    final matching = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    store.docs.forEach((key, val) {
      if (key.startsWith(prefix) && !key.substring(prefix.length).contains('/')) {
        final id = key.substring(prefix.length);
        matching.add(_FakeQueryDocumentSnapshot(id, val, _FakeDocRef(key, store)));
      }
    });
    return _FakeQuerySnapshot(matching);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeFirestore implements FirebaseFirestore {
  final Map<String, Map<String, dynamic>> docs = {};

  @override
  CollectionReference<Map<String, dynamic>> collection(String collectionPath) {
    return _FakeCollection(collectionPath, this);
  }

  @override
  WriteBatch batch() => _FakeWriteBatch(this);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeAuthController extends Fake implements AuthController {
  String? updatedProfileUrl;
  File? updatedProfileFile;
  int updateProfilePicCalls = 0;

  String? savedName;
  String? savedUrlOverride;
  File? savedFile;
  bool? savedRemoveFlag;
  int saveUserCalls = 0;

  @override
  Future<bool> updateCurrentUserProfilePic({
    BuildContext? context,
    File? imageFile,
    String? imageUrl,
  }) async {
    updateProfilePicCalls++;
    updatedProfileFile = imageFile;
    updatedProfileUrl = imageUrl;
    return true;
  }

  @override
  Future<bool> saveUserDatatoFirebase(
    BuildContext context,
    String name,
    File? profilePic, {
    String? userName,
    String? profilePicUrlOverride,
    bool navigateHomeOnComplete = true,
    bool removeProfilePic = false,
  }) async {
    saveUserCalls++;
    savedName = name;
    savedFile = profilePic;
    savedUrlOverride = profilePicUrlOverride;
    savedRemoveFlag = removeProfilePic;
    return true;
  }
}

class _FakeGroupController extends Fake implements GroupController {
  _FakeGroupController(this.groups);

  final List<GroupModel> groups;
  String? updatedGroupId;
  String? updatedGroupImageUrl;
  String? updatedGroupType;
  int updateGroupPicCalls = 0;

  String? editSavedGroupId;
  String? editSavedGroupPicUrl;

  @override
  Future<List<GroupModel>> getAllGroupsForPicker() async => groups;

  @override
  Future<bool> updateGroupProfilePic({
    required String groupId,
    File? imageFile,
    String? imageUrl,
    String type = 'group',
  }) async {
    updateGroupPicCalls++;
    updatedGroupId = groupId;
    updatedGroupImageUrl = imageUrl;
    updatedGroupType = type;
    return true;
  }

  @override
  Future<List<int>> getTakenPriorities({
    required String queendom,
    required String position,
    String? excludeGroupId,
  }) async =>
      const [];

  @override
  Future<void> updateGroup(
    BuildContext context,
    String groupId,
    String name,
    String? wish,
    String selectedQueendom,
    String selectedFamily,
    String selectedPosition,
    File? groupProfilePic,
    String type, {
    String? groupProfilePicUrl,
    String? livingPlace,
    int? priority,
    String? parentGroupId,
    String? parentGroupName,
    bool? isSubGroup,
    String? subGroupType,
  }) async {
    editSavedGroupId = groupId;
    editSavedGroupPicUrl = groupProfilePicUrl;
  }
}

class _FakeGroupGalleryController extends Fake
    implements GroupGalleryController {
  _FakeGroupGalleryController(this.imagesByGroup);
  final Map<String, List<GroupGalleryImage>> imagesByGroup;

  @override
  Stream<List<GroupGalleryImage>> getGalleryStream(String groupId) {
    return Stream.value(imagesByGroup[groupId] ?? const []);
  }

  @override
  Future<List<GroupGalleryImage>> getAllGalleryImagesForPicker(
    List<String> groupIds, {
    int maxPerGroup = 60,
  }) async {
    final all = <GroupGalleryImage>[];
    for (final id in groupIds) {
      all.addAll(imagesByGroup[id] ?? const []);
    }
    return all;
  }
}

class _FakeBookmarkController extends Fake implements BookmarkController {
  _FakeBookmarkController(this.bookmarks, this.collections);
  final List<BookmarkModel> bookmarks;
  final List<BookmarkCollectionModel> collections;

  @override
  Stream<List<BookmarkModel>> myBookmarks() => Stream.value(bookmarks);

  @override
  Stream<List<BookmarkCollectionModel>> collectionsForUser(String userId) =>
      Stream.value(collections);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDir = await Directory.systemTemp.createTemp('profile_pic_picker_test_');
    Hive.init(tempDir.path);
    if (!Hive.isAdapterRegistered(0)) {
      Hive.registerAdapter(UserModelAdapter());
    }
    await Hive.openBox<UserModel>('userBox');
    await Hive.openBox('groups_cache');
  });

  tearDown(() async {
    await Hive.close();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('Repository & Cache Profile Pic Updates', () {
    test(
      'AuthRepository.updateCurrentUserProfilePic applies remote URL directly to Auth, Firestore, Hive, Prefs & Bookmarks',
      () async {
        final userBox = Hive.box<UserModel>('userBox');
        await userBox.put(
          'currentUser',
          UserModel(
            uid: 'u_devotee',
            name: 'Devotee',
            userName: 'devotee',
            email: 'd@example.com',
            profilePic: 'https://old.example/pic.jpg',
          ),
        );

        final fakeFirestore = _FakeFirestore();
        fakeFirestore.docs['users/u_devotee'] = {
          'uid': 'u_devotee',
          'name': 'Devotee',
          'userName': 'devotee',
          'profilePic': 'https://old.example/pic.jpg',
        };
        fakeFirestore.docs['bookmarks/bm_1'] = {
          'bookmarkId': 'bm_1',
          'userId': 'u_devotee',
          'userName': 'Devotee',
          'userProfilePic': 'https://old.example/pic.jpg',
          'imageUrl': 'http://res.cloudinary.com/demo/sample.jpg',
        };

        final fakeUser = _FakeUser(
          uid: 'u_devotee',
          displayName: 'devotee',
          photoURL: 'https://old.example/pic.jpg',
        );
        final repo = AuthRepository(
          auth: _FakeAuth(fakeUser),
          firestore: fakeFirestore,
        );

        final container = ProviderContainer();
        addTearDown(container.dispose);
        final provider = Provider((ref) => ref);
        final ref = container.read(provider);

        final ok = await repo.updateCurrentUserProfilePic(
          ref: ref,
          imageUrl: 'http://res.cloudinary.com/demo/sample.jpg',
        );

        expect(ok, isTrue);
        const expectedHttps = 'https://res.cloudinary.com/demo/sample.jpg';
        expect(fakeUser.photoURL, expectedHttps);
        expect(fakeFirestore.docs['users/u_devotee']?['profilePic'], expectedHttps);
        expect(
          Hive.box<UserModel>('userBox').get('currentUser')?.profilePic,
          expectedHttps,
        );
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString('cached_current_user_pic'), expectedHttps);
        expect(
          fakeFirestore.docs['bookmarks/bm_1']?['userProfilePic'],
          expectedHttps,
        );
      },
    );

    test(
      'GroupRepository.updateGroupProfilePic updates Firestore and Hive groups_cache cleanly',
      () async {
        final groupsCache = Hive.box('groups_cache');
        await groupsCache.put('groups_pooja_u_devotee', [
          {
            'groupId': 'grp_pooja_1',
            'name': 'Pooja Hegde',
            'groupPic': 'https://old.example/pooja.jpg',
            'membersUid': ['u_devotee'],
            'senderId': 'u_devotee',
            'lastMessage': '',
            'timeSent': DateTime.now().millisecondsSinceEpoch,
            'fcmTokens': <String>[],
            'unseenMessages': <String, bool>{},
          },
        ]);

        final fakeFirestore = _FakeFirestore();
        fakeFirestore.docs['groups/grp_pooja_1'] = {
          'groupId': 'grp_pooja_1',
          'name': 'Pooja Hegde',
          'groupPic': 'https://old.example/pooja.jpg',
          'membersUid': ['u_devotee'],
        };
        final fakeAuth = _FakeAuth(_FakeUser(uid: 'u_devotee'));

        final container = ProviderContainer();
        addTearDown(container.dispose);
        final ref = container.read(Provider((r) => r));
        final repo = GroupRepository(
          firestore: fakeFirestore,
          auth: fakeAuth,
          ref: ref,
        );

        final ok = await repo.updateGroupProfilePic(
          groupId: 'grp_pooja_1',
          imageUrl: 'http://cdn.example.com/new_pooja.jpg',
          type: 'queenPooja',
        );

        expect(ok, isTrue);
        const expectedUrl = 'https://cdn.example.com/new_pooja.jpg';
        expect(
          fakeFirestore.docs['groups/grp_pooja_1']?['groupPic'],
          expectedUrl,
        );
        final cached = Hive.box('groups_cache').get('groups_pooja_u_devotee') as List;
        expect((cached.first as Map)['groupPic'], expectedUrl);

        final pickerGroups = await repo.getAllGroupsForPicker();
        expect(pickerGroups.any((g) => g.groupId == 'grp_pooja_1'), isTrue);
        expect(
          pickerGroups.firstWhere((g) => g.groupId == 'grp_pooja_1').groupPic,
          expectedUrl,
        );
      },
    );

    testWidgets(
      'GroupRepository.updateGroup persists groupProfilePicUrl without file upload',
      (tester) async {
        final fakeFirestore = _FakeFirestore();
        fakeFirestore.docs['groups/grp_edit_url'] = {
          'groupId': 'grp_edit_url',
          'name': 'Aura Deity',
          'groupPic': 'https://old.example/a.jpg',
          'membersUid': ['u_devotee'],
        };
        await tester.runAsync(
          () => Hive.box('groups_cache').put('groups_pooja_u_devotee', [
            {
              'groupId': 'grp_edit_url',
              'name': 'Aura Deity',
              'groupPic': 'https://old.example/a.jpg',
              'membersUid': ['u_devotee'],
              'senderId': 'u_devotee',
              'lastMessage': '',
              'timeSent': DateTime.now().millisecondsSinceEpoch,
              'fcmTokens': <String>[],
              'unseenMessages': <String, bool>{},
            },
          ]),
        );

        late BuildContext capturedContext;
        late WidgetRef capturedRef;
        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              home: Scaffold(
                body: Consumer(
                  builder: (context, ref, _) {
                    capturedContext = context;
                    capturedRef = ref;
                    return const SizedBox();
                  },
                ),
              ),
            ),
          ),
        );

        final fakeAuth = _FakeAuth(_FakeUser(uid: 'u_devotee'));
        final repo = GroupRepository(
          firestore: fakeFirestore,
          auth: fakeAuth,
          ref: capturedRef.read(Provider((r) => r)),
        );

        await tester.runAsync(() async {
          repo.updateGroup(
            capturedContext,
            'grp_edit_url',
            'Aura Deity Updated',
            'Wish',
            'Queen Pooja',
            'Aura',
            'Aura Elixiria',
            null,
            'queenPooja',
            groupProfilePicUrl: 'http://cdn.example.com/updated_url.jpg',
          );
          await Future<void>.delayed(const Duration(milliseconds: 50));
        });

        expect(
          fakeFirestore.docs['groups/grp_edit_url']?['groupPic'],
          'https://cdn.example.com/updated_url.jpg',
        );
        final cached =
            Hive.box('groups_cache').get('groups_pooja_u_devotee') as List;
        expect(
          (cached.first as Map)['groupPic'],
          'https://cdn.example.com/updated_url.jpg',
        );
      },
    );
  });

  group('UI Widget Flows for Gallery & Bookmark Profile Pics', () {
    final groupPooja = GroupModel(
      senderId: 'u1',
      name: 'Pooja Hegde',
      groupId: 'grp_pooja',
      lastMessage: '',
      groupPic: '',
      membersUid: const ['u1'],
      timeSent: DateTime.now(),
      fcmTokens: const [],
      unseenMessages: const {},
      queendom: 'Queen Pooja',
      position: 'Aura Elixiria',
      wish: 'All Hail Goddess Pooja',
      priority: 1,
    );
    final groupRashmika = GroupModel(
      senderId: 'u1',
      name: 'Rashmika Mandanna',
      groupId: 'grp_rashmika',
      lastMessage: '',
      groupPic: '',
      membersUid: const ['u1'],
      timeSent: DateTime.now(),
      fcmTokens: const [],
      unseenMessages: const {},
      queendom: 'Queen Rashmika',
      position: 'Queen',
    );

    testWidgets(
      'SetAsProfilePicSheet updates My Profile Pic and Group Profile Pics',
      (tester) async {
        await tester.runAsync(
          () => Hive.box<UserModel>('userBox').put(
            'currentUser',
            UserModel(uid: 'u1', name: 'Royal Devotee', userName: 'royal'),
          ),
        );

        final fakeAuthCtrl = _FakeAuthController();
        final fakeGroupCtrl = _FakeGroupController([groupPooja, groupRashmika]);
        const pickedUrl = 'https://example.com/divine.jpg';

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              authControllerProvider.overrideWithValue(fakeAuthCtrl),
              groupControllerProvider.overrideWithValue(fakeGroupCtrl),
            ],
            child: MaterialApp(
              home: Scaffold(
                body: Builder(
                  builder: (context) => Center(
                    child: ElevatedButton(
                      onPressed: () => SetAsProfilePicSheet.show(
                        context,
                        imageUrl: pickedUrl,
                        sourceGroupId: 'grp_pooja',
                        sourceGroupName: 'Pooja Hegde',
                        title: 'Divine Portrait',
                      ),
                      child: const Text('Open Set Sheet'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );

        // 1. Open sheet and set as My Profile Pic
        await tester.tap(find.text('Open Set Sheet'));
        await tester.pumpAndSettle();

        expect(find.text('Set as Profile Pic'), findsOneWidget);
        expect(find.text('My Profile Pic'), findsOneWidget);
        expect(find.textContaining('Update "'), findsOneWidget);

        await tester.tap(find.text('My Profile Pic'));
        await tester.pumpAndSettle();

        expect(fakeAuthCtrl.updateProfilePicCalls, 1);
        expect(fakeAuthCtrl.updatedProfileUrl, pickedUrl);

        // 2. Re-open and choose another Group / Deity via search
        await tester.tap(find.text('Open Set Sheet'));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Choose Any Group / Deity'));
        await tester.pumpAndSettle();

        await tester.enterText(
          find.widgetWithText(TextField, 'Search deity or group...'),
          'Rashmika',
        );
        await tester.pumpAndSettle();

        await tester.tap(find.textContaining('Rashmika Mandanna').last);
        await tester.pumpAndSettle();

        expect(fakeGroupCtrl.updateGroupPicCalls, 1);
        expect(fakeGroupCtrl.updatedGroupId, 'grp_rashmika');
        expect(fakeGroupCtrl.updatedGroupImageUrl, pickedUrl);
        expect(fakeGroupCtrl.updatedGroupType, 'queenRashmika');
      },
    );

    testWidgets(
      'ProfileScreen source sheet offers App Gallery & Bookmarks and saves URL override',
      (tester) async {
        await tester.runAsync(
          () => Hive.box<UserModel>('userBox').put(
            'currentUser',
            UserModel(
              uid: 'u1',
              name: 'Royal Devotee',
              userName: 'royal_bhakt',
              email: 'devotee@example.com',
              profilePic: 'https://example.com/old.jpg',
            ),
          ),
        );

        final fakeAuthCtrl = _FakeAuthController();
        final fakeGroupCtrl = _FakeGroupController([groupPooja]);
        final fakeGalleryCtrl = _FakeGroupGalleryController({
          'grp_pooja': [
            GroupGalleryImage(
              imageId: 'img_1',
              groupId: 'grp_pooja',
              imageUrl: 'https://example.com/from_app_gallery.jpg',
              uploadedBy: 'u1',
              uploadedByName: 'Royal',
              uploadedAt: DateTime(2026, 11, 25),
              caption: 'Golden Crown',
            ),
          ],
        });
        final fakeBookmarkCtrl = _FakeBookmarkController(
          [
            BookmarkModel(
              bookmarkId: 'bm_1',
              userId: 'u1',
              userName: 'Royal',
              userProfilePic: '',
              imageUrl: 'https://example.com/from_bookmark.jpg',
              groupId: 'grp_pooja',
              groupName: 'Pooja Hegde',
              bookmarkedAt: DateTime(2026, 11, 25),
            ),
          ],
          const [],
        );

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              authControllerProvider.overrideWithValue(fakeAuthCtrl),
              groupControllerProvider.overrideWithValue(fakeGroupCtrl),
              groupGalleryControllerProvider.overrideWithValue(fakeGalleryCtrl),
              bookmarkControllerProvider.overrideWithValue(fakeBookmarkCtrl),
            ],
            child: const MaterialApp(home: ProfileScreen()),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byIcon(Icons.camera_alt_rounded));
        await tester.pumpAndSettle();

        expect(find.text('Choose from App Gallery'), findsOneWidget);
        expect(find.text('Choose from Bookmarks'), findsOneWidget);

        await tester.tap(find.text('Choose from App Gallery'));
        await tester.pumpAndSettle();

        expect(find.text('Choose Profile Photo'), findsOneWidget);
        expect(find.text('Golden Crown'), findsOneWidget);

        await tester.tap(find.text('Golden Crown'));
        await tester.pumpAndSettle();

        expect(find.text('You have unsaved profile changes'), findsOneWidget);
        await tester.ensureVisible(find.text('Update Profile'));
        await tester.tap(find.text('Update Profile'));
        await tester.pumpAndSettle();

        expect(fakeAuthCtrl.saveUserCalls, 1);
        expect(
          fakeAuthCtrl.savedUrlOverride,
          'https://example.com/from_app_gallery.jpg',
        );
      },
    );

    testWidgets(
      'EditGroupScreen source sheet allows picking from Bookmarks directly',
      (tester) async {
        await tester.runAsync(
          () => Hive.box<UserModel>('userBox').put(
            'currentUser',
            UserModel(uid: 'u1', name: 'Royal Devotee', userName: 'royal'),
          ),
        );

        final fakeGroupCtrl = _FakeGroupController([groupPooja]);
        final fakeGalleryCtrl = _FakeGroupGalleryController(const {});
        final fakeBookmarkCtrl = _FakeBookmarkController(
          [
            BookmarkModel(
              bookmarkId: 'bm_99',
              userId: 'u1',
              userName: 'Royal',
              userProfilePic: '',
              imageUrl: 'https://example.com/bookmark_selected.jpg',
              groupId: 'grp_pooja',
              groupName: 'Sanctum Favs',
              bookmarkedAt: DateTime(2026, 11, 25),
            ),
          ],
          [
            BookmarkCollectionModel(
              id: 'col_1',
              userId: 'u1',
              name: 'Favorites',
              bookmarkIds: const ['bm_99'],
              createdAt: DateTime(2026, 11, 25),
              updatedAt: DateTime(2026, 11, 25),
            ),
          ],
        );

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              groupControllerProvider.overrideWithValue(fakeGroupCtrl),
              groupGalleryControllerProvider.overrideWithValue(fakeGalleryCtrl),
              bookmarkControllerProvider.overrideWithValue(fakeBookmarkCtrl),
            ],
            child: MaterialApp(
              home: Scaffold(
                body: Builder(
                  builder: (context) => ElevatedButton(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => EditGroupScreen(
                          group: groupPooja,
                          type: 'queenPooja',
                        ),
                      ),
                    ),
                    child: const Text('Open Edit'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Open Edit'));
        await tester.pumpAndSettle();

        await tester.tap(find.byIcon(Icons.camera_alt));
        await tester.pumpAndSettle();

        expect(find.text('Choose from App Gallery'), findsOneWidget);
        expect(find.text('Choose from Bookmarks'), findsOneWidget);

        await tester.tap(find.text('Choose from Bookmarks'));
        await tester.pumpAndSettle();

        expect(find.text('Sanctum Favs'), findsOneWidget);
        await tester.tap(find.text('Sanctum Favs'));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Save'));
        await tester.pumpAndSettle();

        expect(fakeGroupCtrl.editSavedGroupId, 'grp_pooja');
        expect(
          fakeGroupCtrl.editSavedGroupPicUrl,
          'https://example.com/bookmark_selected.jpg',
        );
      },
    );
  });
}
