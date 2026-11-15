import 'package:flutter/material.dart';
import '../../auth/presentation/personal_avatar.dart';
import '../../navigation/presentation/space_widgets.dart';
import '../../proposals/domain/proposal_repository.dart';
import '../../requests/presentation/request_views.dart' show requestDate;
import '../domain/conversation_repository.dart';

String conversationInitials(String name) {
  final words = name
      .trim()
      .split(RegExp(r'\s+'))
      .where((s) => s.isNotEmpty)
      .toList();
  if (words.isEmpty) return '?';
  return words
      .take(2)
      .map((word) => word.characters.first)
      .join()
      .toUpperCase();
}

String conversationCardDate(int timestamp) {
  const months = [
    'janv.',
    'févr.',
    'mars',
    'avr.',
    'mai',
    'juin',
    'juil.',
    'août',
    'sept.',
    'oct.',
    'nov.',
    'déc.',
  ];
  final date = DateTime.fromMillisecondsSinceEpoch(timestamp);
  return '${date.day} ${months[date.month - 1]}${date.year == DateTime.now().year ? '' : ' ${date.year}'}';
}

class ConversationCard extends StatelessWidget {
  const ConversationCard({
    super.key,
    required this.conversation,
    required this.viewerUid,
    required this.onOpen,
    this.avatarKey,
    this.profilePhoto,
    this.onLongPress,
    this.deleting = false,
  });
  final Conversation conversation;
  final String viewerUid;
  final VoidCallback onOpen;
  final String? avatarKey;
  final Widget? profilePhoto;
  final VoidCallback? onLongPress;
  final bool deleting;
  @override
  Widget build(BuildContext context) {
    final name = conversation.otherName(viewerUid);
    final fallback = CircleAvatar(
      radius: 23,
      backgroundColor: FoundiUi.tint,
      child: Text(
        conversationInitials(name),
        style: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w700,
          color: FoundiUi.green,
        ),
      ),
    );
    final active = conversation.active;
    final retained = active && conversation.proposalStatus == 'retained';
    return FoundiPanel(
      padding: const EdgeInsets.all(16),
      onTap: deleting ? null : onOpen,
      onLongPress: deleting ? null : onLongPress,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ExcludeSemantics(
            child: SizedBox(
              width: 46,
              height: 46,
              child:
                  profilePhoto ??
                  PersonalAvatar(
                    key: ValueKey(avatarKey),
                    publicId: avatarKey,
                    size: 46,
                    fallback: fallback,
                  ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LayoutBuilder(
                  builder: (context, constraints) {
                    final nameWidget = Text(
                      name,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: FoundiUi.ink,
                      ),
                    );
                    final date = deleting
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              semanticsLabel: 'Suppression en cours',
                            ),
                          )
                        : Tooltip(
                            triggerMode: TooltipTriggerMode.manual,
                            message: requestDate(
                              DateTime.fromMillisecondsSinceEpoch(
                                conversation.updatedAt,
                              ),
                            ),
                            child: Text(
                              conversationCardDate(conversation.updatedAt),
                              style: const TextStyle(
                                fontSize: 11,
                                color: FoundiUi.muted,
                              ),
                            ),
                          );
                    if (constraints.maxWidth < 210 ||
                        MediaQuery.textScalerOf(context).scale(16) > 21) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [nameWidget, const SizedBox(height: 3), date],
                      );
                    }
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: nameWidget),
                        const SizedBox(width: 8),
                        date,
                      ],
                    );
                  },
                ),
                const SizedBox(height: 4),
                Text(
                  conversation.requestTitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: FoundiUi.muted),
                ),
                const SizedBox(height: 9),
                Text(
                  conversation.lastMessagePreview.trim().isEmpty
                      ? 'Discussion prête — écrire un message'
                      : conversation.lastMessagePreview,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    color: FoundiUi.ink,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 11),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: active ? FoundiUi.tint : const Color(0xFFF0F3F1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        !active
                            ? Icons.lock_outline
                            : retained
                            ? Icons.check_circle_outline
                            : Icons.chat_bubble_outline,
                        size: 14,
                        color: active ? FoundiUi.green : FoundiUi.muted,
                      ),
                      const SizedBox(width: 5),
                      Flexible(
                        child: Text(
                          !active
                              ? 'Lecture seule'
                              : retained
                              ? 'Proposition retenue'
                              : proposalStatusLabel(
                                  conversation.proposalStatus,
                                ),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: active ? FoundiUi.green : FoundiUi.muted,
                          ),
                        ),
                      ),
                    ],
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
