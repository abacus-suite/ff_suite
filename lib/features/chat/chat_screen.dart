import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api_client.dart';
import '../../core/format.dart';
import '../../core/photos.dart';
import '../../core/services.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';

/// Conversations from Odoo Discuss: channels and direct chats.
class ChatListScreen extends StatefulWidget {
  const ChatListScreen({super.key, this.inSheet = false});

  /// Shown in the pull-up chat panel rather than as a full page.
  final bool inSheet;

  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> {
  List<Map<String, dynamic>> _channels = [];
  String? _error;
  bool _loading = true;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    // Show the last list straight away, then refresh it.
    Services.queue.readCache(ApiClient.cacheKey('/api/v1/chat/channels', null)).then((cached) {
      final data = cached?.$1;
      if (!mounted || data is! Map || _channels.isNotEmpty) return;
      setState(() => _channels = ((data['channels'] as List?) ?? []).cast<Map<String, dynamic>>());
    });
    _load();
    _poll =
        Timer.periodic(const Duration(seconds: 20), (_) => _load(quiet: true));
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _load({bool quiet = false}) async {
    if (!quiet) setState(() => _loading = true);
    try {
      final data = await Services.api.get('/api/v1/chat/channels')
          as Map<String, dynamic>;
      if (mounted) {
        setState(() {
          _channels =
              ((data['channels'] as List?) ?? []).cast<Map<String, dynamic>>();
          _error = null;
        });
        ChatBadge.unread.value = (data['unread'] as num? ?? 0).toInt();
      }
    } catch (e) {
      if (mounted && !quiet) setState(() => _error = e.toString());
    } finally {
      if (mounted && !quiet) setState(() => _loading = false);
    }
  }

  Future<void> _open(Map<String, dynamic> channel) async {
    await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => ConversationScreen(channel: channel)));
    _load(quiet: true);
  }

  Future<void> _newChat() async {
    List<Map<String, dynamic>> people;
    try {
      people = ((await Services.api.get('/api/v1/chat/people')) as List)
          .cast<Map<String, dynamic>>();
    } catch (e) {
      if (mounted) showSnack(context, e.toString());
      return;
    }
    if (!mounted) return;
    final picked = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheet) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        builder: (context, controller) => ListView(
          controller: controller,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text('Chat with',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            ),
            if (people.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text('Nobody in your team has an Odoo user yet.',
                    style: TextStyle(color: AixoloColors.muted)),
              ),
            for (final p in people)
              ListTile(
                leading: CircleAvatar(
                  backgroundColor: const Color(0xFFE8EFFF),
                  child: Text(
                      '${p['name']}'.isNotEmpty ? '${p['name']}'[0] : '?',
                      style: const TextStyle(
                          color: AixoloColors.primary,
                          fontWeight: FontWeight.w800)),
                ),
                title: Text('${p['name']}'),
                subtitle:
                    Text([p['job'], p['team']].whereType<String>().join(' · ')),
                onTap: () => Navigator.pop(sheet, p),
              ),
          ],
        ),
      ),
    );
    if (picked == null) return;
    try {
      final channel = await Services.api.post(
              '/api/v1/chat/direct', {'employee_id': picked['employee_id']})
          as Map<String, dynamic>;
      if (mounted) _open(channel);
    } catch (e) {
      if (mounted) showSnack(context, e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: widget.inSheet
          ? AppBar(
              title: const Text('Chat'),
              automaticallyImplyLeading: false,
              actions: [
                IconButton(
                  tooltip: 'Close',
                  icon: const Icon(Icons.keyboard_arrow_down_rounded),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            )
          : AppBar(title: const Text('Chat')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _newChat,
        icon: const Icon(Icons.chat_rounded),
        label: const Text('New chat'),
      ),
      body: _error != null && _channels.isEmpty
          ? ErrorView(message: _error!, onRetry: _load)
          : _channels.isEmpty && _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: _channels.isEmpty && !_loading
                  ? ListView(children: const [
                      SizedBox(height: 120),
                      Icon(Icons.forum_rounded,
                          size: 56, color: AixoloColors.muted),
                      SizedBox(height: 10),
                      Center(
                          child: Text('No conversations yet',
                              style: TextStyle(color: AixoloColors.muted))),
                    ])
                  : ListView.separated(
                      padding: const EdgeInsets.only(bottom: 90),
                      itemCount: _channels.length,
                      separatorBuilder: (_, __) =>
                          const Divider(height: 1, indent: 72),
                      itemBuilder: (context, i) {
                        final c = _channels[i];
                        final unread = (c['unread'] as num? ?? 0).toInt();
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor: c['type'] == 'chat'
                                ? const Color(0xFFE8EFFF)
                                : const Color(0xFFE6F7EE),
                            child: c['type'] == 'chat'
                                ? Text(
                                    '${c['name']}'.isNotEmpty
                                        ? '${c['name']}'[0]
                                        : '?',
                                    style: const TextStyle(
                                        color: AixoloColors.primary,
                                        fontWeight: FontWeight.w800))
                                : const Icon(Icons.tag_rounded,
                                    color: AixoloColors.success),
                          ),
                          title: Text('${c['name']}',
                              style: TextStyle(
                                  fontWeight: unread > 0
                                      ? FontWeight.w800
                                      : FontWeight.w600)),
                          subtitle: Text(
                            c['last_message'] == null
                                ? 'No messages yet'
                                : '${c['type'] == 'chat' ? '' : '${c['last_author']}: '}${c['last_message']}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              if (c['last_at'] != null)
                                Text(fmtTime(c['last_at']),
                                    style: const TextStyle(
                                        fontSize: 11.5,
                                        color: AixoloColors.muted)),
                              if (unread > 0)
                                Container(
                                  margin: const EdgeInsets.only(top: 4),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 7, vertical: 2),
                                  decoration: BoxDecoration(
                                      color: AixoloColors.primary,
                                      borderRadius: BorderRadius.circular(20)),
                                  child: Text('$unread',
                                      style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w800)),
                                ),
                            ],
                          ),
                          onTap: () => _open(c),
                        );
                      },
                    ),
            ),
    );
  }
}

