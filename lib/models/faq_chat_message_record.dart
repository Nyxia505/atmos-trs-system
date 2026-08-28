import 'package:cloud_firestore/cloud_firestore.dart';

/// Persisted FAQ chat row stored at `users/{uid}/faq_chats/{messageId}`.
class FaqChatMessageRecord {
  const FaqChatMessageRecord({
    required this.id,
    required this.sender,
    required this.message,
    required this.timestamp,
    required this.language,
    required this.messageType,
    required this.createdAt,
  });

  final String id;
  final String sender;
  final String message;
  final DateTime timestamp;
  final String language;
  final String messageType;
  final DateTime createdAt;

  bool get isUser => sender == 'user';

  factory FaqChatMessageRecord.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? {};
    return FaqChatMessageRecord.fromMap(doc.id, data);
  }

  factory FaqChatMessageRecord.fromMap(String id, Map<String, dynamic> data) {
    return FaqChatMessageRecord(
      id: id,
      sender: (data['sender'] as String? ?? 'user').trim(),
      message: (data['message'] as String? ?? '').trim(),
      timestamp: _readDate(data['timestamp']) ?? _readDate(data['createdAt']) ?? DateTime.now(),
      language: (data['language'] as String? ?? 'en').trim(),
      messageType: (data['messageType'] as String? ?? 'text').trim(),
      createdAt: _readDate(data['createdAt']) ?? _readDate(data['timestamp']) ?? DateTime.now(),
    );
  }

  factory FaqChatMessageRecord.fromJson(Map<String, dynamic> json) {
    return FaqChatMessageRecord(
      id: json['id'] as String? ?? '',
      sender: json['sender'] as String? ?? 'user',
      message: json['message'] as String? ?? '',
      timestamp: DateTime.tryParse(json['timestamp'] as String? ?? '') ?? DateTime.now(),
      language: json['language'] as String? ?? 'en',
      messageType: json['messageType'] as String? ?? 'text',
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'sender': sender,
      'message': message,
      'timestamp': Timestamp.fromDate(timestamp),
      'language': language,
      'messageType': messageType,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'sender': sender,
      'message': message,
      'timestamp': timestamp.toIso8601String(),
      'language': language,
      'messageType': messageType,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  static DateTime? _readDate(Object? value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }
}
