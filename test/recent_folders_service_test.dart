import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:worship_chat/features/group/services/recent_folders_service.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    RecentFoldersService.setMockPrefs(null);
  });

  test('RecentFoldersService starts with empty recents', () async {
    final list = await RecentFoldersService.getRecentFolders();
    expect(list, isEmpty);
  });

  test('RecentFoldersService adds folders and puts newest first', () async {
    await RecentFoldersService.addRecentFolder('/storage/emulated/0/DCIM/Camera');
    await RecentFoldersService.addRecentFolder('/storage/emulated/0/Download/Photos.zip');

    final list = await RecentFoldersService.getRecentFolders();
    expect(list.length, equals(2));
    expect(list.first.name, equals('Photos'));
    expect(list.first.isZip, isTrue);
    expect(list.last.name, equals('Camera'));
    expect(list.last.isZip, isFalse);
  });

  test('RecentFoldersService dedupes existing paths and brings them to top', () async {
    await RecentFoldersService.addRecentFolder('/storage/folderA');
    await RecentFoldersService.addRecentFolder('/storage/folderB');
    await RecentFoldersService.addRecentFolder('/storage/folderA/'); // Trailing slash

    final list = await RecentFoldersService.getRecentFolders();
    expect(list.length, equals(2));
    expect(list.first.name, equals('folderA'));
    expect(list.last.name, equals('folderB'));
  });

  test('RecentFoldersService removes specific folder and clears all', () async {
    await RecentFoldersService.addRecentFolder('/storage/folder1');
    await RecentFoldersService.addRecentFolder('/storage/folder2');

    await RecentFoldersService.removeRecentFolder('/storage/folder1');
    var list = await RecentFoldersService.getRecentFolders();
    expect(list.length, equals(1));
    expect(list.first.name, equals('folder2'));

    await RecentFoldersService.clearRecentFolders();
    list = await RecentFoldersService.getRecentFolders();
    expect(list, isEmpty);
  });

  test('RecentFoldersService caps at maximum limit', () async {
    for (int i = 0; i < 20; i++) {
      await RecentFoldersService.addRecentFolder('/storage/folder_$i');
    }
    final list = await RecentFoldersService.getRecentFolders();
    expect(list.length, equals(RecentFoldersService.maxRecentFolders));
    expect(list.first.name, equals('folder_19'));
  });
}

