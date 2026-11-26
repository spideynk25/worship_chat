import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:worship_chat/colors.dart';

class ReactionEmojiEntry {
  final String emoji;
  final String keywords;

  const ReactionEmojiEntry(this.emoji, this.keywords);
}

class ReactionEmojiCategory {
  final String id;
  final String title;
  final IconData icon;
  final List<ReactionEmojiEntry> entries;

  const ReactionEmojiCategory({
    required this.id,
    required this.title,
    required this.icon,
    required this.entries,
  });
}

/// Manages persistent recent reaction emojis and extracts arbitrary OS keyboard
/// emoji inputs so users can react with any Unicode emoji.
class ReactionEmojiCatalog {
  ReactionEmojiCatalog._();

  static const String recentPrefsKey = 'reaction_recent_emojis_v1';
  static const int maxRecent = 24;

  static const List<String> defaultRecents = [
    '👍',
    '❤️',
    '😂',
    '😮',
    '😢',
    '🙏',
    '🔥',
    '👑',
    '💯',
    '✨',
    '😍',
    '🥰',
    '👏',
    '🙌',
    '🎉',
    '💔',
  ];

  static final RegExp _emojiCodePointRegex = RegExp(
    r'[\u{1F000}-\u{1FAFF}\u{2600}-\u{27BF}\u{2300}-\u{23FF}\u{2B50}\u{2B55}\u{203C}\u{2049}\u{3030}\u{303D}\u{3297}\u{3299}]|\uFE0F|\u200D',
    unicode: true,
  );
  static final RegExp _alphaNumericRegex = RegExp(r'[a-zA-Z0-9]');

  /// If [input] is an emoji entered from the OS keyboard rather than a search
  /// keyword, returns the trimmed emoji string; otherwise returns `null`.
  static String? extractDirectEmojiInput(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return null;
    if (_alphaNumericRegex.hasMatch(trimmed)) return null;
    if (!_emojiCodePointRegex.hasMatch(trimmed)) return null;
    return trimmed;
  }

