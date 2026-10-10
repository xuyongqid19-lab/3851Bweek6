import 'package:flutter/foundation.dart';

class ProfileData {
  final String name;
  final String username;
  final int age;
  final DateTime? birthDate;
  final String email;
  final String phone;
  final String community;
  final String address;
  final List<String> interestTags;
  final Map<String, String> customInterestCategories;

  const ProfileData({
    required this.name,
    required this.username,
    required this.age,
    this.birthDate,
    required this.email,
    required this.phone,
    this.community = '',
    this.address = '',
    this.interestTags = const [],
    this.customInterestCategories = const {},
  });

  /// 展示用年龄：有出生日期时按出生日期实时计算，否则用存量 age。
  int get displayAge => birthDate == null ? age : calculateAge(birthDate!);

  ProfileData copyWith({
    String? name,
    String? username,
    int? age,
    DateTime? birthDate,
    String? email,
    String? phone,
    String? community,
    String? address,
    List<String>? interestTags,
    Map<String, String>? customInterestCategories,
  }) {
    return ProfileData(
      name: name ?? this.name,
      username: username ?? this.username,
      age: age ?? this.age,
      birthDate: birthDate ?? this.birthDate,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      community: community ?? this.community,
      address: address ?? this.address,
      interestTags: interestTags ?? this.interestTags,
      customInterestCategories:
          customInterestCategories ?? this.customInterestCategories,
    );
  }
}

/// 根据出生年月日计算周岁年龄。
int calculateAge(DateTime birthDate, [DateTime? asOf]) {
  final now = asOf ?? DateTime.now();
  var age = now.year - birthDate.year;
  if (now.month < birthDate.month ||
      (now.month == birthDate.month && now.day < birthDate.day)) {
    age--;
  }
  return age < 0 ? 0 : age;
}

/// 格式化为 yyyy-MM-dd，便于展示与填写。
String formatBirthDate(DateTime birthDate) {
  final y = birthDate.year.toString().padLeft(4, '0');
  final m = birthDate.month.toString().padLeft(2, '0');
  final d = birthDate.day.toString().padLeft(2, '0');
  return '$y-$m-$d';
}

class MatchUser {
  final String name;
  final int age;
  final String community;
  final String address;
  final List<String> interestTags;
  final String avatarInitial;
  final double matchScore;

  const MatchUser({
    required this.name,
    required this.age,
    this.community = '',
    this.address = '',
    this.interestTags = const [],
    required this.avatarInitial,
    this.matchScore = 0,
  });
}

final availableInterests = [
  'Hiking',
  'Photography',
  'Basketball',
  'Cooking',
  'Travel',
  'Yoga',
  'Gaming',
  'Music',
  'Art',
  'Running',
  'Swimming',
  'Cycling',
  'Reading',
  'Writing',
  'Dancing',
  'Movies',
  'Gardening',
  'Fishing',
  'Painting',
  'Singing',
];

/// 大类 -> 小标签映射。小标签可归属多个大类，用于“大类相同也加分”。
const interestCategories = {
  'Sports': ['Basketball', 'Yoga', 'Running', 'Swimming', 'Cycling'],
  'Outdoors': [
    'Hiking',
    'Travel',
    'Gardening',
    'Fishing',
    'Cycling',
    'Running'
  ],
  'Arts': [
    'Photography',
    'Music',
    'Art',
    'Dancing',
    'Movies',
    'Painting',
    'Singing'
  ],
  'Life': ['Cooking', 'Gardening', 'Travel', 'Movies', 'Photography'],
  'Mind': ['Gaming', 'Reading', 'Writing', 'Yoga', 'Photography'],
};

/// 单个标签归属的大类集合。预设标签查表，自定义标签查 customMap。
Set<String> categoriesOfTag(String tag, [Map<String, String>? customMap]) {
  final result = <String>{};
  interestCategories.forEach((big, smalls) {
    if (smalls.contains(tag)) result.add(big);
  });
  final custom = customMap?[tag];
  if (custom != null && custom.isNotEmpty) result.add(custom);
  return result;
}

/// 一组标签展开成大类集合。
Set<String> tagsToCategories(List<String> tags,
    [Map<String, String>? customMap]) {
  final result = <String>{};
  for (final tag in tags) {
    result.addAll(categoriesOfTag(tag, customMap));
  }
  return result;
}

