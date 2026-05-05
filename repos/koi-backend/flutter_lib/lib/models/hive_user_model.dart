import 'package:hive/hive.dart';

@HiveType(typeId: 0)
class HiveUser extends HiveObject {
  @HiveField(0)
  String id;

  @HiveField(1)
  DateTime createdAt;

  @HiveField(2)
  DateTime lastActive;

  @HiveField(3)
  String? avatarType;

  @HiveField(4)
  String language;

  @HiveField(5)
  String? notificationTime;

  @HiveField(6)
  String? primaryProfile;

  @HiveField(7)
  String? secondaryProfile;

  @HiveField(8)
  String? severityTier;

  @HiveField(9)
  int? uclaScore;

  @HiveField(10)
  String settings;

  @HiveField(11)
  int totalConversations;

  @HiveField(12)
  int totalCheckIns;

  @HiveField(13)
  int currentStreak;

  @HiveField(14)
  int longestStreak;

  @HiveField(15)
  int jigsawPieces;

  HiveUser({
    required this.id,
    required this.createdAt,
    required this.lastActive,
    this.avatarType,
    required this.language,
    this.notificationTime,
    this.primaryProfile,
    this.secondaryProfile,
    this.severityTier,
    this.uclaScore,
    required this.settings,
    required this.totalConversations,
    required this.totalCheckIns,
    required this.currentStreak,
    required this.longestStreak,
    required this.jigsawPieces,
  });
}

class HiveUserAdapter extends TypeAdapter<HiveUser> {
  @override
  final int typeId = 0;

  @override
  HiveUser read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return HiveUser(
      id: fields[0] as String,
      createdAt: fields[1] as DateTime,
      lastActive: fields[2] as DateTime,
      avatarType: fields[3] as String?,
      language: fields[4] as String,
      notificationTime: fields[5] as String?,
      primaryProfile: fields[6] as String?,
      secondaryProfile: fields[7] as String?,
      severityTier: fields[8] as String?,
      uclaScore: fields[9] as int?,
      settings: fields[10] as String,
      totalConversations: fields[11] as int,
      totalCheckIns: fields[12] as int,
      currentStreak: fields[13] as int,
      longestStreak: fields[14] as int,
      jigsawPieces: fields[15] as int,
    );
  }

  @override
  void write(BinaryWriter writer, HiveUser obj) {
    writer
      ..writeByte(16)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.createdAt)
      ..writeByte(2)
      ..write(obj.lastActive)
      ..writeByte(3)
      ..write(obj.avatarType)
      ..writeByte(4)
      ..write(obj.language)
      ..writeByte(5)
      ..write(obj.notificationTime)
      ..writeByte(6)
      ..write(obj.primaryProfile)
      ..writeByte(7)
      ..write(obj.secondaryProfile)
      ..writeByte(8)
      ..write(obj.severityTier)
      ..writeByte(9)
      ..write(obj.uclaScore)
      ..writeByte(10)
      ..write(obj.settings)
      ..writeByte(11)
      ..write(obj.totalConversations)
      ..writeByte(12)
      ..write(obj.totalCheckIns)
      ..writeByte(13)
      ..write(obj.currentStreak)
      ..writeByte(14)
      ..write(obj.longestStreak)
      ..writeByte(15)
      ..write(obj.jigsawPieces);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HiveUserAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;

  @override
  int get hashCode => typeId.hashCode;
}
