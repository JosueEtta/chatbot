import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await dotenv.load(fileName: ".env");
  } catch (e) {
    debugPrint("Failed to load .env file: $e");
  }

  // Load the saved theme before the first frame so there is no flash.
  final prefs = await SharedPreferences.getInstance();
  final startDark = prefs.getBool('dark_mode') ?? false;

  runApp(MyApp(prefs: prefs, startDark: startDark));
}

// ===========================================================================
// Theme
// ===========================================================================

const Color kAccent = Color(0xFFD4271C);

/// All colours used by the UI. Light and dark palettes are interpolated while
/// the toggle animates, so every surface fades smoothly between the two.
class Palette {
  const Palette({
    required this.bg,
    required this.fg,
    required this.muted,
    required this.line,
    required this.divider,
    required this.surface,
    required this.shadow,
    required this.hint,
    required this.track,
    required this.knob,
    required this.sun,
    required this.moon,
    required this.hover,
    required this.userBubble,
    required this.error,
  });

  final Color bg;
  final Color fg;
  final Color muted;
  final Color line;
  final Color divider;
  final Color surface;
  final Color shadow;
  final Color hint;
  final Color track;
  final Color knob;
  final Color sun;
  final Color moon;
  final Color hover;
  final Color userBubble;
  final Color error;

  static const light = Palette(
    bg: Color(0xFFFFFFFF),
    fg: Color(0xFF1A1A1A),
    muted: Color(0xFF6B6B70),
    line: Color(0xFFE6E6E8),
    divider: Color(0xFFF0F0F0),
    surface: Color(0xFFFFFFFF),
    shadow: Color(0x0F000000),
    hint: Color(0xFF8A8A8E),
    track: Color(0xFFEDEDEF),
    knob: Color(0xFFFFFFFF),
    sun: Color(0xFFD4271C),
    moon: Color(0xFF8A8A90),
    hover: Color(0xFFFDF1F0),
    userBubble: Color(0xFFF4F4F5),
    error: Color(0xFFC62828),
  );

  static const dark = Palette(
    bg: Color(0xFF141414),
    fg: Color(0xFFEDEDED),
    muted: Color(0xFF9A9AA0),
    line: Color(0xFF2F2F33),
    divider: Color(0xFF232326),
    surface: Color(0xFF1D1D20),
    shadow: Color(0x80000000),
    hint: Color(0xFF8C8C92),
    track: Color(0xFF2A2A2E),
    knob: Color(0xFF44444A),
    sun: Color(0xFF8C8C92),
    moon: Color(0xFFFFFFFF),
    hover: Color(0xFF2A1A19),
    userBubble: Color(0xFF2A2A2E),
    error: Color(0xFFFF8A80),
  );

  static Palette lerp(Palette a, Palette b, double t) => Palette(
    bg: Color.lerp(a.bg, b.bg, t)!,
    fg: Color.lerp(a.fg, b.fg, t)!,
    muted: Color.lerp(a.muted, b.muted, t)!,
    line: Color.lerp(a.line, b.line, t)!,
    divider: Color.lerp(a.divider, b.divider, t)!,
    surface: Color.lerp(a.surface, b.surface, t)!,
    shadow: Color.lerp(a.shadow, b.shadow, t)!,
    hint: Color.lerp(a.hint, b.hint, t)!,
    track: Color.lerp(a.track, b.track, t)!,
    knob: Color.lerp(a.knob, b.knob, t)!,
    sun: Color.lerp(a.sun, b.sun, t)!,
    moon: Color.lerp(a.moon, b.moon, t)!,
    hover: Color.lerp(a.hover, b.hover, t)!,
    userBubble: Color.lerp(a.userBubble, b.userBubble, t)!,
    error: Color.lerp(a.error, b.error, t)!,
  );
}

// ===========================================================================
// App
// ===========================================================================

class MyApp extends StatelessWidget {
  const MyApp({super.key, required this.prefs, required this.startDark});

  final SharedPreferences prefs;
  final bool startDark;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(fontFamily: 'DMSans'), // bundled font, see pubspec.yaml
      home: HomeScreen(prefs: prefs, startDark: startDark),
    );
  }
}

class ChatMessage {
  ChatMessage({this.text = '', required this.isUser, this.eventType});