/// 双方大类重合数（用于加分）。
int countSharedCategories(List<String> a, List<String> b,
    [Map<String, String>? customMapA]) {
  final catsA = tagsToCategories(a, customMapA);
  final catsB = tagsToCategories(b, null);
  return catsA.intersection(catsB).length;
}

final availableCommunities = [
  'Riverside',
  'Central Park',
  'Downtown',
  'Sunset Village',
  'Pine Ridge',
  'Lakeview',
  'Greenwood',
  'Oakville',
];

/// Map backend /auth/me user JSON to local ProfileData.
/// Backend shape: fullName, birthDate (YYYY-MM-DD), interests (list),
/// customCategories (map), username, email, phone, community, address.
ProfileData profileFromAuthUser(Map<String, dynamic> user,
    {ProfileData? fallback}) {
  String str(String key) => user[key]?.toString() ?? '';
  final fullName = str('fullName').trim();
  final username = str('username').trim();
  final email = str('email').trim();
  final phone = str('phone');
  final community = str('community');
  final address = str('address');
  DateTime? birth;
  final birthStr = str('birthDate').trim();
  if (birthStr.isNotEmpty) {
    try {
      birth = DateTime.parse(birthStr);
    } catch (_) {
      birth = null;
    }
  }
  var interests = <String>[];
  final rawInterests = user['interests'];
  if (rawInterests is List) {
    interests = rawInterests
        .whereType<String>()
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .take(10)
        .toList();
  } else if (user['interest'] is String &&
      (user['interest'] as String).trim().isNotEmpty) {
    interests = [(user['interest'] as String).trim()];
  }
  var custom = <String, String>{};
  final rawCustom = user['customCategories'];
  if (rawCustom is Map) {
    rawCustom.forEach((k, v) {
      if (k is String && v is String && interests.contains(k)) {
        custom[k] = v;
      }
    });
  }
  final fb = fallback;
  final resolvedBirth = birth ?? fb?.birthDate;
  return ProfileData(
    name: fullName.isNotEmpty ? fullName : (fb?.name ?? 'You'),
    username: username.isNotEmpty ? username : (fb?.username ?? '@you'),
    age: resolvedBirth != null ? calculateAge(resolvedBirth) : (fb?.age ?? 25),
    birthDate: resolvedBirth,
    email: email.isNotEmpty ? email : (fb?.email ?? ''),
    phone: phone.isNotEmpty ? phone : (fb?.phone ?? ''),
    community: community.isNotEmpty ? community : (fb?.community ?? ''),
    address: address.isNotEmpty ? address : (fb?.address ?? ''),
    interestTags:
        interests.isNotEmpty ? interests : (fb?.interestTags ?? const []),
    customInterestCategories:
        custom.isNotEmpty ? custom : (fb?.customInterestCategories ?? const {}),
  );
}

final ValueNotifier<ProfileData> currentProfile = ValueNotifier<ProfileData>(
  ProfileData(
    name: 'You',
    username: '@you',
    age: 25,
    birthDate: DateTime(2001, 5, 20),
    email: 'you@example.com',
    phone: '+1 234 567 8900',
    community: 'Riverside',
    address: '123 Main St, Riverside',
    interestTags: ['Hiking', 'Photography', 'Music'],
  ),
);

