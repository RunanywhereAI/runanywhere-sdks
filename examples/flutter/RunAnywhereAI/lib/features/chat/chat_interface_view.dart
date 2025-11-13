import 'package:flutter/material.dart';
import 'package:runanywhere/runanywhere.dart';
import '../../core/design_system/app_colors.dart';
import '../../core/design_system/app_spacing.dart';
import '../../core/design_system/typography.dart';

/// Chat Interface View (placeholder)
class ChatInterfaceView extends StatefulWidget {
  const ChatInterfaceView({super.key});

  @override
  State<ChatInterfaceView> createState() => _ChatInterfaceViewState();
}

class _ChatInterfaceViewState extends State<ChatInterfaceView> {
  final TextEditingController _controller = TextEditingController();
  final List<ChatMessage> _messages = [];
  bool _isGenerating = false;

  Future<void> _sendMessage() async {
    if (_controller.text.isEmpty || _isGenerating) return;

    final userMessage = _controller.text;
    _controller.clear();

    setState(() {
      _messages.add(ChatMessage(
        text: userMessage,
        isUser: true,
      ));
      _isGenerating = true;
    });

    try {
      // Add empty assistant message for streaming
      final assistantMessageIndex = _messages.length;
      _messages.add(ChatMessage(
        text: '',
        isUser: false,
      ));

      // Generate response using SDK with streaming
      final stream = RunAnywhere.generateStream(
        userMessage,
        options: RunAnywhereGenerationOptions(
          maxTokens: 500,
          temperature: 0.7,
        ),
      );

      String fullResponse = '';
      await for (final token in stream) {
        fullResponse += token;
        setState(() {
          _messages[assistantMessageIndex] = ChatMessage(
            text: fullResponse,
            isUser: false,
          );
        });
      }

      setState(() {
        _isGenerating = false;
      });
    } catch (e) {
      setState(() {
        if (_messages.isNotEmpty && !_messages.last.isUser) {
          _messages.removeLast();
        }
        _messages.add(ChatMessage(
          text: 'Error: $e',
          isUser: false,
        ));
        _isGenerating = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Chat'),
      ),
      body: Column(
        children: [
          Expanded(
            child: _messages.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.psychology,
                          size: AppSpacing.iconXXLarge,
                          color: AppColors.primaryBlue,
                        ),
                        const SizedBox(height: AppSpacing.large),
                        Text(
                          'Start a conversation',
                          style: AppTypography.title2(context),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(AppSpacing.padding16),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      final message = _messages[index];
                      return ChatBubble(message: message);
                    },
                  ),
          ),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.padding16),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    decoration: const InputDecoration(
                      hintText: 'Type a message...',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.padding8),
                IconButton(
                  icon: _isGenerating
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send),
                  onPressed: _isGenerating ? null : _sendMessage,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}

class ChatMessage {
  final String text;
  final bool isUser;
  final DateTime timestamp;

  ChatMessage({
    required this.text,
    required this.isUser,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();
}

class ChatBubble extends StatelessWidget {
  final ChatMessage message;

  const ChatBubble({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: message.isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: AppSpacing.padding8),
        padding: const EdgeInsets.all(AppSpacing.padding12),
        decoration: BoxDecoration(
          color: message.isUser
              ? AppColors.primaryBlue
              : AppColors.backgroundSecondary(context),
          borderRadius: BorderRadius.circular(AppSpacing.cornerRadiusBubble),
        ),
        child: Text(
          message.text,
          style: AppTypography.body(context).copyWith(
            color: message.isUser
                ? AppColors.textWhite
                : AppColors.textPrimary(context),
          ),
        ),
      ),
    );
  }
}

