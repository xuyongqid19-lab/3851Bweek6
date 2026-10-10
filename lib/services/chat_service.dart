import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'auth_service.dart';

class ChatApiException implements Exception {
  const ChatApiException(this.message, [this.status]);

  final String message;
  final int? status;

  @override
  String toString() => message;
}

class ChatUser {
  const ChatUser({
    required this.id,
    required this.fullName,
    this.username,
    this.email,
    this.googlePhotoUrl,
    this.interest,
    this.authProvider,
  });

  final String id;
  final String fullName;
  final String? username;
  final String? email;
  final String? googlePhotoUrl;
  final String? interest;
  final String? authProvider;

  factory ChatUser.fromJson(Map<String, dynamic> json) {
    return ChatUser(
      id: json['id']?.toString() ?? json['user_id']?.toString() ?? '',
      fullName: json['fullName']?.toString() ?? '',
      username: json['username']?.toString(),
      email: json['email']?.toString(),
      googlePhotoUrl: json['googlePhotoUrl']?.toString(),
      interest: json['interest']?.toString(),
      authProvider: json['authProvider']?.toString(),
    );
  }
}

class ChatConversation {
  const ChatConversation({
    required this.user,
    this.lastMessage,
    this.unreadCount = 0,
  });

  final ChatUser user;
  final ChatMessageData? lastMessage;
  final int unreadCount;

  factory ChatConversation.fromJson(Map<String, dynamic> json) {
    final last = json['lastMessage'];
    return ChatConversation(
      user: ChatUser.fromJson(
        Map<String, dynamic>.from(json['user'] as Map),
      ),
      lastMessage: last is Map<String, dynamic>
          ? ChatMessageData.fromJson(Map<String, dynamic>.from(last))
          : null,
      unreadCount: (json['unreadCount'] as num?)?.toInt() ?? 0,
    );
  }
}

class ChatMessageData {
  const ChatMessageData({
    required this.id,
    required this.senderId,
    required this.contentType,
    required this.text,
    this.voiceData,
    this.voiceMimeType,
    this.voiceDuration = 0,
    required this.createdAt,
  });

  final String id;
  final String senderId;
  final String contentType;
  final String text;
  final String? voiceData;
  final String? voiceMimeType;
  final int voiceDuration;
  final DateTime createdAt;

  bool get isVoice => contentType == 'voice';
  bool get isLocation => contentType == 'location';
  bool get fromMe => senderId == _currentUserId;

  static String? _currentUserId;

  static void setCurrentUser(String? userId) => _currentUserId = userId;

  factory ChatMessageData.fromJson(Map<String, dynamic> json) {
    return ChatMessageData(
      id: json['id']?.toString() ?? '',
      senderId: json['senderId']?.toString() ?? '',
      contentType: json['contentType']?.toString() ?? 'text',
      text: json['text']?.toString() ?? '',
      voiceData: json['voiceData']?.toString(),
      voiceMimeType: json['voiceMimeType']?.toString(),
      voiceDuration: (json['voiceDuration'] as num?)?.toInt() ?? 0,
      createdAt:
          DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
          DateTime.now(),
    );
  }
}

class ChatFriendRequest {
  const ChatFriendRequest({
    required this.user,
    this.message,
    this.createdAt,
  });

  final ChatUser user;
  final String? message;
  final DateTime? createdAt;

  factory ChatFriendRequest.fromJson(Map<String, dynamic> json) {
    return ChatFriendRequest(
      user: ChatUser.fromJson(json),
      message: json['message']?.toString(),
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? ''),
    );
  }
}

class ChatFriendSummary {
  const ChatFriendSummary({
    required this.friends,
    required this.incoming,
    required this.outgoing,
  });

  final List<ChatUser> friends;
  final List<ChatFriendRequest> incoming;
  final List<ChatUser> outgoing;
}

class ChatService {
  ChatService({http.Client? client, String? baseUrl})
      : _client = client ?? http.Client(),
        _baseUrl = baseUrl ?? defaultBaseUrl;

  static String get defaultBaseUrl {
    const configured = String.fromEnvironment('CHAT_API_BASE_URL');
    return configured.isNotEmpty
        ? configured
        : kIsWeb
            ? 'http://localhost:3004'
            : 'http://10.0.2.2:3004';
  }

