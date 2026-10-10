import 'package:flutter/material.dart';

import '../models/chat_model.dart';
import '../services/chat_service.dart';
import '../widgets/chat_widgets.dart';
import 'chat_detail_page.dart';
import 'community_page.dart';
import 'family_page.dart';
import 'find_friends_page.dart';
import 'friend_requests_page.dart';
import 'profile_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({this.initialTabIndex = 0, super.key});

  final int initialTabIndex;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late int _navIndex;
  String _selectedTab = 'All';

  final ChatService _chatService = ChatService();
  List<Chat> _chats = [];
  bool _loadingChats = true;
  String? _chatsError;
  int _requestCount = 0;

  @override
  void initState() {
    super.initState();
    _navIndex = widget.initialTabIndex;
    _loadConversations();
    _loadRequestCount();
  }

  @override
  void dispose() {
    _chatService.close();
    super.dispose();
  }

  Future<void> _loadConversations({bool silent = false}) async {
    if (!mounted) return;
    if (silent && _chats.isNotEmpty) {
      try {
        final conversations = await _chatService.fetchConversations();
        if (!mounted) return;
        setState(() => _chats = conversations.map(_toChat).toList());
      } catch (_) {}
      return;
    }
    setState(() {
      _loadingChats = true;
      _chatsError = null;
    });
    try {
      final conversations = await _chatService.fetchConversations();
      if (!mounted) return;
      setState(() {
        _chats = conversations.map(_toChat).toList();
        _loadingChats = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingChats = false;
        _chatsError = e.toString();
      });
    }
  }

  Future<void> _loadRequestCount() async {
    try {
      final summary = await _chatService.fetchFriends();
      if (!mounted) return;
      setState(() => _requestCount = summary.incoming.length);
    } catch (_) {}
  }

  Future<void> _openFriendRequests() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const FriendRequestsPage()),
    );
    if (!mounted) return;
    await _loadRequestCount();
    await _loadConversations();
  }

  Chat _toChat(ChatConversation conversation) {
    final last = conversation.lastMessage;
    String preview = 'No messages yet';
    if (last != null) {
      if (last.isVoice) {
        preview = 'Voice message';
      } else if (last.isLocation) {
        preview = 'Location';
      } else {
        preview = last.text;
      }
    }
    return Chat(
      userId: conversation.user.id,
      name: conversation.user.fullName,
      time: _formatListTime(last?.createdAt),
      unreadCount: conversation.unreadCount,
      preview: preview,
    );
  }

  String _formatListTime(DateTime? time) {
    if (time == null) return '';
    final local = time.toLocal();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(local.year, local.month, local.day);
    if (!day.isBefore(today)) {
      final hour12 = local.hour % 12 == 0 ? 12 : local.hour % 12;
      final minute = local.minute.toString().padLeft(2, '0');
      return '${local.hour < 12 ? 'AM' : 'PM'} $hour12:$minute';
    }
    if (day == today.subtract(const Duration(days: 1))) return 'Yesterday';
    final diff = today.difference(day).inDays;
    if (diff < 7) {
      const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      return weekdays[local.weekday - 1];
    }
    return '${local.month}/${local.day}';
  }

  List<Chat> get _filteredChats {
    return _chats.where((c) {
      if (_selectedTab == 'Friends') return !c.isGroup;
      if (_selectedTab == 'Groups') return c.isGroup;
      return true;
    }).toList();
  }

  void _openFindFriends() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const FindFriendsPage()));
  }

  void _openChat(Chat chat) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => ChatDetailPage(chat: chat)));
  }

  void _onNavSelected(int i) {
    setState(() => _navIndex = i);
    if (i == 0) {
      _loadRequestCount();
      _loadConversations(silent: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_navIndex == 1) {
      return Scaffold(
        backgroundColor: Colors.white,
        body: const CommunityPage(),
        bottomNavigationBar: BottomNav(
          selectedIndex: _navIndex,
          onSelected: _onNavSelected,
        ),
      );
    }

    if (_navIndex == 2) {
      return Scaffold(
        backgroundColor: Colors.white,
        body: const FamilyPage(),
        bottomNavigationBar: BottomNav(
          selectedIndex: _navIndex,
          onSelected: _onNavSelected,
        ),
      );
    }

    if (_navIndex == 3) {
      return Scaffold(
        backgroundColor: Colors.white,
        body: const ProfilePage(),
        bottomNavigationBar: BottomNav(
          selectedIndex: _navIndex,
          onSelected: _onNavSelected,
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        children: [
          Navbar(
            notificationCount: _requestCount,
            onNotificationTap: _openFriendRequests,
          ),
          const MessagesHeader(),
          _SearchBarButton(onTap: _openFindFriends),
          CategoryTabs(
            selected: _selectedTab,
            onSelected: (t) => setState(() => _selectedTab = t),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _loadConversations,
              child: _buildChatArea(),
            ),
          ),
        ],
      ),
      bottomNavigationBar: BottomNav(
        selectedIndex: _navIndex,
        onSelected: _onNavSelected,
      ),
    );
  }

  Widget _buildChatArea() {
    if (_loadingChats) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: CircularProgressIndicator(),
        ),
      );
    }
    if (_chatsError != null) {
      return ListView(
        padding: const EdgeInsets.symmetric(vertical: 32),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              _chatsError!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFF9A9A9A), fontSize: 14),
            ),
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: _loadConversations,
            child: const Text('Retry'),
          ),
        ],
      );
    }
    if (_filteredChats.isEmpty) {
      return ListView(
        padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 32),
        children: const [
          Icon(Icons.chat_bubble_outline, size: 56, color: Color(0xFFB7BBC1)),
          SizedBox(height: 16),
          Text(
            'No conversations yet',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: Color(0xFF777777),
            ),
          ),
          SizedBox(height: 8),
          Text(
            'Search for friends by their Google email using the search bar above, '
            'then start chatting.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Color(0xFF9A9A9A), fontSize: 13, height: 1.4),
          ),
        ],
      );
    }
    return ChatList(
      chats: _filteredChats,
      onChatTap: (chat) {
        _openChat(chat);
      },
    );
  }
}

class _SearchBarButton extends StatelessWidget {
  final VoidCallback onTap;
  const _SearchBarButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: 40,
          decoration: BoxDecoration(
            color: const Color(0xFFF0F1F3),
            borderRadius: BorderRadius.circular(20),
          ),
          child: const Row(
            children: [
              Padding(
                padding: EdgeInsets.only(left: 14),
                child: Icon(Icons.search, color: Color(0xFF9A9A9A), size: 20),
              ),
              SizedBox(width: 8),
              Text(
                'Search',
                style: TextStyle(color: Color(0xFF9A9A9A), fontSize: 15),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
