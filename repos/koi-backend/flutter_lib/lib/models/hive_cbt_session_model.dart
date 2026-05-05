import 'package:hive/hive.dart';

@HiveType(typeId: 3)
class HiveCBTSession extends HiveObject {
  @HiveField(0)
  String id;

  @HiveField(1)
  String userId;

  @HiveField(2)
  String moduleType;

  @HiveField(3)
  DateTime startedAt;

  @HiveField(4)
  DateTime? completedAt;

  @HiveField(5)
  double? qualityScore;

  @HiveField(6)
  String? userInsights;

  @HiveField(7)
  int jigsawPiecesAwarded;

  @HiveField(8)
  bool synced;

  HiveCBTSession({
    required this.id,
    required this.userId,
    required this.moduleType,
    required this.startedAt,
    this.completedAt,
    this.qualityScore,
    this.userInsights,
    required this.jigsawPiecesAwarded,
    required this.synced,
  });
}

class HiveCBTSessionAdapter extends TypeAdapter<HiveCBTSession> {
  @override
  final int typeId = 3;

  @override
  HiveCBTSession read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return HiveCBTSession(
      id: fields[0] as String,
      userId: fields[1] as String,
      moduleType: fields[2] as String,
      startedAt: fields[3] as DateTime,
      completedAt: fields[4] as DateTime?,
      qualityScore: fields[5] as double?,
      userInsights: fields[6] as String?,
      jigsawPiecesAwarded: fields[7] as int,
      synced: fields[8] as bool,
    );
  }

  @override
  void write(BinaryWriter writer, HiveCBTSession obj) {
    writer
      ..writeByte(9)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.userId)
      ..writeByte(2)
      ..write(obj.moduleType)
      ..writeByte(3)
      ..write(obj.startedAt)
      ..writeByte(4)
      ..write(obj.completedAt)
      ..writeByte(5)
      ..write(obj.qualityScore)
      ..writeByte(6)
      ..write(obj.userInsights)
      ..writeByte(7)
      ..write(obj.jigsawPiecesAwarded)
      ..writeByte(8)
      ..write(obj.synced);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HiveCBTSessionAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;

  @override
  int get hashCode => typeId.hashCode;
}