  static Future<List<String>> loadRecents() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getStringList(recentPrefsKey);
      if (stored != null && stored.isNotEmpty) {
        return stored;
      }
    } catch (_) {}
    return List<String>.from(defaultRecents);
  }

  static Future<void> recordRecent(String emoji) async {
    final clean = emoji.trim();
    if (clean.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final current =
          prefs.getStringList(recentPrefsKey) ?? List<String>.from(defaultRecents);
      final updated = <String>[
        clean,
        ...current.where((e) => e != clean),
      ];
      if (updated.length > maxRecent) {
        updated.removeRange(maxRecent, updated.length);
      }
      await prefs.setStringList(recentPrefsKey, updated);
    } catch (_) {}
  }

  static List<ReactionEmojiEntry> search(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return const [];
    final seen = <String>{};
    final matches = <ReactionEmojiEntry>[];
    for (final cat in categories) {
      for (final entry in cat.entries) {
        if (seen.contains(entry.emoji)) continue;
        if (entry.emoji == q || entry.keywords.toLowerCase().contains(q)) {
          seen.add(entry.emoji);
          matches.add(entry);
        }
      }
    }
    return matches;
  }

  static const List<ReactionEmojiCategory> categories = [
    ReactionEmojiCategory(
      id: 'smileys',
      title: 'Smileys',
      icon: Icons.emoji_emotions_outlined,
      entries: [
        ReactionEmojiEntry('😀', 'grinning smile happy'),
        ReactionEmojiEntry('😃', 'smiley happy grin'),
        ReactionEmojiEntry('😄', 'smile happy eyes laugh'),
        ReactionEmojiEntry('😁', 'beaming grin teeth'),
        ReactionEmojiEntry('😆', 'laugh squinting lol'),
        ReactionEmojiEntry('😅', 'sweat smile nervous relief'),
        ReactionEmojiEntry('🤣', 'rofl rolling laugh funny'),
        ReactionEmojiEntry('😂', 'joy tears laugh crying lol'),
        ReactionEmojiEntry('🙂', 'slightly smiling'),
        ReactionEmojiEntry('🙃', 'upside down silly'),
        ReactionEmojiEntry('😉', 'wink flirt'),
        ReactionEmojiEntry('😊', 'blush happy warm'),
        ReactionEmojiEntry('😇', 'angel halo innocent blessed'),
        ReactionEmojiEntry('🥰', 'smiling hearts adore love'),
        ReactionEmojiEntry('😍', 'heart eyes crush love'),
        ReactionEmojiEntry('🤩', 'star struck excited wow'),
        ReactionEmojiEntry('😘', 'kiss blow love muah'),
        ReactionEmojiEntry('😗', 'kissing'),
        ReactionEmojiEntry('☺️', 'relaxed blush'),
        ReactionEmojiEntry('😚', 'kissing closed eyes'),
        ReactionEmojiEntry('😙', 'kissing smiling'),
        ReactionEmojiEntry('🥲', 'smiling tear proud sad'),
        ReactionEmojiEntry('😋', 'yum delicious tongue'),
        ReactionEmojiEntry('😛', 'tongue playful'),
        ReactionEmojiEntry('😜', 'wink tongue crazy'),
        ReactionEmojiEntry('🤪', 'zany goofy wild'),
        ReactionEmojiEntry('😝', 'squinting tongue'),
        ReactionEmojiEntry('🤑', 'money rich cash dollar'),
        ReactionEmojiEntry('🤗', 'hugging hug warm'),
        ReactionEmojiEntry('🤭', 'hand over mouth giggle'),
        ReactionEmojiEntry('🫢', 'gasp shock'),
        ReactionEmojiEntry('🫣', 'peeking shy'),
        ReactionEmojiEntry('🤫', 'shh quiet secret'),
        ReactionEmojiEntry('🤔', 'thinking hmm ponder'),
        ReactionEmojiEntry('🫡', 'salute respect yes sir'),
        ReactionEmojiEntry('🤐', 'zipper mouth quiet'),
        ReactionEmojiEntry('🤨', 'raised eyebrow doubt sus'),
        ReactionEmojiEntry('😐', 'neutral straight'),
        ReactionEmojiEntry('😑', 'expressionless blank'),
        ReactionEmojiEntry('😶', 'no mouth silent'),
        ReactionEmojiEntry('🫥', 'dotted invisible shy'),
        ReactionEmojiEntry('😏', 'smirk sly'),
        ReactionEmojiEntry('😒', 'unamused annoyed meh'),
        ReactionEmojiEntry('🙄', 'eye roll whatever'),
        ReactionEmojiEntry('😬', 'grimace awkward cringe'),
        ReactionEmojiEntry('😮‍💨', 'exhale sigh relief'),
        ReactionEmojiEntry('🤥', 'lying pinocchio'),
        ReactionEmojiEntry('😌', 'relieved calm peaceful'),
        ReactionEmojiEntry('😔', 'pensive sad down'),
        ReactionEmojiEntry('😪', 'sleepy tear'),
        ReactionEmojiEntry('🤤', 'drooling crave hungry'),
        ReactionEmojiEntry('😴', 'sleeping zzz tired'),
        ReactionEmojiEntry('😷', 'mask sick'),
        ReactionEmojiEntry('🤒', 'thermometer fever sick'),
        ReactionEmojiEntry('🤕', 'bandage hurt'),
        ReactionEmojiEntry('🤢', 'nauseated sick gross'),
        ReactionEmojiEntry('🤮', 'vomiting sick'),
        ReactionEmojiEntry('🤧', 'sneezing cold'),
        ReactionEmojiEntry('🥵', 'hot sweating spicy'),
        ReactionEmojiEntry('🥶', 'cold freezing'),
        ReactionEmojiEntry('🥴', 'woozy dizzy drunk'),
        ReactionEmojiEntry('😵', 'dizzy knocked out'),
        ReactionEmojiEntry('🤯', 'mind blown shocked'),
        ReactionEmojiEntry('🤠', 'cowboy hat'),
        ReactionEmojiEntry('🥳', 'party celebrate birthday'),
        ReactionEmojiEntry('🥸', 'disguise glasses'),
        ReactionEmojiEntry('😎', 'cool sunglasses swag'),
        ReactionEmojiEntry('🤓', 'nerd glasses geek'),
        ReactionEmojiEntry('🧐', 'monocle inspect'),
        ReactionEmojiEntry('😕', 'confused'),
        ReactionEmojiEntry('🫤', 'diagonal mouth unsure'),
        ReactionEmojiEntry('😟', 'worried concern'),
        ReactionEmojiEntry('🙁', 'frowning sad'),
        ReactionEmojiEntry('☹️', 'frown'),
        ReactionEmojiEntry('😮', 'open mouth wow surprised'),
        ReactionEmojiEntry('😯', 'hushed surprised'),
        ReactionEmojiEntry('😲', 'astonished shocked'),
        ReactionEmojiEntry('😳', 'flushed embarrassed shy'),
        ReactionEmojiEntry('🥺', 'pleading puppy eyes'),
        ReactionEmojiEntry('🥹', 'holding back tears touched'),
        ReactionEmojiEntry('😦', 'frowning open mouth'),
        ReactionEmojiEntry('😧', 'anguished'),
        ReactionEmojiEntry('😨', 'fearful scared'),
        ReactionEmojiEntry('😰', 'anxious sweat'),
        ReactionEmojiEntry('😥', 'sad relieved sweat'),
        ReactionEmojiEntry('😢', 'cry tear sad'),
        ReactionEmojiEntry('😭', 'loudly crying sobbing sad'),
        ReactionEmojiEntry('😱', 'scream fear omg'),
        ReactionEmojiEntry('😖', 'confounded'),
        ReactionEmojiEntry('😣', 'persevere struggle'),
        ReactionEmojiEntry('😞', 'disappointed'),
        ReactionEmojiEntry('😓', 'downcast sweat'),
        ReactionEmojiEntry('😩', 'weary tired'),
        ReactionEmojiEntry('😫', 'tired frustrated'),
        ReactionEmojiEntry('🥱', 'yawning bored sleepy'),
        ReactionEmojiEntry('😤', 'triumph hmph mad'),
        ReactionEmojiEntry('😡', 'enraged pouting angry red'),
        ReactionEmojiEntry('😠', 'angry mad'),
        ReactionEmojiEntry('🤬', 'cursing swearing mad'),
        ReactionEmojiEntry('😈', 'smiling horns devil mischief'),
        ReactionEmojiEntry('👿', 'angry horns devil'),
        ReactionEmojiEntry('💀', 'skull dead lmao'),
        ReactionEmojiEntry('☠️', 'skull crossbones'),
        ReactionEmojiEntry('🤡', 'clown funny'),
        ReactionEmojiEntry('👻', 'ghost boo spooky'),
        ReactionEmojiEntry('👽', 'alien space'),
        ReactionEmojiEntry('🤖', 'robot'),
      ],
    ),
    ReactionEmojiCategory(
      id: 'love',
      title: 'Love',
      icon: Icons.favorite_border_rounded,
      entries: [
        ReactionEmojiEntry('❤️', 'red heart love'),
        ReactionEmojiEntry('🩷', 'pink heart love cute'),
        ReactionEmojiEntry('🧡', 'orange heart'),
        ReactionEmojiEntry('💛', 'yellow heart gold'),
        ReactionEmojiEntry('💚', 'green heart'),
        ReactionEmojiEntry('💙', 'blue heart'),
        ReactionEmojiEntry('💜', 'purple heart royal'),
        ReactionEmojiEntry('🖤', 'black heart dark'),
        ReactionEmojiEntry('🩶', 'grey heart silver'),
        ReactionEmojiEntry('🤍', 'white heart pure'),
        ReactionEmojiEntry('🤎', 'brown heart'),
        ReactionEmojiEntry('💔', 'broken heart heartbreak'),
        ReactionEmojiEntry('❤️‍🔥', 'heart on fire passion'),
        ReactionEmojiEntry('❤️‍🩹', 'mending heart heal'),
        ReactionEmojiEntry('❣️', 'heart exclamation'),
        ReactionEmojiEntry('💕', 'two hearts love'),
        ReactionEmojiEntry('💞', 'revolving hearts'),
        ReactionEmojiEntry('💓', 'beating heart pulse'),
        ReactionEmojiEntry('💗', 'growing heart pink'),
        ReactionEmojiEntry('💖', 'sparkling heart love'),
        ReactionEmojiEntry('💘', 'cupid arrow heart'),
        ReactionEmojiEntry('💝', 'heart ribbon gift'),
        ReactionEmojiEntry('💟', 'heart decoration'),
        ReactionEmojiEntry('💌', 'love letter'),
        ReactionEmojiEntry('💋', 'kiss mark lips'),
        ReactionEmojiEntry('🫶', 'heart hands love'),
        ReactionEmojiEntry('🫂', 'people hugging embrace'),
        ReactionEmojiEntry('🌹', 'rose flower love'),
        ReactionEmojiEntry('🥀', 'wilted rose'),
        ReactionEmojiEntry('💐', 'bouquet flowers'),
        ReactionEmojiEntry('💍', 'ring wedding diamond'),
        ReactionEmojiEntry('💎', 'gem diamond jewel'),
        ReactionEmojiEntry('🎀', 'ribbon bow'),
        ReactionEmojiEntry('💑', 'couple heart'),
        ReactionEmojiEntry('💏', 'kiss couple'),
      ],
    ),
    ReactionEmojiCategory(
      id: 'gestures',
      title: 'People',
      icon: Icons.pan_tool_alt_outlined,
      entries: [
        ReactionEmojiEntry('👍', 'thumbs up yes good like'),
        ReactionEmojiEntry('👎', 'thumbs down bad no'),
        ReactionEmojiEntry('👏', 'clap applause bravo'),
        ReactionEmojiEntry('🙌', 'raising hands praise hooray'),
        ReactionEmojiEntry('👐', 'open hands'),
        ReactionEmojiEntry('🤲', 'palms up prayer'),
        ReactionEmojiEntry('🤝', 'handshake deal agree'),
        ReactionEmojiEntry('🙏', 'pray bow please thank you worship'),
        ReactionEmojiEntry('✍️', 'writing hand'),
        ReactionEmojiEntry('💅', 'nail polish queen slay'),
        ReactionEmojiEntry('🤳', 'selfie'),
        ReactionEmojiEntry('💪', 'muscle strong flex'),
        ReactionEmojiEntry('👌', 'ok hand perfect'),
        ReactionEmojiEntry('🤌', 'pinched fingers chef kiss'),
        ReactionEmojiEntry('🤏', 'pinching tiny small'),
        ReactionEmojiEntry('✌️', 'peace victory two'),
        ReactionEmojiEntry('🤞', 'crossed fingers luck'),
        ReactionEmojiEntry('🫰', 'finger heart snap'),
        ReactionEmojiEntry('🤟', 'love you hand'),
        ReactionEmojiEntry('🤘', 'rock on horns'),
        ReactionEmojiEntry('🤙', 'call me shaka'),
        ReactionEmojiEntry('👋', 'wave hello bye'),
        ReactionEmojiEntry('🤚', 'raised back hand'),
        ReactionEmojiEntry('🖐️', 'hand splayed five'),
        ReactionEmojiEntry('✋', 'raised hand stop'),
        ReactionEmojiEntry('🖖', 'vulcan salute'),
        ReactionEmojiEntry('👈', 'point left'),
        ReactionEmojiEntry('👉', 'point right'),
        ReactionEmojiEntry('👆', 'point up'),
        ReactionEmojiEntry('👇', 'point down'),
        ReactionEmojiEntry('☝️', 'index up first'),
        ReactionEmojiEntry('🫵', 'pointing at you'),
        ReactionEmojiEntry('🙇', 'bow respect worship sorry'),
        ReactionEmojiEntry('🙇‍♀️', 'woman bowing respect'),
        ReactionEmojiEntry('🙇‍♂️', 'man bowing respect'),
        ReactionEmojiEntry('👸', 'princess queen crown royal'),
        ReactionEmojiEntry('🤴', 'prince king crown royal'),
        ReactionEmojiEntry('👰', 'bride queen wedding'),
        ReactionEmojiEntry('💃', 'woman dancing party'),
        ReactionEmojiEntry('🕺', 'man dancing party'),
        ReactionEmojiEntry('🤦', 'facepalm oh no'),
        ReactionEmojiEntry('🤷', 'shrug idk'),
        ReactionEmojiEntry('👀', 'eyes look see watching'),
        ReactionEmojiEntry('👁️', 'eye'),
        ReactionEmojiEntry('🧠', 'brain smart'),
      ],
    ),
    ReactionEmojiCategory(
      id: 'royal',
      title: 'Royal & Party',
      icon: Icons.workspace_premium_outlined,
      entries: [
        ReactionEmojiEntry('👑', 'crown queen king royal majesty'),
        ReactionEmojiEntry('🔥', 'fire flame lit hot'),
        ReactionEmojiEntry('✨', 'sparkles magic shine stars'),
        ReactionEmojiEntry('🌟', 'glowing star shine'),
        ReactionEmojiEntry('⭐', 'star'),
        ReactionEmojiEntry('💫', 'dizzy star shooting'),
        ReactionEmojiEntry('⚡', 'lightning bolt electric'),
        ReactionEmojiEntry('💥', 'boom collision bang'),
        ReactionEmojiEntry('💯', 'hundred 100 perfect'),
        ReactionEmojiEntry('🏆', 'trophy win champion award'),
        ReactionEmojiEntry('🥇', 'first gold medal'),
        ReactionEmojiEntry('🥈', 'second silver medal'),
        ReactionEmojiEntry('🥉', 'third bronze medal'),
        ReactionEmojiEntry('🏅', 'medal'),
        ReactionEmojiEntry('🎉', 'party popper congrats celebrate'),
        ReactionEmojiEntry('🎊', 'confetti ball'),
        ReactionEmojiEntry('🎈', 'balloon party'),
        ReactionEmojiEntry('🎁', 'gift present'),
        ReactionEmojiEntry('🕯️', 'candle light'),
        ReactionEmojiEntry('🪔', 'diya lamp light'),
        ReactionEmojiEntry('✝️', 'cross christian faith worship'),
        ReactionEmojiEntry('🕊️', 'dove peace holy spirit bird'),
        ReactionEmojiEntry('⛪', 'church worship'),
        ReactionEmojiEntry('📿', 'prayer beads'),
        ReactionEmojiEntry('🔮', 'crystal ball magic'),
        ReactionEmojiEntry('🧿', 'evil eye charm'),
        ReactionEmojiEntry('🪄', 'magic wand'),
        ReactionEmojiEntry('👠', 'high heel shoe queen'),
        ReactionEmojiEntry('💄', 'lipstick glam'),
        ReactionEmojiEntry('👗', 'dress gown'),
        ReactionEmojiEntry('👜', 'handbag purse'),
        ReactionEmojiEntry('💍', 'ring jewel'),
        ReactionEmojiEntry('💎', 'diamond gem'),
        ReactionEmojiEntry('🎭', 'masks drama'),
        ReactionEmojiEntry('🎯', 'bullseye target'),
      ],
    ),
    ReactionEmojiCategory(
      id: 'nature',
      title: 'Nature',
      icon: Icons.eco_outlined,
      entries: [
        ReactionEmojiEntry('🌸', 'cherry blossom flower spring'),
        ReactionEmojiEntry('🌺', 'hibiscus flower'),
        ReactionEmojiEntry('🌻', 'sunflower'),
        ReactionEmojiEntry('🌼', 'blossom daisy'),
        ReactionEmojiEntry('🌷', 'tulip flower'),
        ReactionEmojiEntry('🪷', 'lotus flower calm'),
        ReactionEmojiEntry('🪻', 'hyacinth lavender flower'),
        ReactionEmojiEntry('🌱', 'seedling plant'),
        ReactionEmojiEntry('🌿', 'herb leaf'),
        ReactionEmojiEntry('🍀', 'four leaf clover luck'),
        ReactionEmojiEntry('🍁', 'maple leaf autumn'),
        ReactionEmojiEntry('🍃', 'leaf wind'),
        ReactionEmojiEntry('🌍', 'earth globe world'),
        ReactionEmojiEntry('🌞', 'sun face bright'),
        ReactionEmojiEntry('☀️', 'sun sunny bright'),
        ReactionEmojiEntry('🌙', 'crescent moon night'),
        ReactionEmojiEntry('🌕', 'full moon'),
        ReactionEmojiEntry('🌈', 'rainbow colors'),
        ReactionEmojiEntry('☁️', 'cloud'),
        ReactionEmojiEntry('🌧️', 'rain weather'),
        ReactionEmojiEntry('❄️', 'snowflake winter cold'),
        ReactionEmojiEntry('🌊', 'ocean wave water'),
        ReactionEmojiEntry('💧', 'water droplet tear'),
        ReactionEmojiEntry('🦋', 'butterfly nature'),
        ReactionEmojiEntry('🐝', 'bee honey'),
        ReactionEmojiEntry('🐞', 'ladybug'),
        ReactionEmojiEntry('🦢', 'swan graceful'),
        ReactionEmojiEntry('🦚', 'peacock'),
        ReactionEmojiEntry('🦅', 'eagle'),
        ReactionEmojiEntry('🦉', 'owl wise'),
        ReactionEmojiEntry('🦁', 'lion king brave'),
        ReactionEmojiEntry('🐯', 'tiger'),
        ReactionEmojiEntry('🐱', 'cat kitty'),
        ReactionEmojiEntry('🐶', 'dog puppy cute'),
        ReactionEmojiEntry('🐺', 'wolf'),
        ReactionEmojiEntry('🦊', 'fox'),
        ReactionEmojiEntry('🐻', 'bear'),
        ReactionEmojiEntry('🐼', 'panda'),
        ReactionEmojiEntry('🐰', 'bunny rabbit'),
        ReactionEmojiEntry('🦄', 'unicorn magic'),
        ReactionEmojiEntry('🐬', 'dolphin'),
        ReactionEmojiEntry('🐉', 'dragon'),
      ],
    ),
    ReactionEmojiCategory(
      id: 'food',
      title: 'Food',
      icon: Icons.local_cafe_outlined,
      entries: [
        ReactionEmojiEntry('🍇', 'grapes fruit'),
        ReactionEmojiEntry('🍉', 'watermelon'),
        ReactionEmojiEntry('🍊', 'orange tangerine'),
        ReactionEmojiEntry('🍋', 'lemon'),
        ReactionEmojiEntry('🍌', 'banana'),
        ReactionEmojiEntry('🍍', 'pineapple'),
        ReactionEmojiEntry('🥭', 'mango'),
        ReactionEmojiEntry('🍎', 'red apple'),
        ReactionEmojiEntry('🍑', 'peach'),
        ReactionEmojiEntry('🍒', 'cherries'),
        ReactionEmojiEntry('🍓', 'strawberry'),
        ReactionEmojiEntry('🥑', 'avocado'),
        ReactionEmojiEntry('🍕', 'pizza'),
        ReactionEmojiEntry('🍔', 'burger'),
        ReactionEmojiEntry('🍟', 'fries'),
        ReactionEmojiEntry('🌮', 'taco'),
        ReactionEmojiEntry('🍿', 'popcorn movie'),
        ReactionEmojiEntry('🧁', 'cupcake sweet'),
        ReactionEmojiEntry('🍰', 'cake slice dessert'),
        ReactionEmojiEntry('🎂', 'birthday cake celebrate'),
        ReactionEmojiEntry('🍫', 'chocolate candy'),
        ReactionEmojiEntry('🍩', 'donut sweet'),
        ReactionEmojiEntry('🍪', 'cookie'),
        ReactionEmojiEntry('🍯', 'honey sweet'),
        ReactionEmojiEntry('🍦', 'ice cream'),
        ReactionEmojiEntry('☕', 'coffee hot tea'),
        ReactionEmojiEntry('🍵', 'tea matcha'),
        ReactionEmojiEntry('🧋', 'boba bubble tea'),
        ReactionEmojiEntry('🍷', 'wine glass'),
        ReactionEmojiEntry('🥂', 'cheers champagne toast'),
        ReactionEmojiEntry('🍻', 'beers cheers'),
        ReactionEmojiEntry('🍾', 'champagne celebrate'),
      ],
    ),
    ReactionEmojiCategory(
      id: 'objects',
      title: 'Objects',
      icon: Icons.music_note_outlined,
      entries: [
        ReactionEmojiEntry('🎵', 'music note song'),
        ReactionEmojiEntry('🎶', 'music notes melody'),
        ReactionEmojiEntry('🎤', 'mic microphone sing'),
        ReactionEmojiEntry('🎧', 'headphones music audio'),
        ReactionEmojiEntry('🎸', 'guitar music'),
        ReactionEmojiEntry('🎹', 'piano music'),
        ReactionEmojiEntry('🥁', 'drum beat'),
        ReactionEmojiEntry('⚽', 'soccer football'),
        ReactionEmojiEntry('🏀', 'basketball'),
        ReactionEmojiEntry('🏏', 'cricket bat'),
        ReactionEmojiEntry('🎮', 'game controller gaming'),
        ReactionEmojiEntry('🎲', 'dice luck'),
        ReactionEmojiEntry('📸', 'camera flash photo'),
        ReactionEmojiEntry('🎬', 'clapperboard movie video'),
        ReactionEmojiEntry('🎨', 'art palette paint'),
        ReactionEmojiEntry('📱', 'phone mobile'),
        ReactionEmojiEntry('💻', 'laptop computer'),
        ReactionEmojiEntry('💡', 'lightbulb idea bright'),
        ReactionEmojiEntry('🔑', 'key unlock'),
        ReactionEmojiEntry('🔒', 'lock secure'),
        ReactionEmojiEntry('📌', 'pin pushpin'),
        ReactionEmojiEntry('📍', 'location pin'),
        ReactionEmojiEntry('✉️', 'envelope mail message'),
        ReactionEmojiEntry('📖', 'open book bible read'),
        ReactionEmojiEntry('💰', 'money bag rich'),
        ReactionEmojiEntry('💸', 'money wings'),
        ReactionEmojiEntry('✈️', 'airplane travel fly'),
        ReactionEmojiEntry('🚀', 'rocket launch moon'),
        ReactionEmojiEntry('🏰', 'castle palace kingdom'),
        ReactionEmojiEntry('🏠', 'house home'),
      ],
    ),
    ReactionEmojiCategory(
      id: 'symbols',
      title: 'Symbols',
      icon: Icons.emoji_symbols_outlined,
      entries: [
        ReactionEmojiEntry('✅', 'check green ok done yes'),
        ReactionEmojiEntry('❌', 'cross no wrong cancel'),
        ReactionEmojiEntry('❓', 'question mark what'),
        ReactionEmojiEntry('❗', 'exclamation alert important'),
        ReactionEmojiEntry('‼️', 'double exclamation'),
        ReactionEmojiEntry('⁉️', 'exclamation question'),
        ReactionEmojiEntry('💬', 'speech bubble chat talk'),
        ReactionEmojiEntry('💭', 'thought bubble'),
        ReactionEmojiEntry('💤', 'zzz sleep'),
        ReactionEmojiEntry('🔔', 'bell notification alert'),
        ReactionEmojiEntry('🔕', 'mute bell'),
        ReactionEmojiEntry('♻️', 'recycle'),
        ReactionEmojiEntry('⚜️', 'fleur de lis royal'),
        ReactionEmojiEntry('🔱', 'trident'),
        ReactionEmojiEntry('♾️', 'infinity forever'),
        ReactionEmojiEntry('⚠️', 'warning alert'),
        ReactionEmojiEntry('🚫', 'prohibited no ban'),
        ReactionEmojiEntry('🇮🇳', 'india flag'),
        ReactionEmojiEntry('🇺🇸', 'usa united states america flag'),
        ReactionEmojiEntry('🇬🇧', 'uk britain flag'),
        ReactionEmojiEntry('🇨🇦', 'canada flag'),
        ReactionEmojiEntry('🇦🇺', 'australia flag'),
        ReactionEmojiEntry('🇦🇪', 'uae dubai flag'),
        ReactionEmojiEntry('🇸🇬', 'singapore flag'),
        ReactionEmojiEntry('🇫🇷', 'france flag'),
        ReactionEmojiEntry('🇩🇪', 'germany flag'),
        ReactionEmojiEntry('🇯🇵', 'japan flag'),
        ReactionEmojiEntry('🇰🇷', 'korea flag'),
        ReactionEmojiEntry('🇧🇷', 'brazil flag'),
      ],
    ),
  ];
}