/// One conversation; new messages arrive every few seconds while it is open.
class ConversationScreen extends StatefulWidget {
  const ConversationScreen({super.key, required this.channel});

  final Map<String, dynamic> channel;

  @override
  State<ConversationScreen> createState() => _ConversationScreenState();
}

class _ConversationScreenState extends State<ConversationScreen> {
  final List<Map<String, dynamic>> _messages = [];
  final _input = TextEditingController();
  final _scroll = ScrollController();
  Timer? _poll;
  bool _sending = false;
  String? _error;

  int get _id => widget.channel['id'] as int;

  @override
  void initState() {
    super.initState();
    _load();
    _poll =
        Timer.periodic(const Duration(seconds: 5), (_) => _load(newer: true));
  }

  @override
  void dispose() {
    _poll?.cancel();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load({bool newer = false}) async {
    try {
      final data =
          await Services.api.get('/api/v1/chat/channels/$_id/messages', query: {
        if (newer && _messages.isNotEmpty) 'after_id': _messages.last['id'],
      }) as Map<String, dynamic>;
      final incoming =
          ((data['messages'] as List?) ?? []).cast<Map<String, dynamic>>();
      if (!mounted) return;
      if (incoming.isNotEmpty || !newer) {
        final known = _messages.map((m) => m['id']).toSet();
        setState(() {
          _messages.addAll(incoming.where((m) => !known.contains(m['id'])));
          _error = null;
        });
        _toBottom();
        Services.api
            .post('/api/v1/chat/channels/$_id/seen')
            .catchError((_) => null);
      }
    } on ApiException catch (e) {
      if (mounted && !newer) setState(() => _error = e.message);
    }
  }

  void _toBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients)
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
    });
  }

  Future<void> _send({List<Map<String, dynamic>> files = const []}) async {
    final text = _input.text.trim();
    if (text.isEmpty && files.isEmpty) return;
    setState(() => _sending = true);
    try {
      final message =
          await Services.api.post('/api/v1/chat/channels/$_id/messages', {
        'body': text,
        if (files.isNotEmpty) 'attachments': files,
      }) as Map<String, dynamic>;
      _input.clear();
      if (mounted) setState(() => _messages.add(message));
      _toBottom();
    } catch (e) {
      if (mounted) showSnack(context, e.toString());
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  static const _maxBytes = 25 * 1024 * 1024;

  Future<void> _attach() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_rounded,
                  color: AixoloColors.primary),
              title: const Text('Take photo'),
              onTap: () => Navigator.pop(sheet, 'photo'),
            ),
            ListTile(
              leading: const Icon(Icons.videocam_rounded,
                  color: AixoloColors.danger),
              title: const Text('Record video'),
              onTap: () => Navigator.pop(sheet, 'video'),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_rounded,
                  color: AixoloColors.success),
              title: const Text('Photo or video from gallery'),
              onTap: () => Navigator.pop(sheet, 'gallery'),
            ),
            ListTile(
              leading: const Icon(Icons.attach_file_rounded,
                  color: AixoloColors.purple),
              title: const Text('Document'),
              subtitle: const Text('PDF, Excel, Word…'),
              onTap: () => Navigator.pop(sheet, 'file'),
            ),
          ],
        ),
      ),
    );
    if (choice == null) return;
    final files = <Map<String, dynamic>>[];
    try {
      switch (choice) {
        case 'photo':
          final bytes = await takePhoto(ImageSource.camera);
          if (bytes != null)
            files.add(_file(
                'photo_${DateTime.now().millisecondsSinceEpoch}.jpg',
                'image/jpeg',
                bytes));
        case 'video':
          final video = await ImagePicker().pickVideo(
              source: ImageSource.camera,
              maxDuration: const Duration(minutes: 2));
          if (video != null)
            files
                .add(_file(video.name, 'video/mp4', await video.readAsBytes()));
        case 'gallery':
          final media =
              await ImagePicker().pickMedia(imageQuality: 60, maxWidth: 1600);
          if (media != null) {
            final video = media.name.toLowerCase().endsWith('.mp4') ||
                media.name.toLowerCase().endsWith('.mov');
            files.add(_file(media.name, video ? 'video/mp4' : 'image/jpeg',
                await media.readAsBytes()));
          }
        default:
          final picked = await FilePicker.pickFiles();
          for (final f in picked) {
            files.add(_file(f.name, _mime(f.name), await f.readAsBytes()));
          }
      }
    } catch (e) {
      if (mounted) showSnack(context, e.toString());
      return;
    }
    if (files.isEmpty) return;
    final tooBig = files.where((f) => (f['_size'] as int) > _maxBytes);
    if (tooBig.isNotEmpty) {
      if (mounted) showSnack(context, 'Files must be under 25 MB.');
      return;
    }
    for (final f in files) {
      f.remove('_size');
    }
    await _send(files: files);
  }

  Map<String, dynamic> _file(String name, String mimetype, List<int> bytes) => {
        'name': name,
        'mimetype': mimetype,
        'data': base64Encode(bytes),
        '_size': bytes.length
      };

  static String _mime(String name) {
    final ext = name.split('.').last.toLowerCase();
    return const {
          'pdf': 'application/pdf',
          'jpg': 'image/jpeg',
          'jpeg': 'image/jpeg',
          'png': 'image/png',
          'mp4': 'video/mp4',
          'mov': 'video/quicktime',
          'xlsx':
              'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
          'xls': 'application/vnd.ms-excel',
          'docx':
              'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
          'doc': 'application/msword',
          'csv': 'text/csv',
          'txt': 'text/plain',
        }[ext] ??
        'application/octet-stream';
  }

  Future<void> _openFile(Map<String, dynamic> file) async {
    final url = Uri.parse(await Services.api.url('${file['url']}'));
    if (!await launchUrl(url, mode: LaunchMode.externalApplication) &&
        mounted) {
      showSnack(context, 'Could not open the file.');
    }
  }

  Widget _attachmentView(Map<String, dynamic> a, bool mine) {
    final mime = '${a['mimetype']}';
    if (mime.startsWith('image/')) {
      return FutureBuilder<String>(
        future: Services.api.url('${a['url']}'),
        builder: (context, snap) => GestureDetector(
          onTap: () => _openFile(a),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: snap.hasData
                  ? Image.network(snap.data!,
                      width: 220,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const SizedBox(
                          width: 220,
                          height: 80,
                          child: Icon(Icons.broken_image_rounded)))
                  : const SizedBox(width: 220, height: 140),
            ),
          ),
        ),
      );
    }
    final video = mime.startsWith('video/');
    return InkWell(
      onTap: () => _openFile(a),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
                video
                    ? Icons.play_circle_fill_rounded
                    : Icons.insert_drive_file_rounded,
                color: mine ? Colors.white : AixoloColors.primary,
                size: 30),
            const SizedBox(width: 8),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('${a['name']}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: mine ? Colors.white : AixoloColors.text)),
                  Text(
                      '${((a['size'] as num? ?? 0) / 1024).toStringAsFixed(0)} KB · tap to open',
                      style: TextStyle(
                          fontSize: 11,
                          color: mine ? Colors.white70 : AixoloColors.muted)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('${widget.channel['name']}')),
      body: Column(
        children: [
          Expanded(
            child: _error != null
                ? ErrorView(message: _error!, onRetry: _load)
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                    itemCount: _messages.length,
                    itemBuilder: (context, i) {
                      final m = _messages[i];
                      final mine = m['mine'] == true;
                      final showAuthor = !mine &&
                          (i == 0 ||
                              _messages[i - 1]['author_id'] != m['author_id']);
                      return Align(
                        alignment:
                            mine ? Alignment.centerRight : Alignment.centerLeft,
                        child: Container(
                          constraints: BoxConstraints(
                              maxWidth:
                                  MediaQuery.of(context).size.width * 0.78),
                          margin: const EdgeInsets.symmetric(vertical: 3),
                          padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
                          decoration: BoxDecoration(
                            color: mine ? AixoloColors.primary : Colors.white,
                            borderRadius: BorderRadius.only(
                              topLeft: const Radius.circular(16),
                              topRight: const Radius.circular(16),
                              bottomLeft: Radius.circular(mine ? 16 : 4),
                              bottomRight: Radius.circular(mine ? 4 : 16),
                            ),
                            border: mine
                                ? null
                                : Border.all(color: AixoloColors.border),
                          ),
                          child: IntrinsicWidth(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (showAuthor)
                                  Text('${m['author']}',
                                      style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w800,
                                          color: AixoloColors.primary)),
                                for (final a
                                    in ((m['attachments'] as List?) ?? [])
                                        .cast<Map<String, dynamic>>())
                                  _attachmentView(a, mine),
                                if ('${m['body']}'.isNotEmpty)
                                  Text('${m['body']}',
                                      style: TextStyle(
                                          color: mine
                                              ? Colors.white
                                              : AixoloColors.text,
                                          height: 1.3)),
                                const SizedBox(height: 2),
                                Align(
                                  alignment: Alignment.bottomRight,
                                  child: Text(fmtTime(m['at']),
                                      style: TextStyle(
                                          fontSize: 10.5,
                                          color: mine
                                              ? Colors.white70
                                              : AixoloColors.muted)),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
          SafeArea(
            top: false,
            child: Container(
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Attach',
                    onPressed: _sending ? null : _attach,
                    icon: const Icon(Icons.add_circle_outline_rounded,
                        color: AixoloColors.primary),
                  ),
                  Expanded(
                    child: TextField(
                      controller: _input,
                      minLines: 1,
                      maxLines: 4,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(
                          hintText: 'Message', isDense: true),
                    ),
                  ),
                  IconButton.filled(
                    onPressed: _sending ? null : _send,
                    icon: _sending
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.send_rounded),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Unread chat messages, for the pull-up chat button.
class ChatBadge {
  static final ValueNotifier<int> unread = ValueNotifier(0);
  static Timer? _timer;

  static void start() {
    _timer ??= Timer.periodic(const Duration(minutes: 2), (_) => refresh());
    refresh();
  }

  static void stop() {
    _timer?.cancel();
    _timer = null;
  }

  static Future<void> refresh() async {
    try {
      final data = await Services.api.get('/api/v1/chat/channels') as Map<String, dynamic>;
      unread.value = (data['unread'] as num? ?? 0).toInt();
    } catch (_) {
      // No Odoo user or offline: keep the last count.
    }
  }
}

/// A small tab at the bottom edge: tap to pull the chat panel up.
class ChatDock extends StatelessWidget {
  const ChatDock({super.key});

  Future<void> _open(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (sheet) => DraggableScrollableSheet(
        initialChildSize: 0.75,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, controller) => ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
          child: const ChatListScreen(inSheet: true),
        ),
      ),
    );
    ChatBadge.refresh();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: ChatBadge.unread,
      builder: (context, unread, _) => Material(
        color: AixoloColors.primary,
        elevation: 6,
        shadowColor: AixoloColors.primary.withValues(alpha: 0.4),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
        child: InkWell(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
          onTap: () => _open(context),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 5, 12, 5),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.keyboard_arrow_up_rounded, color: Colors.white, size: 18),
                const SizedBox(width: 2),
                const Icon(Icons.forum_rounded, color: Colors.white, size: 16),
                if (unread > 0) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(color: AixoloColors.danger, borderRadius: BorderRadius.circular(10)),
                    child: Text(unread > 99 ? '99+' : '$unread',
                        style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800)),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
