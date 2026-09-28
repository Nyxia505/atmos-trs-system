import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:atmos_trs_system/config/app_theme.dart';
import 'package:atmos_trs_system/config/atmos_brand_typography.dart';
import 'package:atmos_trs_system/data/app_faq_content.dart';
import 'package:atmos_trs_system/features/navigation/tourist_web_layout.dart';
import 'package:atmos_trs_system/models/faq_chat_message_record.dart';
import 'package:atmos_trs_system/services/faq_chat_store.dart';
import 'package:atmos_trs_system/services/faq_chatbot_service.dart';
import 'package:atmos_trs_system/widgets/tourist_full_page.dart';

const Color _kDarkText = Color(0xFF111827);

/// Opens the app FAQ chatbot as a full-screen page (mobile) or centered panel.
void openAppFaq(
  BuildContext context, {
  bool fullScreen = false,
  bool centeredPanel = false,
  double maxPanelWidth = 480,
}) {
  final sheet = AppFaqSheet(
    fullScreen: fullScreen,
    centeredPanel: centeredPanel,
  );

  if (fullScreen) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(fullscreenDialog: true, builder: (_) => sheet),
    );
    return;
  }

  if (centeredPanel) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      builder: (context) => Center(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
          constraints: BoxConstraints(
            maxWidth: maxPanelWidth,
            maxHeight: MediaQuery.sizeOf(context).height * 0.85,
          ),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.12),
                blurRadius: 24,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: sheet,
        ),
      ),
    );
    return;
  }

  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => Container(
      height: MediaQuery.sizeOf(context).height * 0.85,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      clipBehavior: Clip.antiAlias,
      child: sheet,
    ),
  );
}

class AppFaqSheet extends StatelessWidget {
  const AppFaqSheet({
    super.key,
    this.fullScreen = false,
    this.centeredPanel = false,
  });

  final bool fullScreen;
  final bool centeredPanel;

  @override
  Widget build(BuildContext context) {
    return _FaqChatBody(
      accent: AppTheme.primary,
      centeredPanel: centeredPanel,
      fullScreen: fullScreen,
    );
  }
}

class _FaqChatBody extends StatefulWidget {
  const _FaqChatBody({
    required this.accent,
    required this.centeredPanel,
    required this.fullScreen,
  });

  final Color accent;
  final bool centeredPanel;
  final bool fullScreen;

  @override
  State<_FaqChatBody> createState() => _FaqChatBodyState();
}

class _FaqChatBodyState extends State<_FaqChatBody> {
  final _chatbot = FaqChatbotService.instance;
  final _store = FaqChatStore.instance;
  final _inputController = TextEditingController();
  final _scrollController = ScrollController();
  final _focusNode = FocusNode();
  bool _isTyping = false;

  @override
  void initState() {
    super.initState();
    _store.addListener(_onStoreChanged);
    unawaited(_initializeChat());
  }

  Future<void> _initializeChat() async {
    await _store.bindUser();
    _store.restoreChatbotSession(_chatbot);
    if (mounted) {
      setState(() {});
      _scrollToBottom();
    }
  }

  void _onStoreChanged() {
    if (!mounted) return;
    setState(() {});
    _scrollToBottom();
  }