const matchUsers = <MatchUser>[
  MatchUser(
    name: 'Alex Johnson',
    age: 27,
    community: 'Riverside',
    address: '456 Oak Ave, Riverside',
    interestTags: ['Hiking', 'Photography', 'Basketball'],
    avatarInitial: 'A',
  ),
  MatchUser(
    name: 'Sophie Chen',
    age: 24,
    community: 'Central Park',
    address: '789 Pine St, Central Park',
    interestTags: ['Cooking', 'Travel', 'Yoga'],
    avatarInitial: 'S',
  ),
  MatchUser(
    name: 'Liam Brown',
    age: 29,
    community: 'Downtown',
    address: '321 Elm St, Downtown',
    interestTags: ['Gaming', 'Music', 'Basketball'],
    avatarInitial: 'L',
  ),
  MatchUser(
    name: 'Emma Wang',
    age: 23,
    community: 'Sunset Village',
    address: '654 Birch Ln, Sunset Village',
    interestTags: ['Art', 'Photography', 'Movies'],
    avatarInitial: 'E',
  ),
  MatchUser(
    name: 'Noah Lee',
    age: 28,
    community: 'Riverside',
    address: '987 Cedar Dr, Riverside',
    interestTags: ['Running', 'Swimming', 'Cycling'],
    avatarInitial: 'N',
  ),
  MatchUser(
    name: 'Olivia Tan',
    age: 26,
    community: 'Pine Ridge',
    address: '147 Walnut Ct, Pine Ridge',
    interestTags: ['Reading', 'Writing', 'Yoga'],
    avatarInitial: 'O',
  ),
  MatchUser(
    name: 'James Wong',
    age: 30,
    community: 'Lakeview',
    address: '258 Spruce Way, Lakeview',
    interestTags: ['Cooking', 'Travel', 'Photography'],
    avatarInitial: 'J',
  ),
  MatchUser(
    name: 'Mia Patel',
    age: 22,
    community: 'Greenwood',
    address: '369 Ash Blvd, Greenwood',
    interestTags: ['Dancing', 'Music', 'Art'],
    avatarInitial: 'M',
  ),
  MatchUser(
    name: 'Ethan Kim',
    age: 31,
    community: 'Oakville',
    address: '159 Maple Dr, Oakville',
    interestTags: ['Fishing', 'Gardening', 'Hiking'],
    avatarInitial: 'E',
  ),
  MatchUser(
    name: 'Ava Martinez',
    age: 25,
    community: 'Downtown',
    address: '753 Cherry Ln, Downtown',
    interestTags: ['Yoga', 'Reading', 'Movies'],
    avatarInitial: 'A',
  ),
];

List<MatchUser> interestMatch(ProfileData profile) {
  final scored = matchUsers.map((user) {
    final shared = profile.interestTags
        .where((tag) => user.interestTags.contains(tag))
        .length;
    final max = profile.interestTags.isEmpty
        ? 1
        : (profile.interestTags.length + user.interestTags.length) ~/ 2;
    final ageDiff = (profile.displayAge - user.age).abs();
    final ageBonus = ageDiff <= 5 ? 0.2 : (ageDiff <= 10 ? 0.1 : 0);
    // 大类加分：不同小标签但同大类也加分，0.05/个大类，上限0.15
    final sharedCats = countSharedCategories(
      profile.interestTags,
      user.interestTags,
      profile.customInterestCategories,
    );
    final categoryBonus = (sharedCats * 0.05).clamp(0, 0.15);
    final score = (max > 0 ? shared / max : 0) + ageBonus + categoryBonus;
    return MatchUser(
      name: user.name,
      age: user.age,
      community: user.community,
      address: user.address,
      interestTags: user.interestTags,
      avatarInitial: user.avatarInitial,
      matchScore: double.parse((score.clamp(0, 1) * 100).toStringAsFixed(0)),
    );
  }).toList();
  scored.sort((a, b) => b.matchScore.compareTo(a.matchScore));
  return scored;
}

List<MatchUser> recommendMatch(ProfileData profile) {
  final scored = matchUsers.map((user) {
    double score = 0;
    if (user.community == profile.community) score += 0.4;
    final ageDiff = (profile.displayAge - user.age).abs();
    if (ageDiff <= 3) {
      score += 0.3;
    } else if (ageDiff <= 7) {
      score += 0.15;
    }
    final shared = profile.interestTags
        .where((tag) => user.interestTags.contains(tag))
        .length;
    // 小标签相同 +0.12，大类相同 +0.05/个（上限0.15）
    score += shared * 0.12;
    final sharedCats = countSharedCategories(
      profile.interestTags,
      user.interestTags,
      profile.customInterestCategories,
    );
    score += (sharedCats * 0.05).clamp(0, 0.15);
    return MatchUser(
      name: user.name,
      age: user.age,
      community: user.community,
      address: user.address,
      interestTags: user.interestTags,
      avatarInitial: user.avatarInitial,
      matchScore: double.parse((score.clamp(0, 1) * 100).toStringAsFixed(0)),
    );
  }).toList();
  scored.sort((a, b) => b.matchScore.compareTo(a.matchScore));
  return scored;
}