  final http.Client _client;
  final String _baseUrl;

  void close() => _client.close();

  Future<Map<String, dynamic>> _request(
    String method,
    String path, [
    Map<String, dynamic>? data,
  ]) async {
    try {
      final headers = await AuthService.authHeaders(json: true);
      final request = http.Request(method, Uri.parse('$_baseUrl$path'))
        ..headers.addAll(headers);
      if (data != null) request.body = jsonEncode(data);
      final response = await _client
          .send(request)
          .then(http.Response.fromStream)
          .timeout(const Duration(seconds: 15));
      Map<String, dynamic> body;
      try {
        body = Map<String, dynamic>.from(jsonDecode(response.body) as Map);
      } catch (_) {
        throw const ChatApiException(
            'Chat service returned an invalid response. Please retry.');
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw ChatApiException(
          body['error']?.toString() ?? 'Chat request failed.',
          response.statusCode,
        );
      }
      return body;
    } on AuthException catch (e) {
      throw ChatApiException(e.message, 401);
    } on ChatApiException {
      rethrow;
    } on TimeoutException {
      throw const ChatApiException('Chat service timed out. Please retry.');
    } catch (_) {
      throw const ChatApiException(
          'Cannot reach the chat service. Check your connection and try again.');
    }
  }

  Future<String> sendFriendRequest(ChatUser target, String message) async {
    final body = await _request('POST', '/chat/friends/requests', {
      'userId': target.id,
      'fullName': target.fullName,
      'username': target.username,
      'email': target.email,
      'googlePhotoUrl': target.googlePhotoUrl,
      'interest': target.interest,
      'authProvider': target.authProvider,
      'message': message,
    });
    return body['status']?.toString() ?? 'pending';
  }

  Future<void> acceptFriendRequest(String userId) async {
    await _request('POST', '/chat/friends/accepts', {'userId': userId});
  }

  Future<void> declineFriendRequest(String userId) async {
    await _request('POST', '/chat/friends/declines', {'userId': userId});
  }

  Future<ChatFriendSummary> fetchFriends() async {
    final body = await _request('GET', '/chat/friends');
    List<ChatUser> parse(String key) {
      final list = body[key];
      if (list is! List) return const [];
      return list
          .whereType<Map>()
          .map((m) => ChatUser.fromJson(Map<String, dynamic>.from(m)))
          .toList();
    }

    final requests = (body['incoming'] as List? ?? const [])
        .whereType<Map>()
        .map((m) =>
            ChatFriendRequest.fromJson(Map<String, dynamic>.from(m)))
        .toList();

    return ChatFriendSummary(
      friends: parse('friends'),
      incoming: requests,
      outgoing: parse('outgoing'),
    );
  }

  Future<List<ChatConversation>> fetchConversations() async {
    final body = await _request('GET', '/chat/conversations');
    final list = body['conversations'];
    if (list is! List) return const [];
    return list
        .whereType<Map>()
        .map((m) => ChatConversation.fromJson(Map<String, dynamic>.from(m)))
        .toList();
  }

  Future<List<ChatMessageData>> fetchMessages(String userId) async {
    final body = await _request('GET', '/chat/messages/$userId');
    final list = body['messages'];
    if (list is! List) return const [];
    return list
        .whereType<Map>()
        .map((m) => ChatMessageData.fromJson(Map<String, dynamic>.from(m)))
        .toList();
  }

  Future<ChatMessageData> sendMessage({
    required String toUserId,
    required String text,
    bool isLocation = false,
    bool isVoice = false,
    String? voiceData,
    String? voiceMimeType,
    int voiceDuration = 0,
  }) async {
    final body = await _request('POST', '/chat/messages', {
      'toUserId': toUserId,
      'text': text,
      'isLocation': isLocation,
      'isVoice': isVoice,
      'voiceData': voiceData,
      'voiceMimeType': voiceMimeType,
      'voiceDuration': voiceDuration,
    });
    final message = body['message'];
    if (message is! Map) {
      throw const ChatApiException('Chat service returned an invalid response.');
    }
    return ChatMessageData.fromJson(Map<String, dynamic>.from(message));
  }

  Future<void> markRead(String userId) async {
    await _request('POST', '/chat/messages/$userId/read');
  }
}