  @override
  void dispose() {
    _store.removeListener(_onStoreChanged);
    _inputController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _sendMessage([String? preset]) async {
    final text = (preset ?? _inputController.text).trim();
    if (text.isEmpty || _isTyping) return;

    setState(() => _isTyping = true);
    if (preset == null) _inputController.clear();

    final userLang = _languageCode(_chatbot.languageFor(text));
    await _store.appendMessage(
      text: text,
      sender: 'user',
      language: userLang,
    );
    _scrollToBottom();

    await Future<void>.delayed(const Duration(milliseconds: 450));

    final reply = _chatbot.replyTo(text);
    if (!mounted) return;

    await _store.appendMessage(
      text: reply,
      sender: 'ai',
      language: _languageCode(_chatbot.sessionLanguage),
    );

    if (!mounted) return;
    setState(() => _isTyping = false);
    _scrollToBottom();
  }

  String _languageCode(AtmosLanguage lang) {
    return switch (lang) {
      AtmosLanguage.fil => 'fil',
      AtmosLanguage.ceb => 'ceb',
      AtmosLanguage.en => 'en',
    };
  }

  Future<void> _confirmDeleteMessage(FaqChatMessageRecord message) async {
    final confirmed = await showTouristDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete message?'),
        content: const Text('This message will be removed from your chat history.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _store.deleteMessage(message.id);
  }

  Future<void> _openFaqBrowse() async {
    final accent = widget.accent;
    if (widget.fullScreen) {
      final question = await pushTouristFullPage<String>(
        context,
        _FaqBrowsePage(accent: accent),
      );
      if (question != null && mounted) unawaited(_sendMessage(question));
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final height = MediaQuery.sizeOf(sheetContext).height * 0.72;
        return Container(
          height: height,
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 10),
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 8, 8),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.help_outline_rounded,
                        color: accent,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Frequently asked',
                            style: AtmosBrandTypography.meaningTagline(
                              color: _kDarkText,
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            'Tap a question to ask Tala',
                            style: AtmosBrandTypography.meaningTagline(
                              color: AppTheme.unselectedMuted,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(sheetContext),
                      icon: Icon(Icons.close, color: Colors.grey.shade600),
                      tooltip: 'Close',
                    ),
                  ],
                ),
              ),
              Divider(height: 1, color: Colors.grey.shade200),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                  itemCount: kAppFaqItems.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 4),
                  itemBuilder: (context, index) {
                    final item = kAppFaqItems[index];
                    return _FaqBrowseTile(
                      item: item,
                      accent: accent,
                      onAsk: () {
                        Navigator.pop(sheetContext);
                        unawaited(_sendMessage(item.question));
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!widget.fullScreen) _buildHeader(),
        Expanded(child: _buildChat()),
      ],
    );