/// Full searchable WhatsApp-style emoji picker bottom sheet.
/// Users can browse categories, use recent emojis, search by keyword, or
/// pick any emoji from their phone's OS keyboard via the input field.
class EmojiReactionPickerSheet extends StatefulWidget {
  final String? selectedEmoji;

  const EmojiReactionPickerSheet({
    super.key,
    this.selectedEmoji,
  });

  static Future<String?> show(
    BuildContext context, {
    String? selectedEmoji,
  }) {
    return showModalBottomSheet<String>(
      context: context,
      backgroundColor: const Color(0xFF161426),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => EmojiReactionPickerSheet(selectedEmoji: selectedEmoji),
    );
  }

  @override
  State<EmojiReactionPickerSheet> createState() =>
      _EmojiReactionPickerSheetState();
}

class _EmojiReactionPickerSheetState extends State<EmojiReactionPickerSheet> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  List<String> _recentEmojis = ReactionEmojiCatalog.defaultRecents;
  int _selectedCategoryIndex = 0; // 0 = Recent, 1..n = Catalog categories

  @override
  void initState() {
    super.initState();
    _loadRecents();
  }

  Future<void> _loadRecents() async {
    final recents = await ReactionEmojiCatalog.loadRecents();
    if (mounted) {
      setState(() => _recentEmojis = recents);
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _pickEmoji(String emoji) {
    HapticFeedback.lightImpact();
    ReactionEmojiCatalog.recordRecent(emoji);
    Navigator.of(context).pop(emoji);
  }

  void _handleInputChanged(String value) {
    final directEmoji = ReactionEmojiCatalog.extractDirectEmojiInput(value);
    if (directEmoji != null) {
      _pickEmoji(directEmoji);
      return;
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final bottomInset = media.viewInsets.bottom;
    final sheetHeight = (media.size.height * 0.54).clamp(280.0, 480.0);

    final query = _searchController.text;
    final isSearching = query.trim().isNotEmpty;
    final List<String> displayEmojis;
    if (isSearching) {
      displayEmojis = ReactionEmojiCatalog.search(query)
          .map((e) => e.emoji)
          .toList(growable: false);
    } else if (_selectedCategoryIndex == 0) {
      displayEmojis = _recentEmojis;
    } else {
      final cat =
          ReactionEmojiCatalog.categories[_selectedCategoryIndex - 1];
      displayEmojis = cat.entries.map((e) => e.emoji).toList(growable: false);
    }

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: sheetHeight,
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Container(
                        height: 40,
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F0E17),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: tabColor.withValues(alpha: 0.35),
                            width: 0.9,
                          ),
                        ),
                        child: Row(
                          children: [
                            const SizedBox(width: 10),
                            const Icon(
                              Icons.search_rounded,
                              size: 18,
                              color: tabColor,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextField(
                                controller: _searchController,
                                focusNode: _searchFocus,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13.5,
                                ),
                                decoration: InputDecoration(
                                  hintText: 'Search emoji or use keyboard...',
                                  hintStyle: TextStyle(
                                    color: Colors.grey[500],
                                    fontSize: 12.5,
                                  ),
                                  border: InputBorder.none,
                                  isDense: true,
                                  contentPadding: EdgeInsets.zero,
                                ),
                                onChanged: _handleInputChanged,
                              ),
                            ),
                            if (query.isNotEmpty)
                              IconButton(
                                icon: Icon(
                                  Icons.clear_rounded,
                                  size: 16,
                                  color: Colors.grey[400],
                                ),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(
                                  minWidth: 28,
                                  minHeight: 28,
                                ),
                                tooltip: 'Clear emoji search',
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() {});
                                },
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    IconButton(
                      icon: const Icon(
                        Icons.keyboard_alt_outlined,
                        color: Color(0xFFFFD700),
                        size: 21,
                      ),
                      tooltip: 'Type any emoji from keyboard',
                      constraints: const BoxConstraints(
                        minWidth: 38,
                        minHeight: 38,
                      ),
                      onPressed: () => _searchFocus.requestFocus(),
                    ),
                  ],
                ),
              ),
              if (!isSearching)
                SizedBox(
                  height: 38,
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    scrollDirection: Axis.horizontal,
                    itemCount: 1 + ReactionEmojiCatalog.categories.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 4),
                    itemBuilder: (_, idx) {
                      final selected = _selectedCategoryIndex == idx;
                      final IconData icon;
                      final String label;
                      if (idx == 0) {
                        icon = Icons.access_time_rounded;
                        label = 'Recent';
                      } else {
                        final cat = ReactionEmojiCatalog.categories[idx - 1];
                        icon = cat.icon;
                        label = cat.title;
                      }
                      return Tooltip(
                        message: label,
                        child: InkWell(
                          onTap: () =>
                              setState(() => _selectedCategoryIndex = idx),
                          borderRadius: BorderRadius.circular(10),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            decoration: BoxDecoration(
                              color: selected
                                  ? tabColor.withValues(alpha: 0.22)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(10),
                              border: selected
                                  ? Border.all(
                                      color: tabColor.withValues(alpha: 0.6),
                                      width: 0.8,
                                    )
                                  : null,
                            ),
                            alignment: Alignment.center,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  icon,
                                  size: 17,
                                  color: selected ? tabColor : Colors.white60,
                                ),
                                if (selected) ...[
                                  const SizedBox(width: 5),
                                  Text(
                                    label,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              const SizedBox(height: 6),
              Divider(
                height: 1,
                color: Colors.white.withValues(alpha: 0.08),
              ),
              Expanded(
                child: displayEmojis.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            'No matching emojis in list.\nSwitch your keyboard to emojis above to pick any emoji!',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.grey[400],
                              fontSize: 12.5,
                              height: 1.45,
                            ),
                          ),
                        ),
                      )
                    : GridView.builder(
                        padding: const EdgeInsets.all(10),
                        gridDelegate:
                            const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 46,
                          mainAxisSpacing: 6,
                          crossAxisSpacing: 6,
                        ),
                        itemCount: displayEmojis.length,
                        itemBuilder: (_, idx) {
                          final emoji = displayEmojis[idx];
                          final isSelected = widget.selectedEmoji == emoji;
                          return InkWell(
                            onTap: () => _pickEmoji(emoji),
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                color: isSelected
                                    ? tabColor.withValues(alpha: 0.25)
                                    : Colors.transparent,
                                border: isSelected
                                    ? Border.all(color: tabColor, width: 1.4)
                                    : null,
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                emoji,
                                style: const TextStyle(fontSize: 24),
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