  String text; // mutable so streamed tokens append in place
  final bool isUser;
  String? eventType; // "chat", "command" or "error"
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.prefs, required this.startDark});

  final SharedPreferences prefs;
  final bool startDark;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  static const _connectTimeout = Duration(seconds: 15);
  static const _idleTimeout = Duration(seconds: 120); // commands are buffered server-side
  static const _maxHistory = 20;

  static const _suggestions = [
    'Help plan my day',
    'I want to chat with a girl',
    'Give latest sport news',
  ];

  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<ChatMessage> _chatMessages = [];

  http.Client? _client;
  StreamSubscription<String>? _subscription;
  Timer? _uiTimer;
  bool _isStreaming = false;

  // Light / dark theme, animated by a single controller.
  late final AnimationController _themeCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 450),
    value: widget.startDark ? 1.0 : 0.0, // start already in the saved theme
  );
  late final Animation<double> _themeAnim = CurvedAnimation(
    parent: _themeCtrl,
    curve: Curves.easeInOutCubic,
  );
  late bool _dark = widget.startDark;

  void _toggleTheme() {
    setState(() => _dark = !_dark);
    _dark ? _themeCtrl.forward() : _themeCtrl.reverse();
    widget.prefs.setBool('dark_mode', _dark); // remembered for next launch
  }

  // ---------------------------------------------------------------- sending

  /// Sends [override] if given (suggestion chips), otherwise the text field.
  Future<void> _send([String? override]) async {
    final text = (override ?? _controller.text).trim();
    if (text.isEmpty || _isStreaming) return;

    final history = _buildHistory(); // built before adding the new turn

    setState(() {
      _chatMessages
        ..add(ChatMessage(text: text, isUser: true))
        ..add(ChatMessage(isUser: false)); // empty AI placeholder -> dots
      _controller.clear();
      _isStreaming = true;
    });
    _scrollToBottom(force: true);

    final baseUrl = dotenv.env['API_URL'] ?? 'http://10.0.2.2:8000/';
    final apiKey = dotenv.env['API_KEY'];
    final client = http.Client();
    _client = client;

    try {
      final request = http.Request('POST', Uri.parse(baseUrl))
        ..headers['Content-Type'] = 'application/json'
        ..headers['Accept'] = 'text/event-stream'
        ..body = jsonEncode({'question': text, 'history': history});
      if (apiKey != null && apiKey.isNotEmpty) {
        request.headers['X-API-Key'] = apiKey;
      }

      final response = await client.send(request).timeout(_connectTimeout);

      if (response.statusCode != 200) {
        _finish(error: 'Server returned status ${response.statusCode}.');
        return;
      }
      _listen(response);
    } on TimeoutException {
      _finish(error: 'The server took too long to respond.');
    } catch (e) {
      debugPrint('Error sending streaming request: $e');
      _finish(error: 'Could not connect to the server ($baseUrl).');
    }
  }

  /// Sends the previous turns so the model has conversation memory.
  List<Map<String, String>> _buildHistory() {
    final turns = _chatMessages
        .where((m) => m.text.isNotEmpty && m.eventType != 'error')
        .map((m) => {'role': m.isUser ? 'user' : 'assistant', 'content': m.text})
        .toList();
    return turns.length > _maxHistory
        ? turns.sublist(turns.length - _maxHistory)
        : turns;
  }

  // ------------------------------------------------------------ SSE parsing

  void _listen(http.StreamedResponse response) {
    var eventType = 'chat';
    final dataLines = <String>[];

    // A blank line marks the end of one SSE event.
    void dispatch() {
      if (dataLines.isEmpty) {
        eventType = 'chat';
        return;
      }
      final raw = dataLines.join('\n');
      final type = eventType;
      dataLines.clear();
      eventType = 'chat';
      try {
        final payload = jsonDecode(raw) as Map<String, dynamic>;
        _appendAiChunk(payload['text'] as String? ?? '', type);
      } catch (e) {
        debugPrint('Bad SSE payload: $e');
      }
    }

    _subscription = response.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter()) // handles lines split across chunks
        .timeout(
      _idleTimeout,
      onTimeout: (sink) {
        sink.addError(TimeoutException('Stream idle'));
        sink.close();
      },
    )
        .listen(
          (line) {
        if (line.isEmpty) {
          dispatch();
          return;
        }
        if (line.startsWith(':')) return; // comment / keep-alive ping
        if (line.startsWith('event:')) {
          eventType = line.substring(6).trim();
        } else if (line.startsWith('data:')) {
          var d = line.substring(5);
          if (d.startsWith(' ')) d = d.substring(1); // strip ONE space only
          dataLines.add(d);
        }
      },
      onDone: () {
        dispatch(); // flush a final event with no trailing blank line
        _finish();
      },
      onError: (Object e) {
        debugPrint('Stream error: $e');
        _finish(
          error: e is TimeoutException
              ? 'The connection stalled.'
              : 'The stream was interrupted.',
        );
      },
      cancelOnError: true,
    );
  }

  // ---------------------------------------------------------- state updates

  void _appendAiChunk(String chunk, String eventType) {
    if (chunk.isEmpty || _chatMessages.isEmpty || _chatMessages.last.isUser) {
      return;
    }
    final last = _chatMessages.last;
    last.text += chunk;
    last.eventType ??= eventType;
    _scheduleRebuild();
  }

  /// Batches rebuilds to ~20/second instead of one per token.
  void _scheduleRebuild() {
    if (_uiTimer?.isActive ?? false) return;
    _uiTimer = Timer(const Duration(milliseconds: 50), () {
      if (!mounted) return;
      setState(() {});
      _scrollToBottom();
    });
  }

  void _stopStreaming() {
    _subscription?.cancel();
    _finish();
  }

  void _finish({String? error}) {
    _subscription = null;
    _client?.close();
    _client = null;
    _uiTimer?.cancel();
    _uiTimer = null;

    if (!mounted) return;
    setState(() {
      if (_chatMessages.isNotEmpty && !_chatMessages.last.isUser) {
        final last = _chatMessages.last;
        if (error != null) {
          if (last.text.isEmpty) {
            last.text = error;
            last.eventType = 'error';
          } else {
            // keep the partial answer, show the error separately
            _chatMessages.add(
              ChatMessage(text: error, isUser: false, eventType: 'error'),
            );
          }
        } else if (last.text.isEmpty) {
          _chatMessages.removeLast(); // nothing came back, drop the placeholder
        }
      }
      _isStreaming = false;
    });
  }

  /// Only auto-scrolls if the user is already near the bottom.
  void _scrollToBottom({bool force = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      final pos = _scrollController.position;
      final nearBottom = pos.maxScrollExtent - pos.pixels < 120;
      if (force) {
        _scrollController.animateTo(
          pos.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      } else if (nearBottom) {
        pos.jumpTo(pos.maxScrollExtent);
      }
    });
  }

  @override
  void dispose() {
    _uiTimer?.cancel();
    _subscription?.cancel();
    _client?.close();
    _themeCtrl.dispose();
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // --------------------------------------------------------------------- UI

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _themeAnim,
      builder: (context, _) {
        final p = Palette.lerp(Palette.light, Palette.dark, _themeAnim.value);
        final overlay =
        _dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark;

        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: overlay.copyWith(
            statusBarColor: Colors.transparent,
            systemNavigationBarColor: p.bg,
          ),
          child: Scaffold(
            backgroundColor: p.bg,
            body: SafeArea(
              bottom: false,
              child: Column(
                children: [
                  _buildHeader(p),
                  Expanded(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      switchInCurve: Curves.easeOut,
                      switchOutCurve: Curves.easeIn,
                      child: _chatMessages.isEmpty
                          ? _buildWelcome(p)
                          : _buildMessageList(p),
                    ),
                  ),
                  _buildInputBar(p),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildHeader(Palette p) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 16, 8),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: p.divider)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Alice',
              style: TextStyle(
                color: p.fg,
                fontSize: 18,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.2,
              ),
            ),
          ),
          ThemeToggle(
            progress: _themeAnim.value,
            palette: p,
            onTap: _toggleTheme,
          ),
        ],
      ),
    );
  }

  Widget _buildWelcome(Palette p) {
    return Padding(
      key: const ValueKey('welcome'),
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Hi, I'm Alice.",
            style: TextStyle(
              color: p.fg,
              fontSize: 30,
              height: 1.15,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.6,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            "Let's chat.",
            style: TextStyle(color: p.muted, fontSize: 18),
          ),
          const SizedBox(height: 24),
          for (final s in _suggestions)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: SuggestionChip(
                label: s,
                palette: p,
                onTap: () => _send(s),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMessageList(Palette p) {
    return ListView.builder(
      key: const ValueKey('chat'),
      controller: _scrollController,
      padding: const EdgeInsets.all(20),
      itemCount: _chatMessages.length,
      itemBuilder: (context, index) {
        final message = _chatMessages[index];
        return FadeSlideIn(
          key: ObjectKey(message),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 18),
            child: _buildMessage(message, p),
          ),
        );
      },
    );
  }

  Widget _buildMessage(ChatMessage message, Palette p) {
    final width = MediaQuery.of(context).size.width;

    // The user's turn: soft rounded bubble on the right.
    if (message.isUser) {
      return Align(
        alignment: Alignment.centerRight,
        child: Container(
          constraints: BoxConstraints(maxWidth: width * 0.76),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: p.userBubble,
            borderRadius: BorderRadius.circular(20),
          ),
          child: SelectableText(
            message.text,
            style: TextStyle(color: p.fg, fontSize: 15, height: 1.45),
          ),
        ),
      );
    }

    // Alice is still thinking: three bouncing dots.
    if (message.text.isEmpty) {
      return const Align(
        alignment: Alignment.centerLeft,
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 2),
          child: ThinkingDots(),
        ),
      );
    }

    final isCommand = message.eventType == 'command';
    final isError = message.eventType == 'error';

    // Alice's turn: plain text, no bubble, no avatar.
    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: width * 0.88),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isCommand)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  'COMMAND',
                  style: TextStyle(
                    color: p.muted,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.1,
                  ),
                ),
              ),
            SelectableText(
              message.text,
              style: TextStyle(
                color: isError ? p.error : p.fg,
                fontSize: 15,
                height: 1.5,
                fontFamily: isCommand ? 'monospace' : null,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInputBar(Palette p) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 6, 6, 6),
          decoration: BoxDecoration(
            color: p.surface,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: p.line),
            boxShadow: [
              BoxShadow(
                color: p.shadow,
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  // stays enabled while streaming so the keyboard isn't dismissed
                  maxLines: 4,
                  minLines: 1,
                  cursorColor: kAccent,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _send(),
                  style: TextStyle(color: p.fg, fontSize: 16),
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    hintText: 'Message Alice',
                    hintStyle: TextStyle(color: p.hint),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SendButton(
                isStreaming: _isStreaming,
                onPressed: _isStreaming ? _stopStreaming : _send,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ===========================================================================
// Widgets
// ===========================================================================

/// Sun / moon switch. [progress] goes 0 (light) -> 1 (dark): the knob slides,
/// the sun spins out and the moon turns in, all driven by the theme animation.
class ThemeToggle extends StatelessWidget {
  const ThemeToggle({
    super.key,
    required this.progress,
    required this.palette,
    required this.onTap,
  });

  final double progress;
  final Palette palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      toggled: progress > 0.5,
      label: 'Toggle dark mode',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          width: 68,
          height: 44,
          child: Center(
            child: Container(
              width: 68,
              height: 36,
              decoration: BoxDecoration(
                color: palette.track,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Stack(
                children: [
                  Positioned(
                    left: 3 + 32 * progress,
                    top: 3,
                    child: Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        color: palette.knob,
                        shape: BoxShape.circle,
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x40000000),
                            blurRadius: 4,
                            offset: Offset(0, 1),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    left: 3,
                    top: 3,
                    child: SizedBox(
                      width: 30,
                      height: 30,
                      child: Center(
                        child: Transform.rotate(
                          angle: progress * math.pi / 2,
                          child: Icon(
                            Icons.wb_sunny_outlined,
                            size: 18,
                            color: palette.sun,
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 35,
                    top: 3,
                    child: SizedBox(
                      width: 30,
                      height: 30,
                      child: Center(
                        child: Transform.rotate(
                          angle: (progress - 1) * 0.7,
                          child: Icon(
                            Icons.dark_mode_outlined,
                            size: 17,
                            color: palette.moon,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Suggestion button. On hover (desktop / web) or while pressed (mobile) it
/// lifts, gets a red border and a light red tint.
class SuggestionChip extends StatefulWidget {
  const SuggestionChip({
    super.key,
    required this.label,
    required this.palette,
    required this.onTap,
  });

  final String label;
  final Palette palette;
  final VoidCallback onTap;

  @override
  State<SuggestionChip> createState() => _SuggestionChipState();
}

class _SuggestionChipState extends State<SuggestionChip> {
  bool _hover = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final p = widget.palette;
    final active = _hover || _pressed;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
          width: double.infinity,
          constraints: const BoxConstraints(minHeight: 48),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          transform: Matrix4.translationValues(0, active ? -2 : 0, 0),
          decoration: BoxDecoration(
            color: active ? p.hover : p.bg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: active ? kAccent : p.line),
            boxShadow: [
              if (active)
                BoxShadow(
                  color: kAccent.withValues(alpha: 0.14),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
            ],
          ),
          alignment: Alignment.centerLeft,
          child: Text(
            widget.label,
            style: TextStyle(
              color: p.fg,
              fontSize: 15,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

/// Round red send button (turns into a stop button while streaming).
class SendButton extends StatefulWidget {
  const SendButton({
    super.key,
    required this.isStreaming,
    required this.onPressed,
  });

  final bool isStreaming;
  final VoidCallback onPressed;

  @override
  State<SendButton> createState() => _SendButtonState();
}

class _SendButtonState extends State<SendButton> {
  bool _hover = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final scale = _pressed ? 0.94 : (_hover ? 1.08 : 1.0);

    return Semantics(
      button: true,
      label: widget.isStreaming ? 'Stop' : 'Send message',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onPressed,
          onTapDown: (_) => setState(() => _pressed = true),
          onTapUp: (_) => setState(() => _pressed = false),
          onTapCancel: () => setState(() => _pressed = false),
          child: AnimatedScale(
            scale: scale,
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOut,
            child: Container(
              width: 44,
              height: 44,
              decoration: const BoxDecoration(
                color: kAccent,
                shape: BoxShape.circle,
              ),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                transitionBuilder: (child, anim) => ScaleTransition(
                  scale: anim,
                  child: FadeTransition(opacity: anim, child: child),
                ),
                child: Icon(
                  widget.isStreaming ? Icons.stop_rounded : Icons.arrow_upward,
                  key: ValueKey(widget.isStreaming),
                  color: Colors.white,
                  size: 22,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Three red dots that bounce one after another while Alice is thinking.
class ThinkingDots extends StatefulWidget {
  const ThinkingDots({super.key});

  @override
  State<ThinkingDots> createState() => _ThinkingDotsState();
}

class _ThinkingDotsState extends State<ThinkingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1000),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  /// 0..1 bump: rises during the first 30% of the cycle, falls until 60%,
  /// then rests. [phase] delays each dot a little.
  double _bump(double phase) {
    final v = (_c.value - phase) % 1.0; // Dart's % is never negative here
    final double k;
    if (v < 0.3) {
      k = v / 0.3;
    } else if (v < 0.6) {
      k = 1 - (v - 0.3) / 0.3;
    } else {
      k = 0;
    }
    return Curves.easeInOut.transform(k);
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Alice is thinking',
      child: RepaintBoundary(
        child: SizedBox(
          height: 26,
          child: AnimatedBuilder(
            animation: _c,
            builder: (context, _) {
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < 3; i++)
                    Padding(
                      padding: EdgeInsets.only(right: i < 2 ? 5 : 0),
                      child: Builder(builder: (context) {
                        final k = _bump(i * 0.15);
                        return Opacity(
                          opacity: 0.45 + 0.55 * k,
                          child: Transform.translate(
                            offset: Offset(0, -7 * k),
                            child: Container(
                              width: 8,
                              height: 8,
                              decoration: const BoxDecoration(
                                color: kAccent,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                        );
                      }),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Fades a new message in while sliding it up a few pixels.
class FadeSlideIn extends StatelessWidget {
  const FadeSlideIn({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
      child: child,
      builder: (context, v, child) => Opacity(
        opacity: v,
        child: Transform.translate(
          offset: Offset(0, 8 * (1 - v)),
          child: child,
        ),
      ),
    );
  }
}