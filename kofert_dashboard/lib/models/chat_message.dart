import 'package:cloud_firestore/cloud_firestore.dart';

enum MessageType { text }

class ChatMessage {
  final String id;
  final String senderId;
  final String senderName;
  final String senderEmail;
  final String text;
  final DateTime timestamp;
  final MessageType type;

  const ChatMessage({
    required this.id,
    required this.senderId,
    required this.senderName,
    required this.senderEmail,
    required this.text,
    required this.timestamp,
    this.type = MessageType.text,
  });

  factory ChatMessage.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return ChatMessage(
      id: doc.id,
      senderId: d['senderId'] as String? ?? '',
      senderName: d['senderName'] as String? ?? 'Anonyme',
      senderEmail: d['senderEmail'] as String? ?? '',
      text: d['text'] as String? ?? '',
      timestamp: ((d['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now()).toLocal(),
    );
  }

  Map<String, dynamic> toMap() => {
        'senderId': senderId,
        'senderName': senderName,
        'senderEmail': senderEmail,
        'text': text,
        'timestamp': FieldValue.serverTimestamp(),
      };
}

/// A compact user record fetched from Firestore for the user list.
class UserRecord {
  final String uid;
  final String name;
  final String customId;
  final String email;
  final String presenceStatus; // 'online' | 'offline' | 'dnd'
  final DateTime? lastSeen;

  const UserRecord({
    required this.uid,
    required this.name,
    required this.customId,
    required this.email,
    this.presenceStatus = 'offline',
    this.lastSeen,
  });

  UserRecord copyWith({String? presenceStatus, DateTime? lastSeen}) =>
      UserRecord(
        uid: uid,
        name: name,
        customId: customId,
        email: email,
        presenceStatus: presenceStatus ?? this.presenceStatus,
        lastSeen: lastSeen ?? this.lastSeen,
      );
}
