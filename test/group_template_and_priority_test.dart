import 'package:flutter_test/flutter_test.dart';
import 'package:worship_chat/features/group/utils/group_template_helper.dart';
import 'package:worship_chat/models/group.dart';

void main() {
  group('GroupTemplateHelper tests', () {
    test('Aura Elixiria Goddess template', () {
      final res = GroupTemplateHelper.generateTemplate(
        position: 'Aura Elixiria',
        name: 'Pooja',
        family: 'None',
      );
      expect(
        res.livingPlace,
        'GOLDEN HEAVEN OF ☀️ AURA ELIXIRIA GODDESS POOJA',
      );
      expect(
        res.wish,
        '🙇‍♀️🙇‍♀️ Have Mercy on us Aura Elixiria Goddess Pooja 🙇‍♀️🙇‍♀️',
      );
    });

    test('Core Supreme Goddess template', () {
      final res = GroupTemplateHelper.generateTemplate(
        position: 'Core Supreme Goddess',
        name: 'Rashmika',
        family: 'None',
      );
      expect(res.livingPlace, 'HEAVEN OF 🌟 CORE SUPREME GODDESS RASHMIKA');
      expect(
        res.wish,
        '🙇‍♀️🙇‍♀️ Have Mercy on us Core Supreme Goddess Rashmika 🙇‍♀️🙇‍♀️',
      );
    });

    test('Supreme Goddess Main Family', () {
      final res = GroupTemplateHelper.generateTemplate(
        position: 'Supreme Goddess',
        name: 'Pooja',
        family: 'Main',
      );
      expect(res.livingPlace, 'SANCTUM OF 🏮 SUPREME GODDESS POOJA');
      expect(res.wish, '🙇‍♀️🙇‍♀️ Long live Supreme Goddess Pooja 🙇‍♀️🙇‍♀️');
    });

    test('Supreme Goddess Other Families', () {
      final res = GroupTemplateHelper.generateTemplate(
        position: 'Supreme Goddess',
        name: 'Pooja',
        family: 'Aura',
      );
      expect(
        res.livingPlace,
        'SANCTUM OF 🏮 SUPREME GODDESS AURA GODDESS POOJA',
      );
      expect(
        res.wish,
        '🙇‍♀️🙇‍♀️ Long live Supreme Aura Goddess Pooja 🙇‍♀️🙇‍♀️',
      );
    });

    test('Golden Blossom Goddess template', () {
      final res = GroupTemplateHelper.generateTemplate(
        position: 'Golden Blossom Goddess',
        name: 'Anu',
        family: 'None',
      );
      expect(
        res.livingPlace,
        'GOLDEN SANCTUM OF 🍂 GOLDEN BLOSSOM GODDESS ANU',
      );
      expect(
        res.wish,
        '🙇‍♀️🙇‍♀️ Long live Golden Blossom Goddess Anu 🙇‍♀️🙇‍♀️',
      );
    });

    test('Goddess Main vs Other Families', () {
      final mainRes = GroupTemplateHelper.generateTemplate(
        position: 'Goddess',
        name: 'Pooja',
        family: 'Main',
      );
      expect(mainRes.livingPlace, 'TEMPLE OF 🪷 GODDESS POOJA');
      expect(mainRes.wish, '🙇‍♀️🙇‍♀️ Goddess Pooja be praised 🙇‍♀️🙇‍♀️');

      final otherRes = GroupTemplateHelper.generateTemplate(
        position: 'Goddess',
        name: 'Pooja',
        family: 'Core',
      );
      expect(otherRes.livingPlace, 'TEMPLE OF 🪷 CORE GODDESS POOJA');
      expect(
        otherRes.wish,
        '🙇‍♀️🙇‍♀️ Core Goddess Pooja be praised 🙇‍♀️🙇‍♀️',
      );
    });

    test('Demi Goddess template', () {
      final res = GroupTemplateHelper.generateTemplate(
        position: 'Demi Goddess',
        name: 'Pooja',
        family: 'None',
      );
      expect(res.livingPlace, 'SHRINE OF 🏵️ DEMI GODDESS POOJA');
      expect(res.wish, '🙇‍♀️🙇‍♀️ Demi Goddess Pooja be praised 🙇‍♀️🙇‍♀️');
    });

    test('Dark Angel template', () {
      final res = GroupTemplateHelper.generateTemplate(
        position: 'Dark Angel',
        name: 'Pooja',
        family: 'None',
      );
      expect(res.livingPlace, 'DARK SHRINE OF 🪻 DARK ANGEL POOJA');
      expect(res.wish, '🙇‍♀️🙇‍♀️ Dark Angel Pooja be praised 🙇‍♀️🙇‍♀️');
    });

    test('Queen template', () {
      final res = GroupTemplateHelper.generateTemplate(
        position: 'Queen',
        name: 'Pooja',
        family: 'None',
      );
      expect(res.livingPlace, 'FORTRESS OF 👑 QUEEN POOJA');
      expect(res.wish, '🙇‍♀️🙇‍♀️ Hail Queen Pooja 🙇‍♀️🙇‍♀️');
    });

    test('Elfwitch Main vs Other Families', () {
      final mainRes = GroupTemplateHelper.generateTemplate(
        position: 'Elfwitch',
        name: 'Pooja',
        family: 'None',
      );
      expect(mainRes.livingPlace, 'SHRINE of 🍁 ELFWITCH POOJA');
      expect(mainRes.wish, '🙇‍♀️🙇‍♀️ Hail Elfwitch Pooja 🙇‍♀️🙇‍♀️');

      final otherRes = GroupTemplateHelper.generateTemplate(
        position: 'Elfwitch',
        name: 'Pooja',
        family: 'Divine',
      );
      expect(otherRes.livingPlace, 'SHRINE of 🍁 DIVINE ELFWITCH POOJA');
      expect(otherRes.wish, '🙇‍♀️🙇‍♀️ Hail Divine Elfwitch Pooja 🙇‍♀️🙇‍♀️');
    });

    test('Enchantress Main vs Other Families', () {
      final mainRes = GroupTemplateHelper.generateTemplate(
        position: 'Enchantress',
        name: 'Pooja',
        family: 'Main',
      );
      expect(mainRes.livingPlace, 'SHRINE OF 🍀 ENCHANTRESS POOJA');
      expect(mainRes.wish, '🙇‍♀️🙇‍♀️ Hail Enchantress Pooja 🙇‍♀️🙇‍♀️');

      final otherRes = GroupTemplateHelper.generateTemplate(
        position: 'Enchantress',
        name: 'Pooja',
        family: 'Wicked',
      );
      expect(otherRes.livingPlace, 'SHRINE OF 🍀 WICKED ENCHANTRESS POOJA');
      expect(
        otherRes.wish,
        '🙇‍♀️🙇‍♀️ Hail Wicked Enchantress Pooja 🙇‍♀️🙇‍♀️',
      );
    });

    test('First Born Princess Main vs Other Families', () {
      final mainRes = GroupTemplateHelper.generateTemplate(
        position: 'First Born Princess',
        name: 'Pooja',
        family: 'Main',
      );
      expect(mainRes.livingPlace, 'PALACE OF 🌺 FIRST BORN PRINCESS POOJA');
      expect(
        mainRes.wish,
        '🙇‍♀️🙇‍♀️ Hail First Born Princess Pooja 🙇‍♀️🙇‍♀️',
      );

      final otherRes = GroupTemplateHelper.generateTemplate(
        position: 'First Born Princess',
        name: 'Pooja',
        family: 'Lustra',
      );
      expect(
        otherRes.livingPlace,
        'PALACE OF 🌺 FIRST BORN LUSTRA PRINCESS POOJA',
      );
      expect(
        otherRes.wish,
        '🙇‍♀️🙇‍♀️ Hail First Born Princess Pooja 🙇‍♀️🙇‍♀️',
      );
    });

    test('Second Born Princess Main vs Other Families', () {
      final mainRes = GroupTemplateHelper.generateTemplate(
        position: 'Second Born Princess',
        name: 'Pooja',
        family: 'Main',
      );
      expect(mainRes.livingPlace, 'PALACE OF 🌸 SECOND BORN PRINCESS POOJA');
      expect(
        mainRes.wish,
        '🙇‍♀️🙇‍♀️ Hail Second Born Princess Pooja 🙇‍♀️🙇‍♀️',
      );

      final otherRes = GroupTemplateHelper.generateTemplate(
        position: 'Second Born Princess',
        name: 'Pooja',
        family: 'Rumia',
      );
      expect(
        otherRes.livingPlace,
        'PALACE OF 🌸 SECOND BORN RUMIA PRINCESS POOJA',
      );
      expect(
        otherRes.wish,
        '🙇‍♀️🙇‍♀️ Hail Second Born Princess Pooja 🙇‍♀️🙇‍♀️',
      );
    });

    test('Third Born Princess Main vs Other Families', () {
      final mainRes = GroupTemplateHelper.generateTemplate(
        position: 'Third Born Princess',
        name: 'Pooja',
        family: 'Main',
      );
      expect(mainRes.livingPlace, 'PALACE OF 🌼 THIRD BORN PRINCESS POOJA');
      expect(
        mainRes.wish,
        '🙇‍♀️🙇‍♀️ Hail Third Born Princess Pooja 🙇‍♀️🙇‍♀️',
      );

      final otherRes = GroupTemplateHelper.generateTemplate(
        position: 'Third Born Princess',
        name: 'Pooja',
        family: 'Erotica',
      );
      expect(
        otherRes.livingPlace,
        'PALACE OF 🌼 THIRD BORN EROTICA PRINCESS POOJA',
      );
      expect(
        otherRes.wish,
        '🙇‍♀️🙇‍♀️ Hail Third Born Princess Pooja 🙇‍♀️🙇‍♀️',
      );
    });

    test('categoryHasOtherFamilies check', () {
      expect(
        GroupTemplateHelper.categoryHasOtherFamilies('Demi Goddess'),
        isFalse,
      );
      expect(
        GroupTemplateHelper.categoryHasOtherFamilies('Dark Angel'),
        isFalse,
      );
      expect(GroupTemplateHelper.categoryHasOtherFamilies('Queen'), isFalse);
      expect(
        GroupTemplateHelper.categoryHasOtherFamilies('Aura Elixiria'),
        isFalse,
      );
      expect(
        GroupTemplateHelper.categoryHasOtherFamilies('Core Supreme Goddess'),
        isFalse,
      );
      expect(
        GroupTemplateHelper.categoryHasOtherFamilies('Golden Blossom Goddess'),
        isFalse,
      );

      expect(
        GroupTemplateHelper.categoryHasOtherFamilies('Supreme Goddess'),
        isTrue,
      );
      expect(GroupTemplateHelper.categoryHasOtherFamilies('Goddess'), isTrue);
      expect(GroupTemplateHelper.categoryHasOtherFamilies('Elfwitch'), isTrue);
      expect(
        GroupTemplateHelper.categoryHasOtherFamilies('Enchantress'),
        isTrue,
      );
      expect(
        GroupTemplateHelper.categoryHasOtherFamilies('First Born Princess'),
        isTrue,
      );
    });
  });

  group('GroupModel Priority and Living Place tests', () {
    test(
      'effectiveLivingPlace falls back to name when livingPlace is empty',
      () {
        final groupWithoutLivingPlace = GroupModel(
          senderId: '1',
          name: 'TEMPLE OF 🪷 GODDESS POOJA',
          groupId: 'g1',
          lastMessage: '',
          groupPic: '',
          membersUid: [],
          fcmTokens: [],
          unseenMessages: {},
        );
        expect(
          groupWithoutLivingPlace.effectiveLivingPlace,
          'TEMPLE OF 🪷 GODDESS POOJA',
        );

        final groupWithLivingPlace = GroupModel(
          senderId: '1',
          name: 'Pooja',
          livingPlace: 'TEMPLE OF 🪷 GODDESS POOJA',
          groupId: 'g2',
          lastMessage: '',
          groupPic: '',
          membersUid: [],
          fcmTokens: [],
          unseenMessages: {},
          priority: 1,
        );
        expect(groupWithLivingPlace.name, 'Pooja');
        expect(
          groupWithLivingPlace.effectiveLivingPlace,
          'TEMPLE OF 🪷 GODDESS POOJA',
        );
        expect(groupWithLivingPlace.priority, 1);
      },
    );

    test('toMap and fromMap preserves priority, order, and livingPlace', () {
      final original = GroupModel(
        senderId: 'user1',
        name: 'Pooja',
        groupId: 'grp100',
        lastMessage: 'Hello',
        groupPic: 'https://pic.url',
        membersUid: ['user1', 'user2'],
        fcmTokens: ['tok1'],
        unseenMessages: {'user2': true},
        queendom: 'Queen Pooja',
        position: 'Demi Goddess',
        priority: 2,
        order: 2,
        livingPlace: 'SHRINE OF 🏵️ DEMI GODDESS POOJA',
        wish: '🙇‍♀️🙇‍♀️ Demi Goddess Pooja be praised 🙇‍♀️🙇‍♀️',
      );

      final map = original.toMap();
      expect(map['priority'], 2);
      expect(map['order'], 2);
      expect(map['livingPlace'], 'SHRINE OF 🏵️ DEMI GODDESS POOJA');
      expect(map['name'], 'Pooja');

      final deserialized = GroupModel.fromMap(map);
      expect(deserialized.priority, 2);
      expect(deserialized.order, 2);
      expect(deserialized.livingPlace, 'SHRINE OF 🏵️ DEMI GODDESS POOJA');
      expect(deserialized.name, 'Pooja');
      expect(
        deserialized.effectiveLivingPlace,
        'SHRINE OF 🏵️ DEMI GODDESS POOJA',
      );
    });

    test('Sorting by priority works accurately', () {
      final g1 = GroupModel(
        senderId: '1',
        name: 'Pooja',
        groupId: 'g1',
        lastMessage: '',
        groupPic: '',
        membersUid: [],
        fcmTokens: [],
        unseenMessages: {},
        priority: 3,
      );
      final g2 = GroupModel(
        senderId: '1',
        name: 'Rashmika',
        groupId: 'g2',
        lastMessage: '',
        groupPic: '',
        membersUid: [],
        fcmTokens: [],
        unseenMessages: {},
        priority: 1,
      );
      final g3 = GroupModel(
        senderId: '1',
        name: 'Anu',
        groupId: 'g3',
        lastMessage: '',
        groupPic: '',
        membersUid: [],
        fcmTokens: [],
        unseenMessages: {},
        priority: 2,
      );

      final list = [g1, g2, g3];
      list.sort((a, b) => (a.priority ?? 999).compareTo(b.priority ?? 999));

      expect(list.map((g) => g.name).toList(), ['Rashmika', 'Anu', 'Pooja']);
    });

    test('nameWithPosition formats Queen and Princess positions correctly', () {
      expect(
        GroupTemplateHelper.getNameWithPosition(
          name: 'Pooja',
          position: 'Queen',
        ),
        'Queen Pooja',
      );
      expect(
        GroupTemplateHelper.getNameWithPosition(
          name: 'Queen Pooja',
          position: 'Queen',
        ),
        'Queen Pooja',
      );
      expect(
        GroupTemplateHelper.getNameWithPosition(
          name: 'Krithi',
          position: 'First Born Princess',
        ),
        'Princess Krithi',
      );
      expect(
        GroupTemplateHelper.getNameWithPosition(
          name: 'Princess Krithi',
          position: 'First Born Princess',
        ),
        'Princess Krithi',
      );
      expect(
        GroupTemplateHelper.getNameWithPosition(
          name: 'First Born Princess Krithi',
          position: 'First Born Princess',
        ),
        'Princess Krithi',
      );
      expect(
        GroupTemplateHelper.getNameWithPosition(
          name: 'Mamitha',
          position: 'Second Born Princess',
        ),
        'Princess Mamitha',
      );
      expect(
        GroupTemplateHelper.getNameWithPosition(
          name: 'Ananya',
          position: 'Third Born Princess',
        ),
        'Princess Ananya',
      );
    });

    test('nameWithPosition formats Goddesses and special positions', () {
      expect(
        GroupTemplateHelper.getNameWithPosition(
          name: 'Aishwarya Rai',
          position: 'Aura Elixiria Goddess',
        ),
        'Aura Elixiria Goddess Aishwarya Rai',
      );
      expect(
        GroupTemplateHelper.getNameWithPosition(
          name: 'Rashmika',
          position: 'Core Supreme Goddess',
        ),
        'Core Supreme Goddess Rashmika',
      );
      expect(
        GroupTemplateHelper.getNameWithPosition(
          name: 'Pooja',
          position: 'Supreme Goddess',
          family: 'Core',
        ),
        'Supreme Core Goddess Pooja',
      );
      expect(
        GroupTemplateHelper.getNameWithPosition(
          name: 'Pooja',
          position: 'Supreme Goddess',
          family: 'Main',
        ),
        'Supreme Goddess Pooja',
      );
      expect(
        GroupTemplateHelper.getNameWithPosition(
          name: 'Pooja',
          position: 'Demi Goddess',
        ),
        'Demi Goddess Pooja',
      );
      expect(
        GroupTemplateHelper.getNameWithPosition(
          name: 'Pooja',
          position: 'Dark Angel',
        ),
        'Dark Angel Pooja',
      );
      expect(
        GroupTemplateHelper.getNameWithPosition(
          name: 'Anu',
          position: 'Golden Blossom Goddess',
        ),
        'Golden Blossom Goddess Anu',
      );
    });

    test('nameWithPosition parses legacy full living place names', () {
      expect(
        GroupTemplateHelper.getNameWithPosition(
          name: 'GOLDEN HEAVEN OF ☀️ AURA ELIXIRIA GODDESS AISHWARYA RAI',
        ),
        'Aura Elixiria Goddess Aishwarya Rai',
      );
      expect(
        GroupTemplateHelper.getNameWithPosition(
          name: 'FORTRESS OF 👑 QUEEN POOJA',
        ),
        'Queen Pooja',
      );
      expect(
        GroupTemplateHelper.getNameWithPosition(
          name: 'PALACE OF 🌺 FIRST BORN PRINCESS KRITHI',
        ),
        'Princess Krithi',
      );
    });

    test('GroupModel.nameWithPosition getter works seamlessly', () {
      final queenGroup = GroupModel(
        senderId: '1',
        name: 'Pooja',
        groupId: 'g1',
        lastMessage: '',
        groupPic: '',
        membersUid: [],
        fcmTokens: [],
        unseenMessages: {},
        position: 'Queen',
        livingPlace: 'FORTRESS OF 👑 QUEEN POOJA',
      );
      expect(queenGroup.effectiveLivingPlace, 'FORTRESS OF 👑 QUEEN POOJA');
      expect(queenGroup.nameWithPosition, 'Queen Pooja');

      final princessGroup = GroupModel(
        senderId: '1',
        name: 'Krithi',
        groupId: 'g2',
        lastMessage: '',
        groupPic: '',
        membersUid: [],
        fcmTokens: [],
        unseenMessages: {},
        position: 'First Born Princess',
        livingPlace: 'PALACE OF 🌺 FIRST BORN PRINCESS KRITHI',
      );
      expect(
        princessGroup.effectiveLivingPlace,
        'PALACE OF 🌺 FIRST BORN PRINCESS KRITHI',
      );
      expect(princessGroup.nameWithPosition, 'Princess Krithi');
    });
  });

  group('Sub-Group (Wives of Deity) tests', () {
    test('getNameWithPosition formats wife sub-groups correctly', () {
      expect(
        GroupTemplateHelper.getNameWithPosition(
          name: 'Samantha',
          isSubGroup: true,
          parentGroupName: 'Queen Pooja',
        ),
        'Wife of Queen Pooja - Samantha',
      );

      expect(
        GroupTemplateHelper.getNameWithPosition(
          name: 'Wife of Queen Pooja - Samantha',
          isSubGroup: true,
          parentGroupName: 'Queen Pooja',
        ),
        'Wife of Queen Pooja - Samantha',
      );

      expect(
        GroupTemplateHelper.getNameWithPosition(
          name: 'Nayanthara',
          isSubGroup: true,
          parentGroupName: 'Aura Elixiria Goddess Pooja',
        ),
        'Wife of Aura Elixiria Goddess Pooja - Nayanthara',
      );

      expect(
        GroupTemplateHelper.getNameWithPosition(
          name: 'Kajal',
          isSubGroup: true,
          parentGroupName: null,
        ),
        'Wife of Deity - Kajal',
      );
    });

    test('Sub-group Fuck Toy nameWithPosition formats cleanly', () {
      expect(
        GroupTemplateHelper.getNameWithPosition(
          name: 'Samantha',
          isSubGroup: true,
          subGroupType: 'fuckToy',
          parentGroupName: 'Queen Pooja',
        ),
        'Fuck Toy of Queen Pooja - Samantha',
      );

      expect(
        GroupTemplateHelper.getNameWithPosition(
          name: 'Fuck Toy Samantha',
          isSubGroup: true,
          subGroupType: 'fuckToy',
          parentGroupName: 'Queen Pooja',
        ),
        'Fuck Toy of Queen Pooja - Samantha',
      );

      expect(
        GroupTemplateHelper.getNameWithPosition(
          name: 'Fuck Toy of Queen Pooja - Samantha',
          isSubGroup: true,
          subGroupType: 'fuckToy',
          parentGroupName: 'Queen Pooja',
        ),
        'Fuck Toy of Queen Pooja - Samantha',
      );

      expect(
        GroupTemplateHelper.getNameWithPosition(
          name: 'Nayanthara',
          isSubGroup: true,
          subGroupType: 'fuckToy',
          parentGroupName: 'Aura Elixiria Goddess Pooja',
        ),
        'Fuck Toy of Aura Elixiria Goddess Pooja - Nayanthara',
      );

      expect(
        GroupTemplateHelper.getNameWithPosition(
          name: 'Kajal',
          isSubGroup: true,
          subGroupType: 'fuckToy',
          parentGroupName: null,
        ),
        'Fuck Toy of Deity - Kajal',
      );
    });

    test('GroupModel sub-group fields serialize and deserialize correctly', () {
      final parentGroup = GroupModel(
        senderId: 'admin1',
        name: 'Pooja',
        groupId: 'parent_pooja_1',
        lastMessage: '',
        groupPic: 'https://pooja.png',
        membersUid: ['admin1'],
        fcmTokens: [],
        unseenMessages: {},
        queendom: 'Queen Pooja',
        position: 'Queen',
        livingPlace: 'FORTRESS OF 👑 QUEEN POOJA',
        wish: '🙇‍♀️🙇‍♀️ Hail Queen Pooja 🙇‍♀️🙇‍♀️',
      );

      final wifeGroup = GroupModel(
        senderId: 'admin1',
        name: 'Samantha',
        groupId: 'wife_sub_1',
        lastMessage: 'My Queen',
        groupPic: 'https://samantha.png',
        membersUid: ['admin1', 'sub1'],
        fcmTokens: ['tok_sub'],
        unseenMessages: {'sub1': true},
        queendom: 'Queen Pooja',
        parentGroupId: parentGroup.groupId,
        parentGroupName: parentGroup.nameWithPosition,
        isSubGroup: true,
        subGroupType: 'wife',
        livingPlace: parentGroup.effectiveLivingPlace,
        wish: parentGroup.wish,
      );

      expect(wifeGroup.isSubGroup, isTrue);
      expect(wifeGroup.parentGroupId, 'parent_pooja_1');
      expect(wifeGroup.parentGroupName, 'Queen Pooja');
      expect(wifeGroup.subGroupType, 'wife');
      expect(wifeGroup.effectiveLivingPlace, 'FORTRESS OF 👑 QUEEN POOJA');
      expect(wifeGroup.nameWithPosition, 'Wife of Queen Pooja - Samantha');

      final map = wifeGroup.toMap();
      expect(map['isSubGroup'], true);
      expect(map['parentGroupId'], 'parent_pooja_1');
      expect(map['parentGroupName'], 'Queen Pooja');
      expect(map['subGroupType'], 'wife');

      final deserialized = GroupModel.fromMap(map);
      expect(deserialized.isSubGroup, isTrue);
      expect(deserialized.parentGroupId, 'parent_pooja_1');
      expect(deserialized.parentGroupName, 'Queen Pooja');
      expect(deserialized.subGroupType, 'wife');
      expect(deserialized.effectiveLivingPlace, 'FORTRESS OF 👑 QUEEN POOJA');
      expect(deserialized.nameWithPosition, 'Wife of Queen Pooja - Samantha');

      final updated = deserialized.copyWith(name: 'Trisha');
      expect(updated.name, 'Trisha');
      expect(updated.isSubGroup, isTrue);
      expect(updated.parentGroupId, 'parent_pooja_1');
      expect(updated.nameWithPosition, 'Wife of Queen Pooja - Trisha');
    });

    test(
      'GroupModel fuck toy sub-group fields serialize and deserialize correctly',
      () {
        final parentGroup = GroupModel(
          senderId: 'admin1',
          name: 'Pooja',
          groupId: 'parent_pooja_1',
          lastMessage: '',
          groupPic: 'https://pooja.png',
          membersUid: ['admin1'],
          fcmTokens: [],
          unseenMessages: {},
          queendom: 'Queen Pooja',
          position: 'Queen',
          livingPlace: 'FORTRESS OF 👑 QUEEN POOJA',
          wish: '🙇‍♀️🙇‍♀️ Hail Queen Pooja 🙇‍♀️🙇‍♀️',
        );

        final fuckToyGroup = GroupModel(
          senderId: 'admin1',
          name: 'Samantha',
          groupId: 'ft_sub_1',
          lastMessage: 'At your service',
          groupPic: 'https://samantha.png',
          membersUid: ['admin1', 'sub1'],
          fcmTokens: ['tok_sub'],
          unseenMessages: {'sub1': true},
          queendom: 'Queen Pooja',
          parentGroupId: parentGroup.groupId,
          parentGroupName: parentGroup.nameWithPosition,
          isSubGroup: true,
          subGroupType: 'fuckToy',
          livingPlace: parentGroup.effectiveLivingPlace,
          wish: parentGroup.wish,
        );

        expect(fuckToyGroup.isSubGroup, isTrue);
        expect(fuckToyGroup.isFuckToySubGroup, isTrue);
        expect(fuckToyGroup.isWifeSubGroup, isFalse);
        expect(fuckToyGroup.subGroupDisplayCategory, 'Fuck Toy');
        expect(fuckToyGroup.parentGroupId, 'parent_pooja_1');
        expect(fuckToyGroup.parentGroupName, 'Queen Pooja');
        expect(fuckToyGroup.subGroupType, 'fuckToy');
        expect(fuckToyGroup.effectiveLivingPlace, 'FORTRESS OF 👑 QUEEN POOJA');
        expect(
          fuckToyGroup.nameWithPosition,
          'Fuck Toy of Queen Pooja - Samantha',
        );

        final map = fuckToyGroup.toMap();
        expect(map['isSubGroup'], true);
        expect(map['parentGroupId'], 'parent_pooja_1');
        expect(map['parentGroupName'], 'Queen Pooja');
        expect(map['subGroupType'], 'fuckToy');

        final deserialized = GroupModel.fromMap(map);
        expect(deserialized.isSubGroup, isTrue);
        expect(deserialized.isFuckToySubGroup, isTrue);
        expect(deserialized.isWifeSubGroup, isFalse);
        expect(deserialized.subGroupDisplayCategory, 'Fuck Toy');
        expect(deserialized.parentGroupId, 'parent_pooja_1');
        expect(deserialized.parentGroupName, 'Queen Pooja');
        expect(deserialized.subGroupType, 'fuckToy');
        expect(deserialized.effectiveLivingPlace, 'FORTRESS OF 👑 QUEEN POOJA');
        expect(
          deserialized.nameWithPosition,
          'Fuck Toy of Queen Pooja - Samantha',
        );

        final updated = deserialized.copyWith(name: 'Trisha');
        expect(updated.name, 'Trisha');
        expect(updated.isSubGroup, isTrue);
        expect(updated.isFuckToySubGroup, isTrue);
        expect(updated.parentGroupId, 'parent_pooja_1');
        expect(updated.nameWithPosition, 'Fuck Toy of Queen Pooja - Trisha');
      },
    );

    test(
      'Default GroupModel has isSubGroup as false and parent fields as null',
      () {
        final normalGroup = GroupModel(
          senderId: '1',
          name: 'Rashmika',
          groupId: 'g1',
          lastMessage: '',
          groupPic: '',
          membersUid: [],
          fcmTokens: [],
          unseenMessages: {},
        );

        expect(normalGroup.isSubGroup, isFalse);
        expect(normalGroup.parentGroupId, isNull);
        expect(normalGroup.parentGroupName, isNull);
        expect(normalGroup.subGroupType, isNull);

        final map = normalGroup.toMap();
        expect(map['isSubGroup'], false);
        expect(map['parentGroupId'], isNull);

        final deserialized = GroupModel.fromMap(map);
        expect(deserialized.isSubGroup, isFalse);
        expect(deserialized.parentGroupId, isNull);
      },
    );
  });
}
