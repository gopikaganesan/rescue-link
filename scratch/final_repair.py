
import os

file_path = r'c:\Users\gopik\Documents\gdg-hack\app\rescue_link\lib\screens\group_chat_screen.dart'

with open(file_path, 'r', encoding='utf-8') as f:
    content = f.read()

# 1. Fix the message Align block
# We look for the start of the Align block that contains Row and Flexible
target_align_start = '                          return Align(\n                            alignment: isMine\n                                ? Alignment.centerRight\n                                : Alignment.centerLeft,\n                            child: Row('
if target_align_start in content:
    print("Found target align block start")
    # We need to find the specific closing segment to replace
    # The current one has unclosed Row/Flexible tags
    mismatch_segment = '''                             ),\n                             ),\n                           );'''
    correct_segment = '''                                    ),\n                                  ),\n                                ),\n                              ],\n                            ),\n                          );'''
    # This is risky due to multiple matches. Let's do a more specific replacement for the whole block.
    
# Actually, let's just use a very specific block replacement for the Text widget
old_text = '''                                   Text(
                                    isAiMessage
                                        ? '$senderName • AI'
                                        : senderName,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelMedium
                                        ?.copyWith(fontWeight: FontWeight.w600),
                                  ),'''
new_text = '''                                          GestureDetector(
                                            onTap: isMine || isAiMessage || isSystem ? null : () => _showResponderOptions(
                                              context: context,
                                              participantData: {
                                                'uid': senderUid,
                                                'displayName': senderName,
                                                'isAi': isAiMessage,
                                              },
                                              responderName: senderName,
                                            ),
                                            child: Text(
                                              isAiMessage
                                                  ? '$senderName • AI'
                                                  : senderName,
                                              overflow: TextOverflow.ellipsis,
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .labelMedium
                                                  ?.copyWith(
                                                    fontWeight: FontWeight.w600,
                                                    color: !isMine && !isAiMessage ? Theme.of(context).colorScheme.primary : null,
                                                  ),
                                            ),
                                          ),'''

content = content.replace(old_text, new_text)

# 2. Fix the brackets
old_brackets = '''                             ),
                             ),
                           );'''
new_brackets = '''                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );'''
content = content.replace(old_brackets, new_brackets)

# 3. Add JoinRequestsHeader call
old_overview = '''               _buildOverviewCard(
                context,
                message: overviewMessage,
                media: overviewMedia,
                overview: overviewWithLocation,
              ),
              if (showJoinGate)'''
new_overview = '''               _buildOverviewCard(
                context,
                message: overviewMessage,
                media: overviewMedia,
                overview: overviewWithLocation,
              ),
              if (_isOwner && joinRequests.any((r) => r['status'] == 'pending'))
                _buildJoinRequestsHeader(joinRequests),
              if (showJoinGate)'''
content = content.replace(old_overview, new_overview)

with open(file_path, 'w', encoding='utf-8') as f:
    f.write(content)

print("Repair completed.")
