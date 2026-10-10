import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/chat_model.dart';
import '../services/auth_service.dart';
import '../services/chat_service.dart';
import '../services/chat_sessions_state.dart';
import '../services/voice_message_service.dart';
import '../theme/app_theme.dart';

class ChatDetailPage extends StatefulWidget {
  final Chat chat;

  const ChatDetailPage({super.key, required this.chat});

  @override
  State<ChatDetailPage> createState() => _ChatDetailPageState();
}

class _ChatDetailPageState extends State<ChatDetailPage> {
  final _inputController = TextEditingController();
  final _scrollController = ScrollController();
  late List<Message> _messages;
  late final VoiceMessageService _voiceService;
  late final ChatService _chatService;
  String? _myUserId;
  bool _loadingMessages = false;
  StreamSubscription<int>? _recordSecondsSubscription;
  late final StreamSubscription<String?> _playingPathSubscription;
  bool _isRecording = false;
  int _recordSeconds = 0;

  bool get _isDatabaseChat => widget.chat.userId.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _messages = [];
    _voiceService = VoiceMessageService();
    _chatService = ChatService();
    _recordSecondsSubscription = _voiceService.recordSecondsStream.listen((s) {
      if (mounted) setState(() => _recordSeconds = s);
    });
    _playingPathSubscription = _voiceService.playingPathStream.listen((_) {
      if (mounted) setState(() {});
    });
    ChatSessionsState.instance.markAsRead(widget.chat.name);
    if (_isDatabaseChat) {
      _loadMessages();
    }
  }

  String _formatTime(DateTime time) {
    final local = time.toLocal();
    final hour12 = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final minute = local.minute.toString().padLeft(2, '0');
    final period = local.hour < 12 ? 'AM' : 'PM';
    return '$hour12:$minute $period';
  }

  Message _toMessage(ChatMessageData data) {
    return Message(
      text: data.text,
      time: _formatTime(data.createdAt),
      isIncoming: _myUserId == null || data.senderId != _myUserId,
      isLocation: data.isLocation,
      isVoice: data.isVoice,
      voiceData: data.voiceData,
      voiceMimeType: data.voiceMimeType,
      voiceDuration: data.voiceDuration,
    );
  }

  Future<void> _loadMessages() async {
    if (!mounted) return;
    setState(() => _loadingMessages = true);
    try {
      final me = await AuthService.getCurrentUser();
      final history = await _chatService.fetchMessages(widget.chat.userId);
      if (!mounted) return;
      setState(() {
        _myUserId = me?['id']?.toString();
        _messages = history.map(_toMessage).toList();
        _loadingMessages = false;
      });
      await _chatService.markRead(widget.chat.userId);
      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingMessages = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    }
  }

  @override
  void dispose() {
    _recordSecondsSubscription?.cancel();
    _playingPathSubscription.cancel();
    _voiceService.dispose();
    _chatService.close();
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  String _nowTime() {
    final now = DateTime.now();
    final hour12 = now.hour % 12 == 0 ? 12 : now.hour % 12;
    final minute = now.minute.toString().padLeft(2, '0');
    final period = now.hour < 12 ? 'AM' : 'PM';
    return '$hour12:$minute $period';
  }

  Future<void> _sendMessage() async {
    final text = _inputController.text.trim();
    if (text.isEmpty) return;
    final message = Message(text: text, time: _nowTime(), isIncoming: false);
    setState(() {
      _messages.add(message);
      _inputController.clear();
    });
    _scrollToBottom();
    ChatSessionsState.instance.updateLastMessage(widget.chat.name, message);
    if (!_isDatabaseChat) return;
    try {
      await _chatService.sendMessage(toUserId: widget.chat.userId, text: text);
    } catch (e) {
      if (!mounted) return;
      setState(() => _messages.remove(message));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    }
  }

  Future<void> _startRecording() async {
    final granted = await _voiceService.startRecording();
    if (!mounted) return;
    if (!granted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Microphone permission is required to record a voice message.'),
        ),
      );
      return;
    }
    setState(() => _isRecording = true);
  }

  Future<void> _stopAndSendRecording() async {
    final voice = await _voiceService.stopRecording();
    if (!mounted) return;
    setState(() => _isRecording = false);
    if (voice == null) return;
    if (voice.durationSeconds < 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Hold on a bit longer — recording is too short.')),
      );
      return;
    }
    final message = Message(
      text: 'Voice message',
      time: _nowTime(),
      isIncoming: false,
      isVoice: true,
      voicePath: voice.path,
      voiceData: voice.dataBase64,
      voiceMimeType: voice.mimeType,
      voiceDuration: voice.durationSeconds,
    );
    setState(() => _messages.add(message));
    _scrollToBottom();
    ChatSessionsState.instance.updateLastMessage(widget.chat.name, message);
    if (!_isDatabaseChat) return;
    try {
      await _chatService.sendMessage(
        toUserId: widget.chat.userId,
        text: 'Voice message',
        isVoice: true,
        voiceData: voice.dataBase64,
        voiceMimeType: voice.mimeType,
        voiceDuration: voice.durationSeconds,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _messages.remove(message));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    }
  }

  Future<void> _cancelRecording() async {
    await _voiceService.cancelRecording();
    if (!mounted) return;
    setState(() => _isRecording = false);
  }

  String? _resolvePlayableSource(Message msg) {
    final path = msg.voicePath;
    if (path != null && !path.startsWith('blob:')) return path;
    final data = msg.voiceData;
    if (data == null) return path;
    return 'data:${msg.voiceMimeType ?? 'audio/mp4'};base64,$data';
  }

  Future<void> _toggleVoice(Message msg) async {
    final source = _resolvePlayableSource(msg);
    if (source == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This voice message is no longer available.')),
      );
      return;
    }
    await _voiceService.togglePlayback(source);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F7F7),
      body: Column(
        children: [
          _buildHeader(context),
          Expanded(child: _buildMessageList()),
          _buildInputBar(),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top),
      color: Colors.white,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back, color: AppTheme.ink),
                  onPressed: () => Navigator.of(context).pop(),
                ),
                CircleAvatar(
                  radius: 20,
                  backgroundColor: const Color(0xFFE8E8E8),
                  child: Icon(
                    widget.chat.isGroup ? Icons.group : Icons.person,
                    color: const Color(0xFF9A9A9A),
                    size: 22,
                  ),
                ),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.chat.name,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.ink,
                      ),
                    ),
                    const Text(
                      'Online',
                      style: TextStyle(fontSize: 12, color: Color(0xFF9A9A9A)),
                    ),
                  ],
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.phone_outlined, color: AppTheme.ink),
                  onPressed: () {},
                ),
                IconButton(
                  icon: const Icon(Icons.videocam_outlined, color: AppTheme.ink),
                  onPressed: () {},
                ),
                IconButton(
                  icon: const Icon(Icons.more_vert, color: AppTheme.ink),
                  onPressed: () {},
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFFE8E8E8)),
        ],
      ),
    );
  }

  Widget _buildMessageList() {
    if (_loadingMessages && _messages.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      itemCount: _messages.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          return _buildDateSeparator();
        }
        final msg = _messages[index - 1];
        if (msg.isLocation) {
          return _buildLocationCard(msg);
        }
        final showAvatar = msg.isIncoming &&
            (index == 1 ||
                index > 1 && _messages[index - 2].isIncoming != msg.isIncoming);
        if (msg.isVoice) {
          return _buildVoiceBubble(msg, showAvatar);
        }
        return _buildMessageBubble(msg, showAvatar);
      },
    );
  }

  Widget _buildDateSeparator() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: const BoxDecoration(
            color: Color(0xFFE8E8E8),
            borderRadius: BorderRadius.all(Radius.circular(12)),
          ),
          child: const Text(
            'May 12, 2025',
            style: TextStyle(fontSize: 12, color: Color(0xFF6F6F6F)),
          ),
        ),
      ),
    );
  }

  Widget _buildMessageBubble(Message msg, bool showAvatar) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisAlignment:
            msg.isIncoming ? MainAxisAlignment.start : MainAxisAlignment.end,
        children: [
          if (msg.isIncoming)
            showAvatar
                ? const Padding(
                    padding: EdgeInsets.only(right: 8),
                    child: CircleAvatar(
                      radius: 14,
                      backgroundColor: Color(0xFFE8E8E8),
                      child: Icon(Icons.person, size: 16, color: Color(0xFF9A9A9A)),
                    ),
                  )
                : const SizedBox(width: 36),
          Flexible(
            child: Column(
              crossAxisAlignment: msg.isIncoming
                  ? CrossAxisAlignment.start
                  : CrossAxisAlignment.end,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: msg.isIncoming
                        ? const Color(0xFFE8E8E8)
                        : Colors.white,
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(18),
                      topRight: const Radius.circular(18),
                      bottomLeft: showAvatar && msg.isIncoming
                          ? const Radius.circular(6)
                          : const Radius.circular(18),
                      bottomRight: const Radius.circular(18),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.04),
                        blurRadius: 4,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                  child: Text(
                    msg.text,
                    style: const TextStyle(
                      fontSize: 15,
                      color: AppTheme.ink,
                      height: 1.3,
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      msg.time,
                      style: const TextStyle(
                          fontSize: 11, color: Color(0xFF9A9A9A)),
                    ),
                    if (!msg.isIncoming) ...[
                      const SizedBox(width: 4),
                      const Icon(Icons.done_all,
                          size: 14, color: Color(0xFF4CAF50)),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLocationCard(Message msg) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(right: 8),
            child: CircleAvatar(
              radius: 14,
              backgroundColor: Color(0xFFE8E8E8),
              child: Icon(Icons.group, size: 16, color: Color(0xFF9A9A9A)),
            ),
          ),
          Flexible(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(18),
                  topRight: Radius.circular(18),
                  bottomLeft: Radius.circular(6),
                  bottomRight: Radius.circular(18),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              child: Row(
                children: [
                  const Icon(Icons.location_on,
                      color: Color(0xFF4CAF50), size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Location',
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.ink)),
                        const SizedBox(height: 2),
                        Text(msg.text,
                            style: const TextStyle(
                                fontSize: 14, color: AppTheme.ink)),
                        const SizedBox(height: 2),
                        const Text('Updated 2 hours ago',
                            style: TextStyle(
                                fontSize: 11, color: Color(0xFF9A9A9A))),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      color: const Color(0xFFE8E8E8),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.map,
                        color: Color(0xFF9A9A9A), size: 28),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInputBar() {
    if (_isRecording) {
      return _buildRecordingBar();
    }
    final hasText = _inputController.text.isNotEmpty;
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(
          top: BorderSide(color: Color(0xFFE8E8E8), width: 1),
        ),
      ),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).padding.bottom + 4,
        left: 8,
        right: 8,
        top: 8,
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.add_circle_outline,
                color: Color(0xFF9A9A9A)),
            onPressed: () {},
          ),
          Expanded(
            child: Container(
              height: 40,
              decoration: BoxDecoration(
                color: const Color(0xFFF0F1F3),
                borderRadius: BorderRadius.circular(20),
              ),
              child: TextField(
                controller: _inputController,
                onChanged: (_) => setState(() {}),
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _sendMessage(),
                decoration: const InputDecoration(
                  hintText: 'Message...',
                  hintStyle:
                      TextStyle(color: Color(0xFF9A9A9A), fontSize: 15),
                  border: InputBorder.none,
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                ),
              ),
            ),
          ),
          if (hasText)
            IconButton(
              icon: const Icon(Icons.send, color: AppTheme.ink),
              onPressed: _sendMessage,
            )
          else
            IconButton(
              icon: const Icon(Icons.mic, color: Color(0xFF9A9A9A)),
              onPressed: _startRecording,
            ),
        ],
      ),
    );
  }

  Widget _buildRecordingBar() {
    final minutes = (_recordSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (_recordSeconds % 60).toString().padLeft(2, '0');
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(
          top: BorderSide(color: Color(0xFFE8E8E8), width: 1),
        ),
      ),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).padding.bottom + 4,
        left: 8,
        right: 8,
        top: 8,
      ),
      child: Row(
        children: [
          const SizedBox(width: 6),
          const _RecordingDot(),
          const SizedBox(width: 10),
          Text(
            '$minutes:$seconds',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppTheme.ink,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Recording voice message...',
              style: TextStyle(fontSize: 14, color: Color(0xFF9A9A9A)),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, color: Color(0xFF9A9A9A)),
            tooltip: 'Discard recording',
            onPressed: _cancelRecording,
          ),
          IconButton(
            icon: const Icon(Icons.send, color: AppTheme.ink),
            tooltip: 'Send voice message',
            onPressed: _stopAndSendRecording,
          ),
        ],
      ),
    );
  }

  Widget _buildVoiceBubble(Message msg, bool showAvatar) {
    final activeSource = _resolvePlayableSource(msg);
    final isPlayingThis = activeSource != null &&
        _voiceService.isPlaying &&
        _voiceService.playingPath == activeSource;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisAlignment:
            msg.isIncoming ? MainAxisAlignment.start : MainAxisAlignment.end,
        children: [
          if (msg.isIncoming)
            showAvatar
                ? const Padding(
                    padding: EdgeInsets.only(right: 8),
                    child: CircleAvatar(
                      radius: 14,
                      backgroundColor: Color(0xFFE8E8E8),
                      child: Icon(Icons.person, size: 16, color: Color(0xFF9A9A9A)),
                    ),
                  )
                : const SizedBox(width: 36),
          Flexible(
            child: Column(
              crossAxisAlignment: msg.isIncoming
                  ? CrossAxisAlignment.start
                  : CrossAxisAlignment.end,
              children: [
                GestureDetector(
                  onTap: () => _toggleVoice(msg),
                  child: Container(
                    constraints: const BoxConstraints(minWidth: 120),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: msg.isIncoming
                          ? const Color(0xFFE8E8E8)
                          : Colors.white,
                      borderRadius: BorderRadius.only(
                        topLeft: const Radius.circular(18),
                        topRight: const Radius.circular(18),
                        bottomLeft: showAvatar && msg.isIncoming
                            ? const Radius.circular(6)
                            : const Radius.circular(18),
                        bottomRight: const Radius.circular(18),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.04),
                          blurRadius: 4,
                          offset: const Offset(0, 1),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isPlayingThis
                              ? Icons.pause_circle_filled
                              : Icons.play_circle_filled,
                          size: 26,
                          color: AppTheme.ink,
                        ),
                        const SizedBox(width: 8),
                        VoiceWaveBars(active: isPlayingThis),
                        const SizedBox(width: 8),
                        Text(
                          '${msg.voiceDuration}"',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.ink,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      msg.time,
                      style: const TextStyle(
                          fontSize: 11, color: Color(0xFF9A9A9A)),
                    ),
                    if (!msg.isIncoming) ...[
                      const SizedBox(width: 4),
                      const Icon(Icons.done_all,
                          size: 14, color: Color(0xFF4CAF50)),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RecordingDot extends StatefulWidget {
  const _RecordingDot();

  @override
  State<_RecordingDot> createState() => _RecordingDotState();
}

class _RecordingDotState extends State<_RecordingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(begin: 0.3, end: 1).animate(_controller),
      child: Container(
        width: 12,
        height: 12,
        decoration: const BoxDecoration(
          color: Color(0xFFE5484D),
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

class VoiceWaveBars extends StatefulWidget {
  final bool active;

  const VoiceWaveBars({super.key, required this.active});

  @override
  State<VoiceWaveBars> createState() => _VoiceWaveBarsState();
}

class _VoiceWaveBarsState extends State<VoiceWaveBars>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  static const _barPhases = [0.0, 0.6, 1.2, 0.3, 0.9];

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    if (widget.active) _controller.repeat();
  }

  @override
  void didUpdateWidget(VoiceWaveBars oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active == oldWidget.active) return;
    if (widget.active) {
      _controller.repeat();
    } else {
      _controller
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            for (final phase in _barPhases)
              Container(
                width: 3,
                height: widget.active
                    ? 6 +
                        10 *
                            (0.5 +
                                0.5 *
                                    math.sin(
                                        _controller.value * 2 * math.pi * 2 +
                                            phase))
                    : 10.0,
                margin: const EdgeInsets.symmetric(horizontal: 1.5),
                decoration: BoxDecoration(
                  color: const Color(0xFF6F6F6F),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
          ],
        );
      },
    );
  }
}
