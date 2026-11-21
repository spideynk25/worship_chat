import 'dart:io';
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:worship_chat/common/utils/app_capabilities.dart';
import 'package:worship_chat/features/auth/repository/auth_repository.dart';
import 'package:worship_chat/features/auth/controller/auth_controller.dart';
import 'package:worship_chat/models/user_model.dart';

class _Auth implements FirebaseAuth {
  final _User user = _User();
  User? signedInUser;
  bool signedOut = false;

  @override
  User? get currentUser => signedOut ? null : (signedInUser ?? user);

  @override
  Future<UserCredential> createUserWithEmailAndPassword({
    required String email,
    required String password,
  }) async => _Credential(user);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _User implements User {
  _User({this.uid = 'account'});
  @override
  final String uid;
  @override
  String get email => 'user@example.com';
  @override
  String get displayName => 'existing-user';
  @override
  String get photoURL => 'https://example.com/profile.jpg';
  @override
  Future<void> updateDisplayName(String? displayName) async {}
  @override
  Future<void> sendEmailVerification([
    ActionCodeSettings? actionCodeSettings,
  ]) async {}
  @override
  Future<void> updateProfile({String? displayName, String? photoURL}) async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Credential implements UserCredential {
  _Credential(this.user);
  @override
  final User user;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Firestore implements FirebaseFirestore {
  _Firestore({
    bool failProfileRead = false,
    Future<DocumentSnapshot<Map<String, dynamic>>>? pendingRead,
  }) : userDocument = _Document(
         failProfileRead: failProfileRead,
         pendingRead: pendingRead,
       );
  final _Document userDocument;
  @override
  CollectionReference<Map<String, dynamic>> collection(String collectionPath) =>
      _Collection(userDocument);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// Firestore interfaces are intentionally replaced with isolated test doubles.
// ignore: subtype_of_sealed_class
class _Collection implements CollectionReference<Map<String, dynamic>> {
  _Collection(this.document);
  final _Document document;
  @override
  DocumentReference<Map<String, dynamic>> doc([String? path]) => document;
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
  }) => this;
  @override
  Future<QuerySnapshot<Map<String, dynamic>>> get([
    GetOptions? options,
  ]) async => _QuerySnapshot();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _QuerySnapshot implements QuerySnapshot<Map<String, dynamic>> {
  @override
  List<QueryDocumentSnapshot<Map<String, dynamic>>> get docs => [];
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// Firestore interfaces are intentionally replaced with isolated test doubles.
// ignore: subtype_of_sealed_class
class _Document implements DocumentReference<Map<String, dynamic>> {
  _Document({this.failProfileRead = false, this.pendingRead});
  final bool failProfileRead;
  final Future<DocumentSnapshot<Map<String, dynamic>>>? pendingRead;
  final List<Map<String, dynamic>> writes = [];
  Map<String, dynamic>? get lastWrite => writes.isEmpty ? null : writes.last;
  @override
  Future<DocumentSnapshot<Map<String, dynamic>>> get([
    GetOptions? options,
  ]) async {
    if (failProfileRead) throw StateError('Metadata read unavailable');
    if (pendingRead != null) return pendingRead!;
    return _DocumentSnapshot(overrides: lastWrite ?? {});
  }

  @override
  Future<void> set(Map<String, dynamic> data, [SetOptions? options]) async {
    writes.add(Map<String, dynamic>.from(data));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// Firestore interfaces are intentionally replaced with isolated test doubles.
// ignore: subtype_of_sealed_class
class _DocumentSnapshot implements DocumentSnapshot<Map<String, dynamic>> {
  _DocumentSnapshot({this.overrides = const {}});
  final Map<String, dynamic> overrides;
  @override
  bool get exists => true;
  @override
  Map<String, dynamic> data() => {
    'uid': 'account',
    'name': 'Existing name',
    'userName': 'existing-user',
    'isOnline': true,
    'fcmToken': 'registered-phone-token',
    'groupId': ['existing-group'],
    ...overrides,
  };
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Ref implements Ref {
  final invalidatedProviders = <Object>[];
  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #invalidate) {
      invalidatedProviders.add(invocation.positionalArguments.single as Object);
      return null;
    }
    return super.noSuchMethod(invocation);
  }
}

class _IdentityRepository extends AuthRepository {
  _IdentityRepository() : super(auth: _Auth(), firestore: _Firestore());
  UserModel? currentData;
  @override
  Future<UserModel?> getCurrentUserData() async => currentData;
}

class _ProfileAttributionRepository extends AuthRepository {
  _ProfileAttributionRepository(this.metadata)
    : super(auth: _Auth(), firestore: metadata);
  final _Firestore metadata;
  @override
  Future<UserModel?> getCurrentUserData() async => UserModel(
    uid: 'account',
    name:
        metadata.userDocument.lastWrite?['name'] as String? ?? 'Existing name',
  );
}

// Capture navigation without building HomeScreen and starting live Firebase streams.
class _TestNavigator extends Navigator {
  _TestNavigator(Widget child)
    : super(
        onGenerateRoute: (_) => MaterialPageRoute<void>(builder: (_) => child),
      );
  @override
  NavigatorState createState() => _TestNavigatorState();
}

class _TestNavigatorState extends NavigatorState {
  @override
  Future<T?> pushAndRemoveUntil<T extends Object?>(
    Route<T> newRoute,
    RoutePredicate predicate,
  ) async => null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory cacheDirectory;

  setUp(() async {
    AppCapabilities.debugOverride = const AppCapabilities(
      platform: TargetPlatform.iOS,
      isTablet: true,
    );
    cacheDirectory = await Directory.systemTemp.createTemp(
      'gallery_auth_test_',
    );
    Hive.init(cacheDirectory.path);
    if (!Hive.isAdapterRegistered(0)) {
      Hive.registerAdapter(UserModelAdapter());
    }
    await Hive.openBox<UserModel>('userBox');
  });
  tearDown(() async {
    AppCapabilities.debugOverride = null;
    await Hive.close();
    await cacheDirectory.delete(recursive: true);
  });

  Future<BuildContext> mountContext(WidgetTester tester) async {
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        home: _TestNavigator(
          Scaffold(
            body: Builder(
              builder: (value) {
                context = value;
                return const SizedBox();
              },
            ),
          ),
        ),
      ),
    );
    return context;
  }

  testWidgets('gallery account creation succeeds without Firebase Messaging', (
    tester,
  ) async {
    final firestore = _Firestore();
    final repository = AuthRepository(auth: _Auth(), firestore: firestore);
    final context = await mountContext(tester);

    await tester.runAsync(
      () => repository.registerWithEmail(
        context,
        'Gallery user',
        'gallery-user',
        'user@example.com',
        'password',
      ),
    );

    expect(firestore.userDocument.lastWrite?['name'], 'Gallery user');
    expect(firestore.userDocument.lastWrite?['isOnline'], isFalse);
    expect(firestore.userDocument.lastWrite?.containsKey('fcmToken'), isFalse);
    expect(
      Hive.box<UserModel>('userBox').get('currentUser')?.name,
      'Gallery user',
    );
  });

  testWidgets('gallery profile edits preserve phone token and chat presence', (
    tester,
  ) async {
    final firestore = _Firestore();
    final repository = AuthRepository(auth: _Auth(), firestore: firestore);
    final context = await mountContext(tester);

    await tester.runAsync(
      () => repository.saveUserDataToFirebase(
        name: 'Updated gallery name',
        profilePic: null,
        ref: _Ref(),
        context: context,
      ),
    );

    final update = firestore.userDocument.lastWrite!;
    expect(update['name'], 'Updated gallery name');
    expect(update.containsKey('fcmToken'), isFalse);
    expect(update.containsKey('isOnline'), isFalse);
    expect(update.containsKey('groupId'), isFalse);
    final cached = Hive.box<UserModel>('userBox').get('currentUser')!;
    expect(cached.fcmToken, 'registered-phone-token');
    expect(cached.isOnline, isTrue);
  });

  testWidgets('gallery profile edits preserve account fields when reads fail', (
    tester,
  ) async {
    final firestore = _Firestore(failProfileRead: true);
    final repository = AuthRepository(auth: _Auth(), firestore: firestore);
    await tester.runAsync(
      () => Hive.box<UserModel>('userBox').put(
        'currentUser',
        UserModel(
          uid: 'account',
          fcmToken: 'cached-phone-token',
          isOnline: true,
          groupId: ['cached-gallery-group'],
        ),
      ),
    );
    final context = await mountContext(tester);

    await tester.runAsync(
      () => repository.saveUserDataToFirebase(
        name: 'Updated while metadata is unavailable',
        profilePic: null,
        ref: _Ref(),
        context: context,
      ),
    );

    final update = firestore.userDocument.lastWrite!;
    expect(update['name'], 'Updated while metadata is unavailable');
    expect(update.containsKey('fcmToken'), isFalse);
    expect(update.containsKey('isOnline'), isFalse);
    expect(update.containsKey('groupId'), isFalse);
    final cached = Hive.box<UserModel>('userBox').get('currentUser')!;
    expect(cached.fcmToken, 'cached-phone-token');
    expect(cached.isOnline, isTrue);
    expect(cached.groupId, ['cached-gallery-group']);
  });

  test(
    'cached gallery attribution follows logout and account switching',
    () async {
      final authStates = StreamController<User?>();
      final repository = _IdentityRepository()
        ..currentData = UserModel(uid: 'account-a', name: 'Account A');
      final container = ProviderContainer(
        overrides: [
          authRepositoryProvider.overrideWithValue(repository),
          authStateChangesProvider.overrideWith((ref) => authStates.stream),
        ],
      );
      addTearDown(container.dispose);
      addTearDown(authStates.close);

      // Preserve the original eager read, before the auth stream's first event.
      expect(
        (await container.read(userDataAuthProvider.future))?.name,
        'Account A',
      );
      authStates.add(_User(uid: 'account-a'));
      await container.pump();
      expect(
        (await container.read(userDataAuthProvider.future))?.uid,
        'account-a',
      );

      repository.currentData = null;
      authStates.add(null);
      await container.pump();
      expect(await container.read(userDataAuthProvider.future), isNull);

      repository.currentData = UserModel(uid: 'account-b', name: 'Account B');
      authStates.add(_User(uid: 'account-b'));
      await container.pump();
      final switchedUser = await container.read(userDataAuthProvider.future);
      expect(switchedUser?.uid, 'account-b');
      expect(switchedUser?.name, 'Account B');
    },
  );

  testWidgets(
    'profile save refreshes attribution for subsequent gallery uploads',
    (tester) async {
      final repository = _ProfileAttributionRepository(_Firestore());
      final operationRefProvider = Provider<Ref>((ref) => ref);
      final container = ProviderContainer(
        overrides: [
          authRepositoryProvider.overrideWithValue(repository),
          authStateChangesProvider.overrideWith((ref) => const Stream.empty()),
        ],
      );
      addTearDown(container.dispose);
      final context = await mountContext(tester);

      await tester.runAsync(() async {
        await container.pump();
        expect(
          (await container.read(userDataAuthProvider.future))?.name,
          'Existing name',
        );
        await repository.saveUserDataToFirebase(
          name: 'Updated attribution',
          profilePic: null,
          ref: container.read(operationRefProvider),
          context: context,
        );
        final refreshed = await container.read(userDataAuthProvider.future);
        expect(refreshed?.uid, 'account');
        expect(refreshed?.name, 'Updated attribution');
      });
    },
  );

  test(
    'a previous account read cannot overwrite the switched account cache',
    () async {
      final read = Completer<DocumentSnapshot<Map<String, dynamic>>>();
      final auth = _Auth();
      final repository = AuthRepository(
        auth: auth,
        firestore: _Firestore(pendingRead: read.future),
      );
      final newAccount = UserModel(uid: 'account-b', name: 'Account B');
      await Hive.box<UserModel>('userBox').put('currentUser', newAccount);

      final previousRead = repository.getCurrentUserData();
      auth.signedInUser = _User(uid: 'account-b');
      read.complete(_DocumentSnapshot());
      expect(await previousRead, isNull);
      expect(
        Hive.box<UserModel>('userBox').get('currentUser')?.uid,
        'account-b',
      );
    },
  );

  test('gallery lifecycle does not change phone chat presence', () {
    // Auth/firestore fakes have no update method. Any attempted presence access
    // would throw, so this also verifies the guard precedes currentUser access.
    final repository = AuthRepository(auth: _Auth(), firestore: _Firestore());
    repository.setUserState(true);
    repository.setUserState(false);
  });
}
