import 'package:cloud_firestore/cloud_firestore.dart';

class KoiUser {
  final String uid; // Firebase UID (we will preserve an app UUID as koiUuid in Firestore)
  final String? koiUuid;
  final DateTime? createdAt;
  final DateTime? lastActive;
  final Map<String, dynamic> profile;
  final Map<String, dynamic> classification;
  final Map<String, dynamic> settings;
  final Map<String, dynamic> stats;

  KoiUser({
    required this.uid,
    this.koiUuid,
    this.createdAt,
    this.lastActive,
    Map<String, dynamic>? profile,
    Map<String, dynamic>? classification,
    Map<String, dynamic>? settings,
    Map<String, dynamic>? stats,
  })  : profile = profile ?? const {
          'avatar': null,
          'language': 'en',
          'notificationTime': null,
        },
        classification = classification ?? const {
          'primary_profile': null,
          'secondary_profile': null,
          'severity_tier': null,
          'ucla_score': null,
        },
        settings = settings ?? const {
          'notifications_enabled': true,
          'sound_enabled': true,
          'haptic_enabled': true,
        },
        stats = stats ?? const {
          'total_conversations': 0,
          'total_check_ins': 0,
          'current_streak': 0,
          'longest_streak': 0,
          'jigsaw_pieces': 0,
        };

  Map<String, dynamic> toMap() {
    return {
      'koiUuid': koiUuid,
      'createdAt': createdAt != null ? Timestamp.fromDate(createdAt!) : FieldValue.serverTimestamp(),
      'lastActive': lastActive != null ? Timestamp.fromDate(lastActive!) : FieldValue.serverTimestamp(),
      'profile': profile,
      'classification': classification,
      'settings': settings,
      'stats': stats,
    };
  }

  factory KoiUser.fromFirestore(DocumentSnapshot<Map<String, dynamic>> ds) {
    final data = ds.data() ?? {};
    final Timestamp? createdTs = data['createdAt'] as Timestamp?;
    final Timestamp? lastTs = data['lastActive'] as Timestamp?;
    return KoiUser(
      uid: ds.id,
      koiUuid: data['koiUuid'] as String?,
      createdAt: createdTs?.toDate(),
      lastActive: lastTs?.toDate(),
      profile: Map<String, dynamic>.from(data['profile'] ?? {}),
      classification: Map<String, dynamic>.from(data['classification'] ?? {}),
      settings: Map<String, dynamic>.from(data['settings'] ?? {}),
      stats: Map<String, dynamic>.from(data['stats'] ?? {}),
    );
  }
}
