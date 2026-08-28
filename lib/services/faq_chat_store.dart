import 'dart:async';
import 'dart:convert';

import 'package:atmos_trs_system/config/auth_config.dart';
import 'package:atmos_trs_system/models/faq_chat_message_record.dart';
import 'package:atmos_trs_system/services/faq_chatbot_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

/// Singleton store for FAQ chat history — Firestore + local cache.
class FaqChatStore extends ChangeNotifier {
  FaqChatStore._();

  static final FaqChatStore instance = FaqChatStore._();

  static const _uuid = Uuid();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  String? _uid;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _subscription;
  List<FaqChatMessageRecord> _messages = [];
  bool _loading = false;
  bool _initialized = false;
  bool _seededWelcome = false;

  List<FaqChatMessageRecord> get messages => List.unmodifiable(_messages);
  bool get isLoading => _loading;
  bool get isInitialized => _initialized;
  String? get boundUid => _uid;

  CollectionReference<Map<String, dynamic>>? get _collection {
    final uid = _uid;
    if (uid == null || uid.isEmpty) return null;
    return _firestore.collection('users').doc(uid).collection('faq_chats');
  }

  String _cacheKey(String uid) => 'faq_chat_cache_v1_$uid';

  Future<String?> resolveUid([String? override]) async {
    final direct = override?.trim();
    if (direct != null && direct.isNotEmpty) return direct;
    final cached = AuthConfig.currentUserUid?.trim();
    if (cached != null && cached.isNotEmpty) return cached;
    return FirebaseAuth.instance.currentUser?.uid;
  }

  /// Binds the store to [uid], loads cache instantly, then listens to Firestore.
  Future<void> bindUser([String? uid]) async {
    final resolved = await resolveUid(uid);
    if (_uid == resolved && _initialized) return;

    await _subscription?.cancel();
    _subscription = null;
    _uid = resolved;
    _initialized = false;
    _seededWelcome = false;
    _loading = true;
    notifyListeners();

    if (resolved == null || resolved.isEmpty) {
      _messages = await _readCache('guest');
      _loading = false;
      _initialized = true;
      notifyListeners();
      return;
    }

    _messages = await _readCache(resolved);
    _loading = false;
    notifyListeners();

    if (_messages.isEmpty) {
      try {
        final snap = await _collection!.orderBy('timestamp').get();
        _onSnapshot(snap);
      } catch (e) {
        debugPrint('[FaqChatStore] initial fetch failed: $e');
        if (_messages.isEmpty) {
          _seededWelcome = true;
          await _ensureWelcomeIfEmpty();
        }
      }
    } else {
      _seededWelcome = true;
    }

    _subscription = _collection!
        .orderBy('timestamp')
        .snapshots()
        .listen(
          _onSnapshot,
          onError: (Object e) {
            debugPrint('[FaqChatStore] snapshot error: $e');
          },
        );

    _initialized = true;
  }

  void _onSnapshot(QuerySnapshot<Map<String, dynamic>> snapshot) {
    final merged = <String, FaqChatMessageRecord>{};

    for (final doc in snapshot.docs) {
      final record = FaqChatMessageRecord.fromFirestore(doc);
      if (record.message.isEmpty) continue;
      merged[record.id] = record;
    }

    for (final local in _messages) {
      merged.putIfAbsent(local.id, () => local);
    }

    _messages = merged.values.toList()
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

    unawaited(_writeCache(_uid!, _messages));
    notifyListeners();

    if (!_seededWelcome) {
      _seededWelcome = true;
      unawaited(_ensureWelcomeIfEmpty());
    }
  }

  Future<void> _ensureWelcomeIfEmpty() async {
    if (_messages.isNotEmpty) return;
    if (_messages.any((m) => m.messageType == 'welcome')) return;
    final uid = _uid;
    if (uid == null || uid.isEmpty) return;

    final chatbot = FaqChatbotService.instance;
    final welcome = chatbot.welcomeFor(null);
    await appendMessage(
      text: welcome,
      sender: 'ai',
      language: 'en',
      messageType: 'welcome',
    );
  }

