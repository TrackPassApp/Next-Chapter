class UserProfile {
  final String id;
  final String firstName;
  final DateTime dateOfBirth;
  final String city;
  final String state;
  final String gender;
  final String relationshipStatus;
  final List<String> photoUrls;
  final String aboutMe;
  final List<String> lookingFor;
  final List<String> interests;
  final List<String> lifeSituation;
  final bool emailVerified;
  final bool phoneVerified;
  final bool selfieVerified;
  final bool idVerified;
  final bool isOnline;
  final DateTime lastActive;
  final bool isSuspended;

  const UserProfile({
    required this.id,
    required this.firstName,
    required this.dateOfBirth,
    required this.city,
    required this.state,
    required this.gender,
    required this.relationshipStatus,
    required this.photoUrls,
    required this.aboutMe,
    required this.lookingFor,
    required this.interests,
    required this.lifeSituation,
    this.emailVerified = false,
    this.phoneVerified = false,
    this.selfieVerified = false,
    this.idVerified = false,
    this.isOnline = false,
    required this.lastActive,
    this.isSuspended = false,
  });

  int get age {
    final now = DateTime.now();
    int a = now.year - dateOfBirth.year;
    if (now.month < dateOfBirth.month || (now.month == dateOfBirth.month && now.day < dateOfBirth.day)) {
      a--;
    }
    return a;
  }

  int get verificationCount {
    int count = 0;
    if (emailVerified) count++;
    if (phoneVerified) count++;
    if (selfieVerified) count++;
    if (idVerified) count++;
    return count;
  }

  bool get hasAnyVerification => verificationCount > 0;

  UserProfile copyWith({
    String? firstName,
    DateTime? dateOfBirth,
    String? city,
    String? state,
    String? gender,
    String? relationshipStatus,
    List<String>? photoUrls,
    String? aboutMe,
    List<String>? lookingFor,
    List<String>? interests,
    List<String>? lifeSituation,
    bool? emailVerified,
    bool? phoneVerified,
    bool? selfieVerified,
    bool? idVerified,
    bool? isOnline,
    DateTime? lastActive,
    bool? isSuspended,
  }) {
    return UserProfile(
      id: id,
      firstName: firstName ?? this.firstName,
      dateOfBirth: dateOfBirth ?? this.dateOfBirth,
      city: city ?? this.city,
      state: state ?? this.state,
      gender: gender ?? this.gender,
      relationshipStatus: relationshipStatus ?? this.relationshipStatus,
      photoUrls: photoUrls ?? this.photoUrls,
      aboutMe: aboutMe ?? this.aboutMe,
      lookingFor: lookingFor ?? this.lookingFor,
      interests: interests ?? this.interests,
      lifeSituation: lifeSituation ?? this.lifeSituation,
      emailVerified: emailVerified ?? this.emailVerified,
      phoneVerified: phoneVerified ?? this.phoneVerified,
      selfieVerified: selfieVerified ?? this.selfieVerified,
      idVerified: idVerified ?? this.idVerified,
      isOnline: isOnline ?? this.isOnline,
      lastActive: lastActive ?? this.lastActive,
      isSuspended: isSuspended ?? this.isSuspended,
    );
  }
}

class LifeSituationOptions {
  static const List<String> all = [
    'Divorced',
    'Widowed',
    'Single Parent',
    'Empty Nester',
    'Veteran',
    'Disabled',
    'Retired',
    'Recently Relocated',
    'Starting Over',
  ];
}

class LookingForOptions {
  static const List<String> all = [
    'Friendship',
    'Dating',
    'Long-Term Relationship',
    'Travel Partner',
    'Activity Partner',
    'Local Friends',
    'Online Friends',
    'Open To Anything',
  ];
}

class InterestOptions {
  static const List<String> all = [
    'Hiking',
    'Reading',
    'Cooking',
    'Travel',
    'Photography',
    'Music',
    'Yoga',
    'Gardening',
    'Movies',
    'Fitness',
    'Art',
    'Board Games',
    'Volunteering',
    'Wine Tasting',
    'Dancing',
    'Pets',
    'Crafts',
    'Technology',
    'Writing',
    'Sports',
  ];
}