    if (!widget.fullScreen) return content;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        leadingWidth: 80,
        leading: Padding(
          padding: const EdgeInsets.only(left: 12),
          child: Center(
            child: FilledButton(
              onPressed: () => Navigator.pop(context),
              style: FilledButton.styleFrom(
                backgroundColor: widget.accent,
                foregroundColor: AppTheme.onPrimary,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                minimumSize: const Size(0, 36),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: const Text(
                'Back',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ),
        title: Text(
          FaqChatbotService.botName,
          style: AtmosBrandTypography.meaningTagline(
            color: _kDarkText,
            fontSize: 18,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.2,
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Center(
              child: _FaqHelpCircleButton(
                accent: widget.accent,
                onPressed: _openFaqBrowse,
              ),
            ),
          ),
          const _FaqChatMenuButton(),
        ],
      ),
      body: SafeArea(child: content),
    );
  }

  Widget _buildHeader() {
    final help = _FaqHelpCircleButton(
      accent: widget.accent,
      onPressed: _openFaqBrowse,
    );

    if (widget.centeredPanel) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 8, 8),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: widget.accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                Icons.smart_toy_outlined,
                color: widget.accent,
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    FaqChatbotService.botName,
                    style: AtmosBrandTypography.meaningTagline(
                      color: _kDarkText,
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.2,
                    ),
                  ),
                  Text(
                    'Tourism & ATMOS-TRS app assistant',
                    style: AtmosBrandTypography.meaningTagline(
                      color: AppTheme.unselectedMuted,
                      fontSize: 12,
                      letterSpacing: 0.15,
                    ),
                  ),
                ],
              ),
            ),
            help,
            IconButton(
              onPressed: () => Navigator.pop(context),
              icon: Icon(Icons.close, color: Colors.grey.shade600),
              tooltip: 'Close',
            ),
            const _FaqChatMenuButton(),
          ],
        ),
      );
    }

    return Column(
      children: [
        Container(
          margin: const EdgeInsets.only(top: 12),
          width: 40,
          height: 4,
          decoration: BoxDecoration(
            color: Colors.grey.shade300,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 12, 8),
          child: Row(
            children: [
              Icon(Icons.smart_toy_outlined, color: widget.accent, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  FaqChatbotService.botName,
                  style: AtmosBrandTypography.meaningTagline(
                    color: _kDarkText,
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              help,
              const SizedBox(width: 4),
              const _FaqChatMenuButton(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildChat() {
    final messages = _store.messages;

    if (_store.isLoading && messages.isEmpty) {
      return Center(
        child: CircularProgressIndicator(color: widget.accent),
      );
    }

    return Column(
      children: [
        Expanded(
          child: messages.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'No messages yet. Say hi to Tala AI!',
                      textAlign: TextAlign.center,
                      style: AtmosBrandTypography.meaningTagline(
                        color: AppTheme.unselectedMuted,
                        fontSize: 14,
                        height: 1.45,
                      ),
                    ),
                  ),
                )
              : ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  itemCount: messages.length + (_isTyping ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (_isTyping && index == messages.length) {
                      return _TypingBubble(accent: widget.accent);
                    }
                    final message = messages[index];
                    return _ChatBubble(
                      message: message,
                      accent: widget.accent,
                      onLongPress: () => _confirmDeleteMessage(message),
                    );
                  },
                ),
        ),
        _buildSuggestionChips(),
        _buildInputBar(),
      ],
    );
  }

  Widget _buildSuggestionChips() {
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
        itemCount: FaqChatbotService.suggestedQuestions.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final question = FaqChatbotService.suggestedQuestions[index];
          return ActionChip(
            label: Text(
              question,
              style: AtmosBrandTypography.meaningTagline(
                color: widget.accent,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
            backgroundColor: widget.accent.withValues(alpha: 0.08),
            side: BorderSide(color: widget.accent.withValues(alpha: 0.25)),
            onPressed: _isTyping ? null : () => _sendMessage(question),
          );
        },
      ),
    );
  }

  Widget _buildInputBar() {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _inputController,
                focusNode: _focusNode,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _sendMessage(),
                decoration: InputDecoration(
                  hintText: '',
                  filled: true,
                  fillColor: AppTheme.scaffoldBackground,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide(
                      color: Colors.grey.shade300,
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide(color: widget.accent, width: 1.5),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Material(
              color: widget.accent,
              borderRadius: BorderRadius.circular(24),
              child: InkWell(
                borderRadius: BorderRadius.circular(24),
                onTap: _isTyping ? null : () => _sendMessage(),
                child: const SizedBox(
                  width: 48,
                  height: 48,
                  child: Icon(Icons.send_rounded, color: Colors.white, size: 22),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Compact help circle — opens the FAQ list without competing with chat.
class _FaqHelpCircleButton extends StatelessWidget {
  const _FaqHelpCircleButton({
    required this.accent,
    required this.onPressed,
  });

  final Color accent;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'FAQ',
      child: Material(
        color: accent.withValues(alpha: 0.12),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: SizedBox(
            width: 36,
            height: 36,
            child: Icon(
              Icons.question_mark_rounded,
              size: 18,
              color: accent,
            ),
          ),
        ),
      ),
    );
  }
}

class _FaqChatMenuButton extends StatelessWidget {
  const _FaqChatMenuButton();

  Future<void> _confirmNewChat(BuildContext context) async {
    final confirmed = await showTouristDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Start new chat?'),
        content: const Text(
          'Your current conversation will be cleared and a fresh chat will begin.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('New chat'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await FaqChatStore.instance.startNewChat();
  }

  Future<void> _confirmDeleteConversation(BuildContext context) async {
    final confirmed = await showTouristDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete conversation?'),
        content: const Text(
          'All messages will be permanently removed. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete all'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await FaqChatStore.instance.deleteAllMessages(addWelcome: false);
  }

  @override
  Widget build(BuildContext context) {
    final accent = AppTheme.primary;
    return PopupMenuButton<String>(
      icon: Icon(Icons.more_vert_rounded, color: Colors.grey.shade700),
      tooltip: 'Chat options',
      onSelected: (value) {
        switch (value) {
          case 'new_chat':
            unawaited(_confirmNewChat(context));
          case 'delete_all':
            unawaited(_confirmDeleteConversation(context));
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          value: 'new_chat',
          child: Row(
            children: [
              Icon(Icons.add_comment_outlined, size: 20, color: accent),
              const SizedBox(width: 10),
              const Text('New chat'),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'delete_all',
          child: Row(
            children: [
              Icon(Icons.delete_outline_rounded, size: 20, color: Colors.red.shade700),
              const SizedBox(width: 10),
              Text(
                'Delete conversation',
                style: TextStyle(color: Colors.red.shade700),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ChatBubble extends StatelessWidget {
  const _ChatBubble({
    required this.message,
    required this.accent,
    required this.onLongPress,
  });

  final FaqChatMessageRecord message;
  final Color accent;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final isUser = message.isUser;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isUser) ...[
            CircleAvatar(
              radius: 16,
              backgroundColor: accent.withValues(alpha: 0.12),
              child: Icon(Icons.smart_toy_outlined, size: 18, color: accent),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onLongPress: onLongPress,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: Radius.circular(isUser ? 16 : 4),
                  bottomRight: Radius.circular(isUser ? 4 : 16),
                ),
                child: Ink(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: isUser
                        ? accent
                        : AppTheme.scaffoldBackground,
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(16),
                      topRight: const Radius.circular(16),
                      bottomLeft: Radius.circular(isUser ? 16 : 4),
                      bottomRight: Radius.circular(isUser ? 4 : 16),
                    ),
                    border: isUser
                        ? null
                        : Border.all(color: Colors.grey.shade200),
                  ),
                  child: isUser
                      ? Text(
                          message.message,
                          style: AtmosBrandTypography.meaningTagline(
                            color: Colors.white,
                            fontSize: 14,
                            height: 1.45,
                            letterSpacing: 0.15,
                          ),
                        )
                      : _FaqBotMessageText(text: message.message),
                ),
              ),
            ),
          ),
          if (isUser) const SizedBox(width: 4),
        ],
      ),
    );
  }
}

class _FaqBotMessageText extends StatelessWidget {
  const _FaqBotMessageText({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      color: _kDarkText,
      fontSize: 14,
      height: 1.5,
      fontWeight: FontWeight.w500,
      letterSpacing: 0.1,
    );
    final lines = text.replaceAll('\r\n', '\n').split('\n');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < lines.length; i++)
          if (lines[i].trim().isEmpty)
            const SizedBox(height: 8)
          else if (lines[i].trim().startsWith('────'))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Divider(
                height: 1,
                thickness: 1,
                color: Colors.grey.shade300,
              ),
            )
          else if (_isBulletLine(lines[i]))
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '•  ',
                    style: style.copyWith(fontWeight: FontWeight.w700),
                  ),
                  Expanded(
                    child: Text(
                      _bulletBody(lines[i]),
                      style: style,
                    ),
                  ),
                ],
              ),
            )
          else
            Padding(
              padding: EdgeInsets.only(
                bottom: _isSectionHeader(lines[i]) ? 2 : 0,
              ),
              child: Text(
                lines[i],
                style: style.copyWith(
                  fontWeight: (_isHotelTitleLine(lines[i]) ||
                          _isSectionHeader(lines[i]))
                      ? FontWeight.w700
                      : FontWeight.w500,
                  fontSize: _isHotelTitleLine(lines[i]) ? 14.5 : 14,
                  color: (_isHotelTitleLine(lines[i]) ||
                          _isSectionHeader(lines[i]))
                      ? const Color(0xFF1F2937)
                      : _kDarkText,
                ),
              ),
            ),
      ],
    );
  }

  bool _isBulletLine(String line) {
    final t = line.trimLeft();
    // Numbered steps stay as title lines (1. 2. 3.) — only bullet markers here.
    return t.startsWith('• ') || t.startsWith('- ') || t.startsWith('* ');
  }

  String _bulletBody(String line) {
    final t = line.trimLeft();
    if (t.startsWith('• ')) return t.substring(2).trimLeft();
    if (t.startsWith('- ') || t.startsWith('* ')) {
      return t.substring(2).trimLeft();
    }
    return t;
  }

  bool _isSectionHeader(String line) {
    final t = line.trim();
    if (t.isEmpty || t.length > 42) return false;
    if (_isBulletLine(t)) return false;
    return t.endsWith(':');
  }

  bool _isHotelTitleLine(String line) {
    final t = line.trim();
    if (t.isEmpty) return false;
    // "1. Hotel Name" or header lines with emoji title.
    if (RegExp(r'^\d+\.\s+\S').hasMatch(t)) return true;
    if (t.startsWith('🏨') ||
        t.startsWith('🍽️') ||
        t.startsWith('☕') ||
        t.startsWith('🏞️')) {
      return true;
    }
    return false;
  }
}

class _TypingBubble extends StatelessWidget {
  const _TypingBubble({required this.accent});

  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: accent.withValues(alpha: 0.12),
            child: Icon(Icons.smart_toy_outlined, size: 18, color: accent),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: AppTheme.scaffoldBackground,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: accent,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  'Typing…',
                  style: AtmosBrandTypography.meaningTagline(
                    color: AppTheme.unselectedMuted,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Mobile full-screen FAQ browser; pops with the question to ask Tala.
class _FaqBrowsePage extends StatefulWidget {
  const _FaqBrowsePage({required this.accent});

  final Color accent;

  @override
  State<_FaqBrowsePage> createState() => _FaqBrowsePageState();
}

class _FaqBrowsePageState extends State<_FaqBrowsePage> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<AppFaqItem> get _items {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return kAppFaqItems;
    return kAppFaqItems
        .where(
          (i) =>
              i.question.toLowerCase().contains(q) ||
              i.answer.toLowerCase().contains(q),
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    return TouristFullPage(
      title: 'Frequently asked',
      subtitle: 'Tap a question to see the answer, or ask Tala for more.',
      icon: Icons.help_outline_rounded,
      headerBottom: Container(
        height: 46,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
        ),
        child: TextField(
          controller: _search,
          onChanged: (v) => setState(() => _query = v),
          textInputAction: TextInputAction.search,
          style: const TextStyle(fontSize: 14.5, color: _kDarkText),
          decoration: InputDecoration(
            hintText: 'Search questions',
            hintStyle: TextStyle(color: Colors.grey.shade500),
            prefixIcon: Icon(Icons.search_rounded, color: Colors.grey.shade500),
            suffixIcon: _query.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Clear',
                    icon: Icon(Icons.close_rounded, color: Colors.grey.shade500),
                    onPressed: () {
                      _search.clear();
                      setState(() => _query = '');
                    },
                  ),
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(vertical: 13),
          ),
        ),
      ),
      child: items.isEmpty
          ? const TouristEmptyState(
              icon: Icons.search_off_rounded,
              title: 'No matching questions',
              message: 'Try another word, or go back and ask Tala directly.',
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 32),
              itemCount: items.length + 1,
              separatorBuilder: (_, i) => SizedBox(height: i == 0 ? 12 : 10),
              itemBuilder: (context, index) {
                if (index == 0) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Text(
                      _query.isEmpty
                          ? '${items.length} common questions'
                          : '${items.length} ${items.length == 1 ? 'result' : 'results'}',
                      style: AtmosBrandTypography.meaningTagline(
                        color: AppTheme.unselectedMuted,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  );
                }
                final item = items[index - 1];
                return _FaqBrowseTile(
                  key: ValueKey(item.question),
                  item: item,
                  accent: widget.accent,
                  onAsk: () => Navigator.of(context).pop(item.question),
                );
              },
            ),
    );
  }
}