  Future<void> appendMessage({
    required String text,
    required String sender,
    required String language,
    String messageType = 'text',
    String? id,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;

    final uid = _uid;
    final now = DateTime.now();
    final record = FaqChatMessageRecord(
      id: id ?? _uuid.v4(),
      sender: sender,
      message: trimmed,
      timestamp: now,
      language: language,
      messageType: messageType,
      createdAt: now,
    );

    if (_messages.any((m) => m.id == record.id)) return;

    _messages = [..._messages, record]
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    notifyListeners();

    if (uid != null && uid.isNotEmpty) {
      unawaited(_writeCache(uid, _messages));
      try {
        await _collection!.doc(record.id).set(record.toFirestore());
      } catch (e) {
        debugPrint('[FaqChatStore] save message failed: $e');
      }
    } else {
      unawaited(_writeCache('guest', _messages));
    }
  }

  Future<void> deleteMessage(String messageId) async {
    _messages = _messages.where((m) => m.id != messageId).toList();
    notifyListeners();

    final uid = _uid;
    if (uid != null && uid.isNotEmpty) {
      unawaited(_writeCache(uid, _messages));
      try {
        await _collection!.doc(messageId).delete();
      } catch (e) {
        debugPrint('[FaqChatStore] delete message failed: $e');
      }
    } else {
      unawaited(_writeCache('guest', _messages));
    }
  }

  Future<void> deleteAllMessages({bool addWelcome = false}) async {
    final ids = _messages.map((m) => m.id).toList();
    _messages = [];
    FaqChatbotService.instance.resetSession();
    notifyListeners();

    final uid = _uid;
    if (uid != null && uid.isNotEmpty) {
      unawaited(_writeCache(uid, _messages));
      try {
        final batch = _firestore.batch();
        for (final id in ids) {
          batch.delete(_collection!.doc(id));
        }
        await batch.commit();
      } catch (e) {
        debugPrint('[FaqChatStore] delete all failed: $e');
      }
    } else {
      unawaited(_writeCache('guest', _messages));
    }

    if (addWelcome) {
      _seededWelcome = true;
      final chatbot = FaqChatbotService.instance;
      chatbot.resetSession();
      await appendMessage(
        text: chatbot.welcomeFor(null),
        sender: 'ai',
        language: _languageCode(chatbot.sessionLanguage),
        messageType: 'welcome',
      );
    }
  }

  Future<void> startNewChat() => deleteAllMessages(addWelcome: true);

  Future<List<FaqChatMessageRecord>> _readCache(String uid) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_cacheKey(uid));
      if (raw == null || raw.isEmpty) return [];
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .whereType<Map<String, dynamic>>()
          .map(FaqChatMessageRecord.fromJson)
          .where((m) => m.message.isNotEmpty)
          .toList()
        ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    } catch (e) {
      debugPrint('[FaqChatStore] cache read failed: $e');
      return [];
    }
  }

  Future<void> _writeCache(String uid, List<FaqChatMessageRecord> messages) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final encoded = jsonEncode(messages.map((m) => m.toJson()).toList());
      await prefs.setString(_cacheKey(uid), encoded);
    } catch (e) {
      debugPrint('[FaqChatStore] cache write failed: $e');
    }
  }

  String _languageCode(AtmosLanguage lang) {
    return switch (lang) {
      AtmosLanguage.fil => 'fil',
      AtmosLanguage.ceb => 'ceb',
      AtmosLanguage.en => 'en',
    };
  }

  AtmosLanguage languageFromCode(String code) {
    return switch (code.trim().toLowerCase()) {
      'fil' || 'tagalog' || 'filipino' => AtmosLanguage.fil,
      'ceb' || 'bisaya' || 'cebuano' => AtmosLanguage.ceb,
      _ => AtmosLanguage.en,
    };
  }

  void restoreChatbotSession(FaqChatbotService chatbot) {
    for (final message in _messages.reversed) {
      if (message.isUser && message.language.isNotEmpty) {
        chatbot.restoreSessionLanguage(languageFromCode(message.language));
        return;
      }
    }
    for (final message in _messages.reversed) {
      if (!message.isUser && message.language.isNotEmpty) {
        chatbot.restoreSessionLanguage(languageFromCode(message.language));
        return;
      }
    }
  }
}
