import 'package:hive/hive.dart';

@HiveType(typeId: 1)
class HiveMessage extends HiveObject {
  @HiveField(0)
  String id;

  @HiveField(1)
  String conversationId;

  @HiveField(2)
  String sender;

  @HiveField(3)
  String content;

  @HiveField(4)
  DateTime timestamp;

  @HiveField(5)
  double? textSentiment;

  @HiveField(6)
  double? audioEmotion;

  @HiveField(7)
  double? videoEmotion;

  @HiveField(8)
  double? fusedEmotion;

  @HiveField(9)
  bool synced;

  HiveMessage({
    required this.id,
    required this.conversationId,
    required this.sender,
    required this.content,
    required this.timestamp,
    this.textSentiment,
    this.audioEmotion,
    this.videoEmotion,
    this.fusedEmotion,
    required this.synced,
  });
}

class HiveMessageAdapter extends TypeAdapter<HiveMessage> {
  @override
  final int typeId = 1;

  @override
  HiveMessage read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return HiveMessage(
      id: fields[0] as String,
      conversationId: fields[1] as String,
      sender: fields[2] as String,
      content: fields[3] as String,
      timestamp: fields[4] as DateTime,
      textSentiment: fields[5] as double?,
      audioEmotion: fields[6] as double?,
      videoEmotion: fields[7] as double?,
      fusedEmotion: fields[8] as double?,
      synced: fields[9] as bool,
    );
  }

  @override
  void write(BinaryWriter writer, HiveMessage obj) {
    writer
      ..writeByte(10)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.conversationId)
      ..writeByte(2)
      ..write(obj.sender)
      ..writeByte(3)
      ..write(obj.content)
      ..writeByte(4)
      ..write(obj.timestamp)
      ..writeByte(5)
      ..write(obj.textSentiment)
      ..writeByte(6)
      ..write(obj.audioEmotion)
      ..writeByte(7)
      ..write(obj.videoEmotion)
      ..writeByte(8)
      ..write(obj.fusedEmotion)
      ..writeByte(9)
      ..write(obj.synced);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HiveMessageAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;

  @override
  int get hashCode => typeId.hashCode;
}