class _FaqBrowseTile extends StatefulWidget {
  const _FaqBrowseTile({
    super.key,
    required this.item,
    required this.accent,
    required this.onAsk,
  });

  final AppFaqItem item;
  final Color accent;
  final VoidCallback onAsk;

  @override
  State<_FaqBrowseTile> createState() => _FaqBrowseTileState();
}

class _FaqBrowseTileState extends State<_FaqBrowseTile> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final accent = widget.accent;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _expanded
              ? accent.withValues(alpha: 0.45)
              : const Color(0xFFE2E8F0),
          width: _expanded ? 1.4 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: _expanded
                ? accent.withValues(alpha: 0.12)
                : Colors.black.withValues(alpha: 0.03),
            blurRadius: _expanded ? 16 : 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => setState(() => _expanded = !_expanded),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 10, 12),
            child: AnimatedSize(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              accent.withValues(alpha: 0.18),
                              accent.withValues(alpha: 0.08),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(widget.item.icon, size: 20, color: accent),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            widget.item.question,
                            style: AtmosBrandTypography.meaningTagline(
                              color: _kDarkText,
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              height: 1.35,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      AnimatedRotation(
                        turns: _expanded ? 0.5 : 0,
                        duration: const Duration(milliseconds: 200),
                        child: Container(
                          width: 30,
                          height: 30,
                          margin: const EdgeInsets.only(top: 4),
                          decoration: BoxDecoration(
                            color: _expanded
                                ? accent.withValues(alpha: 0.12)
                                : const Color(0xFFF1F5F9),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.expand_more_rounded,
                            size: 20,
                            color: _expanded ? accent : AppTheme.unselectedMuted,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (_expanded) ...[
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(left: 50, right: 4),
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(12),
                        border: Border(
                          left: BorderSide(color: accent, width: 3),
                        ),
                      ),
                      child: Text(
                        widget.item.answer,
                        style: AtmosBrandTypography.meaningTagline(
                          color: const Color(0xFF475569),
                          fontSize: 14,
                          height: 1.5,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Padding(
                      padding: const EdgeInsets.only(left: 50),
                      child: FilledButton.icon(
                        onPressed: widget.onAsk,
                        style: FilledButton.styleFrom(
                          backgroundColor: accent,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 8,
                          ),
                          visualDensity: VisualDensity.compact,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                        ),
                        icon: const Icon(Icons.chat_bubble_outline, size: 16),
                        label: Text(
                          'Ask Tala',
                          style: AtmosBrandTypography.meaningTagline(
                            color: Colors.white,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
