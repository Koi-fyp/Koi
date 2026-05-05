import 'package:hive/hive.dart';

@HiveType(typeId: 4)
class HiveTask extends HiveObject {
  @HiveField(0)
  String id;

  @HiveField(1)
  String userId;

  @HiveField(2)
  String type;

  @HiveField(3)
  String description;

  @HiveField(4)
  int commitmentLevel;

  @HiveField(5)
  DateTime createdAt;

  @HiveField(6)
  DateTime? completedAt;

  @HiveField(7)
  bool archived;

  @HiveField(8)
  bool synced;

  HiveTask({
    required this.id,
    required this.userId,
    required this.type,
    required this.description,
    required this.commitmentLevel,
    required this.createdAt,
    this.completedAt,
    required this.archived,
    required this.synced,
  });
}

class HiveTaskAdapter extends TypeAdapter<HiveTask> {
  @override
  final int typeId = 4;

  @override
  HiveTask read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return HiveTask(
      id: fields[0] as String,
      userId: fields[1] as String,
      type: fields[2] as String,
      description: fields[3] as String,
      commitmentLevel: fields[4] as int,
      createdAt: fields[5] as DateTime,
      completedAt: fields[6] as DateTime?,
      archived: fields[7] as bool,
      synced: fields[8] as bool,
    );
  }

  @override
  void write(BinaryWriter writer, HiveTask obj) {
    writer
      ..writeByte(9)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.userId)
      ..writeByte(2)
      ..write(obj.type)
      ..writeByte(3)
      ..write(obj.description)
      ..writeByte(4)
      ..write(obj.commitmentLevel)
      ..writeByte(5)
      ..write(obj.createdAt)
      ..writeByte(6)
      ..write(obj.completedAt)
      ..writeByte(7)
      ..write(obj.archived)
      ..writeByte(8)
      ..write(obj.synced);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HiveTaskAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;

  @override
  int get hashCode => typeId.hashCode;
}
