import 'package:hive/hive.dart';

@HiveType(typeId: 2)
class HiveMoodEntry extends HiveObject {
  @HiveField(0)
  String id;

  @HiveField(1)
  String userId;

  @HiveField(2)
  DateTime timestamp;

  @HiveField(3)
  int moodRating;

  @HiveField(4)
  int connectionRating;

  @HiveField(5)
  int energyRating;

  @HiveField(6)
  double lonelinessScore;

  @HiveField(7)
  String? notes;

  @HiveField(8)
  bool synced;

  HiveMoodEntry({
    required this.id,
    required this.userId,
    required this.timestamp,
    required this.moodRating,
    required this.connectionRating,
    required this.energyRating,
    required this.lonelinessScore,
    this.notes,
    required this.synced,
  });
}

class HiveMoodEntryAdapter extends TypeAdapter<HiveMoodEntry> {
  @override
  final int typeId = 2;

  @override
  HiveMoodEntry read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return HiveMoodEntry(
      id: fields[0] as String,
      userId: fields[1] as String,
      timestamp: fields[2] as DateTime,
      moodRating: fields[3] as int,
      connectionRating: fields[4] as int,
      energyRating: fields[5] as int,
      lonelinessScore: fields[6] as double,
      notes: fields[7] as String?,
      synced: fields[8] as bool,
    );
  }

  @override
  void write(BinaryWriter writer, HiveMoodEntry obj) {
    writer
      ..writeByte(9)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.userId)
      ..writeByte(2)
      ..write(obj.timestamp)
      ..writeByte(3)
      ..write(obj.moodRating)
      ..writeByte(4)
      ..write(obj.connectionRating)
      ..writeByte(5)
      ..write(obj.energyRating)
      ..writeByte(6)
      ..write(obj.lonelinessScore)
      ..writeByte(7)
      ..write(obj.notes)
      ..writeByte(8)
      ..write(obj.synced);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HiveMoodEntryAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;

  @override
  int get hashCode => typeId.hashCode;
}
