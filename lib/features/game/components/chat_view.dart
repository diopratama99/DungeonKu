import 'package:flutter/material.dart';

import 'package:dungeonku/core/theme/app_theme.dart';
import 'package:dungeonku/core/theme/pixel_colors.dart';
import 'package:dungeonku/core/widgets/pixel_panel.dart';
import 'package:dungeonku/core/widgets/pixel_spinner.dart';
import 'package:dungeonku/data/models/messages.dart';

class ChatView extends StatefulWidget {
  const ChatView({required this.messages, required this.busy, super.key});
  final List<GameMessage> messages;
  final bool busy;

  @override
  State<ChatView> createState() => _ChatViewState();
}

class _ChatViewState extends State<ChatView> {
  final _scrollCtrl = ScrollController();

  @override
  void didUpdateWidget(ChatView old) {
    super.didUpdateWidget(old);
    if (widget.messages.length != old.messages.length) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollCtrl.hasClients) {
          _scrollCtrl.animateTo(
            _scrollCtrl.position.maxScrollExtent,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      controller: _scrollCtrl,
      padding: const EdgeInsets.all(12),
      itemCount: widget.messages.length + (widget.busy ? 1 : 0),
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        if (i >= widget.messages.length) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Row(
              children: [
                PixelSpinner(size: 18),
                SizedBox(width: 8),
                Text('The DM considers...'),
              ],
            ),
          );
        }
        final m = widget.messages[i];
        return _Bubble(message: m);
      },
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message});
  final GameMessage message;

  @override
  Widget build(BuildContext context) {
    final isPlayer = message.role == 'player';
    final isSystem = message.role == 'system';
    if (isSystem) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            const Expanded(
              child: Divider(color: PixelColors.borderSoft, thickness: 1),
            ),
            const SizedBox(width: 8),
            Text('\u2756  ${message.content}  \u2756',
                style: AppTheme.pressStart(7, color: PixelColors.textMuted)),
            const SizedBox(width: 8),
            const Expanded(
              child: Divider(color: PixelColors.borderSoft, thickness: 1),
            ),
          ],
        ),
      );
    }
    final speaker = isPlayer ? 'YOU' : 'DUNGEON MASTER';
    final speakerColor =
        isPlayer ? PixelColors.textPlayer : PixelColors.accentGold;
    return Align(
      alignment: isPlayer ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 540),
        child: Padding(
          padding: EdgeInsets.only(
            left: isPlayer ? 40 : 0,
            right: isPlayer ? 0 : 40,
          ),
          child: Column(
            crossAxisAlignment:
                isPlayer ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 4, right: 4, bottom: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(width: 6, height: 6, color: speakerColor),
                    const SizedBox(width: 6),
                    Text(speaker,
                        style: AppTheme.pressStart(8, color: speakerColor)),
                  ],
                ),
              ),
              PixelPanel(
                color:
                    isPlayer ? PixelColors.panelInner : PixelColors.parchment,
                borderColor: isPlayer
                    ? PixelColors.borderSoft
                    : PixelColors.borderHighlight,
                innerBorderColor: isPlayer
                    ? PixelColors.borderSoft
                    : PixelColors.parchmentDark,
                child: Text(
                  message.content,
                  style: isPlayer
                      ? AppTheme.vt323(20, color: PixelColors.textPlayer)
                      : AppTheme.vt323(20, color: PixelColors.textOnParchment),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
