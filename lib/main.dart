import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  runApp(const ClapperboardApp());
}

class ClapperboardApp extends StatelessWidget {
  const ClapperboardApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Clapperboard',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: Colors.black,
      ),
      home: const ClapperboardScreen(),
    );
  }
}

// -----------------------------------------------------------------------------
// Data model
// -----------------------------------------------------------------------------

class ClapData {
  String title;
  String scene;
  String take;
  String roll;
  String camera;
  String aperture;
  String fps;
  String shutter;
  String lens;
  String sound;
  String notes;

  ClapData({
    this.title = '',
    this.scene = '1',
    this.take = '1',
    this.roll = '',
    this.camera = '',
    this.aperture = '',
    this.fps = '',
    this.shutter = '',
    this.lens = '',
    this.sound = '',
    this.notes = '',
  });

  Map<String, dynamic> toJson() => {
        'title': title,
        'scene': scene,
        'take': take,
        'roll': roll,
        'camera': camera,
        'aperture': aperture,
        'fps': fps,
        'shutter': shutter,
        'lens': lens,
        'sound': sound,
        'notes': notes,
      };

  factory ClapData.fromJson(Map<String, dynamic> j) => ClapData(
        title: j['title'] ?? '',
        scene: j['scene'] ?? '1',
        take: j['take'] ?? '1',
        roll: j['roll'] ?? '',
        camera: j['camera'] ?? '',
        aperture: j['aperture'] ?? '',
        fps: j['fps'] ?? '',
        shutter: j['shutter'] ?? '',
        lens: j['lens'] ?? '',
        sound: j['sound'] ?? '',
        notes: j['notes'] ?? '',
      );

  // Access by field key (the same keys used for history and JSON).
  String get(String field) => switch (field) {
        'title' => title,
        'scene' => scene,
        'take' => take,
        'roll' => roll,
        'camera' => camera,
        'aperture' => aperture,
        'fps' => fps,
        'shutter' => shutter,
        'lens' => lens,
        'sound' => sound,
        'notes' => notes,
        _ => '',
      };

  void set(String field, String value) {
    switch (field) {
      case 'title':
        title = value;
      case 'scene':
        scene = value;
      case 'take':
        take = value;
      case 'roll':
        roll = value;
      case 'camera':
        camera = value;
      case 'aperture':
        aperture = value;
      case 'fps':
        fps = value;
      case 'shutter':
        shutter = value;
      case 'lens':
        lens = value;
      case 'sound':
        sound = value;
      case 'notes':
        notes = value;
    }
  }
}

// Fixed text shown around a field's value so it never has to be typed:
// aperture reads "f/2.8", shutter reads "1/50s". Only the variable part
// ("2.8", "50") is stored.
const Map<String, ({String prefix, String suffix})> kFieldAffixes = {
  'aperture': (prefix: 'f/', suffix: ''),
  'shutter': (prefix: '1/', suffix: 's'),
};

// Removes a typed-in copy of the field's fixed prefix/suffix, so "F/2.8" and
// "2.8" are stored the same way. Fields without affixes are returned as is.
String stripAffixes(String field, String value) {
  final affix = kFieldAffixes[field];
  if (affix == null) return value;
  var v = value.trim();
  if (affix.prefix.isNotEmpty &&
      v.toLowerCase().startsWith(affix.prefix.toLowerCase())) {
    v = v.substring(affix.prefix.length).trimLeft();
  }
  if (affix.suffix.isNotEmpty &&
      v.toLowerCase().endsWith(affix.suffix.toLowerCase())) {
    v = v.substring(0, v.length - affix.suffix.length).trimRight();
  }
  return v;
}

// The value as shown on the board: with its fixed prefix/suffix, or empty if
// there is no value.
String displayValue(String field, String value) {
  final affix = kFieldAffixes[field];
  if (affix == null) return value;
  final v = stripAffixes(field, value);
  return v.isEmpty ? '' : '${affix.prefix}$v${affix.suffix}';
}

class Preset {
  final String name;
  final String title;
  final String roll;
  final String camera;
  final String aperture;
  final String fps;
  final String shutter;
  final String lens;
  final String sound;

  Preset({
    required this.name,
    required this.title,
    required this.roll,
    required this.camera,
    required this.aperture,
    required this.fps,
    required this.shutter,
    required this.lens,
    required this.sound,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'title': title,
        'roll': roll,
        'camera': camera,
        'aperture': aperture,
        'fps': fps,
        'shutter': shutter,
        'lens': lens,
        'sound': sound,
      };

  factory Preset.fromJson(Map<String, dynamic> j) => Preset(
        name: j['name'] ?? '',
        title: j['title'] ?? '',
        roll: j['roll'] ?? '',
        camera: j['camera'] ?? '',
        aperture: j['aperture'] ?? '',
        fps: j['fps'] ?? '',
        shutter: j['shutter'] ?? '',
        lens: j['lens'] ?? '',
        sound: j['sound'] ?? '',
      );

  factory Preset.fromClap(String name, ClapData c) => Preset(
        name: name,
        title: c.title,
        roll: c.roll,
        camera: c.camera,
        aperture: c.aperture,
        fps: c.fps,
        shutter: c.shutter,
        lens: c.lens,
        sound: c.sound,
      );
}

// -----------------------------------------------------------------------------
// Main screen
// -----------------------------------------------------------------------------

class ClapperboardScreen extends StatefulWidget {
  const ClapperboardScreen({super.key});

  @override
  State<ClapperboardScreen> createState() => _ClapperboardScreenState();
}

class _ClapperboardScreenState extends State<ClapperboardScreen>
    with SingleTickerProviderStateMixin {
  static const _kDataKey = 'clap_data';
  static const _kPresetsKey = 'clap_presets';
  static const _kTextSizeKey = 'text_size';
  static const _kBgColorKey = 'bg_color';
  static const _kFgColorKey = 'fg_color';
  static const _kHistoryKey = 'clap_history';
  static const _kShowSceneRowKey = 'show_scene_row';
  static const _kRowSizesKey = 'row_sizes';
  static const _kCountdownOnKey = 'clap_countdown_on';
  static const _kCountdownSecsKey = 'clap_countdown_secs';
  static const _kChartModeKey = 'color_chart';
  static const _kMouseClapKey = 'mouse_clap';

  // Which mouse button claps from anywhere on the board, no aiming needed.
  static const Map<String, String> _mouseClapModes = {
    'off': 'Off',
    'right': 'Right button',
    'middle': 'Middle button',
  };

  // Keys from a presentation clicker (or any Bluetooth/USB keyboard).
  // Logitech presenters send Page Down for "next" and Page Up for "back";
  // the arrows cover clickers set to send arrow keys instead.
  static final Set<LogicalKeyboardKey> _clapKeys = {
    LogicalKeyboardKey.pageDown,
    LogicalKeyboardKey.arrowRight,
    LogicalKeyboardKey.space,
    LogicalKeyboardKey.enter,
    LogicalKeyboardKey.numpadEnter,
  };
  static final Set<LogicalKeyboardKey> _takeUpKeys = {
    LogicalKeyboardKey.pageUp,
    LogicalKeyboardKey.arrowLeft,
    LogicalKeyboardKey.arrowUp,
  };
  static final Set<LogicalKeyboardKey> _takeDownKeys = {
    LogicalKeyboardKey.arrowDown,
  };

  // Where the colour calibration sheet is shown.
  static const Map<String, String> _chartModes = {
    'off': 'Off',
    'notes': 'Notes',
    'full': 'Fullscreen',
  };

  static const int _clapDurationMs = 1000;
  static const int _maxCountdownSecs = 600;
  static const int _maxHistory = 10;
  static const String _clapCredit = 'Clapboard by Adaminion';

  static const double _dividerThickness = 5;
  // Gap between the screen edge and the outer frame.
  static const double _frameMargin = 8;
  // Height of the invisible grab strip over each horizontal divider.
  static const double _dragHandleHeight = 28;
  static const double _minRowPx = 36;
  // Most of the board height the fixed rows may take between them.
  static const double _maxFixedShare = 0.75;

  // Rows top to bottom. 'scene' (SCENE / TAKE / ROLL) can be hidden.
  static const List<String> _rowOrder = [
    'title',
    'date',
    'scene',
    'camera',
    'shutter',
    'bar',
  ];
  // Default px height (at text size M) of the rows that don't flex.
  static const Map<String, double> _fixedRowBase = {
    'title': 56,
    'date': 44,
    'bar': 144,
  };
  // Fixed rows: multiplier of their default height. Grid rows: flex weight
  // for sharing whatever height the fixed rows leave.
  static const Map<String, double> _defaultRowSizes = {
    'title': 1,
    'date': 1,
    'scene': 2,
    'camera': 1,
    'shutter': 1,
    'bar': 1,
  };

  // Fields that keep a list of remembered values, in board order.
  static const List<(String, String)> _listFields = [
    ('title', 'TITLE'),
    ('scene', 'SCENE'),
    ('take', 'TAKE'),
    ('roll', 'ROLL'),
    ('camera', 'CAMERA'),
    ('aperture', 'APERTURE'),
    ('fps', 'FPS'),
    ('shutter', 'SHUTTER'),
    ('lens', 'LENS'),
    ('sound', 'SOUND'),
    ('notes', 'NOTES'),
  ];

  static const Map<String, double> _textScales = {
    'S': 0.85,
    'M': 1.0,
    'L': 1.5,
    'XL': 2.0,
  };

  // The swatch palette used by the color picker.
  static const List<Color> _swatches = [
    Colors.black,
    Color(0xFF222222),
    Color(0xFF555555),
    Color(0xFF999999),
    Color(0xFFCCCCCC),
    Colors.white,
    Color(0xFFE53935), // red
    Color(0xFFFB8C00), // orange
    Color(0xFFFDD835), // yellow
    Color(0xFF43A047), // green
    Color(0xFF1E88E5), // blue
    Color(0xFF8E24AA), // purple
    Color(0xFFD81B60), // pink
    Color(0xFF00ACC1), // cyan
    Color(0xFF6D4C41), // brown
    Color(0xFFFFB300), // amber
  ];

  ClapData _data = ClapData();
  List<Preset> _presets = [];
  Map<String, List<String>> _history = {};
  String _textSize = 'M';
  Color _bgColor = Colors.black;
  Color _fgColor = Colors.white;
  bool _showSceneRow = true;
  // Row sizes the user has changed by dragging a divider; see
  // [_defaultRowSizes] for what the numbers mean.
  Map<String, double> _rowSizes = {};
  // Optional countdown between tapping CLAP and the flash.
  bool _countdownOn = false;
  int _countdownSecs = 10;
  // 'off', 'notes' (behind the notes panel) or 'full' (behind everything).
  String _chartMode = 'off';
  String _mouseClap = 'right';
  DateTime _now = DateTime.now();
  Timer? _clockTimer;
  SharedPreferences? _prefs;
  String _buildInfo = '';

  // A clap run is an optional countdown ([_clapLeadMs] long) followed by the
  // flash. The ticker reports the time since CLAP was tapped.
  late final Ticker _clapTicker;
  bool _clapRunning = false;
  Duration _clapElapsed = Duration.zero;
  int _clapLeadMs = 0;
  bool _flashAnnounced = false;

  double get _scale => _textScales[_textSize] ?? 1.0;

  bool get _countingDown =>
      _clapRunning && _clapElapsed.inMilliseconds < _clapLeadMs;

  // True during the flash itself.
  bool get _clapping =>
      _clapRunning && _clapElapsed.inMilliseconds >= _clapLeadMs;

  int get _countdownRemainingMs =>
      math.max(0, _clapLeadMs - _clapElapsed.inMilliseconds);

  int get _clapRemainingMs => math.max(
      0, _clapLeadMs + _clapDurationMs - _clapElapsed.inMilliseconds);

  @override
  void initState() {
    super.initState();
    _clapTicker = createTicker(_onClapTick);
    HardwareKeyboard.instance.addHandler(_onKey);
    _load();
    _loadBuildInfo();
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    HardwareKeyboard.instance.removeHandler(_onKey);
    if (kIsWeb) BrowserContextMenu.enableContextMenu();
    _clapTicker.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Persistence
  // ---------------------------------------------------------------------------

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    _prefs = prefs;
    final raw = prefs.getString(_kDataKey);
    if (raw != null) {
      try {
        _data = ClapData.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      } catch (_) {}
    }
    final presetsRaw = prefs.getString(_kPresetsKey);
    if (presetsRaw != null) {
      try {
        final list = jsonDecode(presetsRaw) as List<dynamic>;
        _presets = list
            .map((e) => Preset.fromJson(e as Map<String, dynamic>))
            .toList();
      } catch (_) {}
    }
    final savedTextSize = prefs.getString(_kTextSizeKey);
    if (savedTextSize != null && _textScales.containsKey(savedTextSize)) {
      _textSize = savedTextSize;
    }
    final bgVal = prefs.getInt(_kBgColorKey);
    final fgVal = prefs.getInt(_kFgColorKey);
    if (bgVal != null) _bgColor = Color(bgVal);
    if (fgVal != null) _fgColor = Color(fgVal);
    final historyRaw = prefs.getString(_kHistoryKey);
    if (historyRaw != null) {
      try {
        final m = jsonDecode(historyRaw) as Map<String, dynamic>;
        _history = m.map((k, v) => MapEntry(
              k,
              (v as List).map((e) => e.toString()).toList(),
            ));
      } catch (_) {}
    }
    _showSceneRow = prefs.getBool(_kShowSceneRowKey) ?? true;
    _countdownOn = prefs.getBool(_kCountdownOnKey) ?? false;
    final savedSecs = prefs.getInt(_kCountdownSecsKey);
    if (savedSecs != null && savedSecs >= 1 && savedSecs <= _maxCountdownSecs) {
      _countdownSecs = savedSecs;
    }
    final savedChart = prefs.getString(_kChartModeKey);
    if (savedChart != null && _chartModes.containsKey(savedChart)) {
      _chartMode = savedChart;
    }
    final savedMouse = prefs.getString(_kMouseClapKey);
    if (savedMouse != null && _mouseClapModes.containsKey(savedMouse)) {
      _mouseClap = savedMouse;
    }
    await _applyContextMenu();
    final rowSizesRaw = prefs.getString(_kRowSizesKey);
    if (rowSizesRaw != null) {
      try {
        final m = jsonDecode(rowSizesRaw) as Map<String, dynamic>;
        _rowSizes = {
          for (final e in m.entries)
            if (_defaultRowSizes.containsKey(e.key) &&
                e.value is num &&
                (e.value as num).isFinite &&
                (e.value as num) > 0)
              e.key: (e.value as num).toDouble(),
        };
      } catch (_) {}
    }
    if (mounted) setState(() {});
  }

  Future<void> _saveRowSizes() async {
    await _prefs?.setString(_kRowSizesKey, jsonEncode(_rowSizes));
  }

  Future<void> _saveData() async {
    await _prefs?.setString(_kDataKey, jsonEncode(_data.toJson()));
  }

  Future<void> _savePresets() async {
    await _prefs?.setString(
      _kPresetsKey,
      jsonEncode(_presets.map((p) => p.toJson()).toList()),
    );
  }

  Future<void> _saveColors() async {
    await _prefs?.setInt(_kBgColorKey, _colorToInt(_bgColor));
    await _prefs?.setInt(_kFgColorKey, _colorToInt(_fgColor));
  }

  Future<void> _saveHistory() async {
    await _prefs?.setString(_kHistoryKey, jsonEncode(_history));
  }

  // Push a value to the front of [field]'s history. Empty values are ignored;
  // duplicates are moved to the front; the list is capped at [_maxHistory].
  void _pushHistory(String field, String value) {
    final v = stripAffixes(field, value).trim();
    if (v.isEmpty) return;
    final list = List<String>.from(_history[field] ?? const <String>[]);
    list.remove(v);
    list.insert(0, v);
    while (list.length > _maxHistory) {
      list.removeLast();
    }
    _history[field] = list;
    _saveHistory();
  }

  int _colorToInt(Color c) {
    return ((c.a * 255).round() & 0xff) << 24 |
        ((c.r * 255).round() & 0xff) << 16 |
        ((c.g * 255).round() & 0xff) << 8 |
        ((c.b * 255).round() & 0xff);
  }

  Future<void> _loadBuildInfo() async {
    try {
      final pubspec = await rootBundle.loadString('pubspec.yaml');
      final m = RegExp(r'^version:\s*(\S+)', multiLine: true).firstMatch(pubspec);
      if (m != null && mounted) {
        setState(() => _buildInfo = m.group(1) ?? '');
      }
    } catch (_) {}
  }

  // ---------------------------------------------------------------------------
  // Clap
  // ---------------------------------------------------------------------------

  // Tap on CLAP. With the countdown option on, the flash follows after the
  // chosen number of seconds; a second tap during the countdown cancels it.
  void _clap() {
    HapticFeedback.heavyImpact();
    if (_countingDown) {
      _stopClap();
      return;
    }
    _clapTicker.stop();
    setState(() {
      _clapRunning = true;
      _clapElapsed = Duration.zero;
      _clapLeadMs = _countdownOn ? _countdownSecs * 1000 : 0;
      _flashAnnounced = _clapLeadMs == 0;
    });
    _clapTicker.start();
  }

  void _onClapTick(Duration elapsed) {
    final ms = elapsed.inMilliseconds;
    if (ms >= _clapLeadMs + _clapDurationMs) {
      _stopClap();
      return;
    }
    if (!_flashAnnounced && ms >= _clapLeadMs) {
      // The countdown just ran out: this is the clap.
      _flashAnnounced = true;
      HapticFeedback.heavyImpact();
    }
    setState(() => _clapElapsed = elapsed);
  }

  void _stopClap() {
    _clapTicker.stop();
    setState(() {
      _clapRunning = false;
      _clapElapsed = Duration.zero;
    });
  }

  // ---------------------------------------------------------------------------
  // Remote control: clicker / keyboard / mouse
  // ---------------------------------------------------------------------------

  // Only the board itself reacts: not while the menu, a dialog or the
  // remembered-values page is open (keys are for typing there).
  bool get _boardInFront => ModalRoute.of(context)?.isCurrent ?? true;

  bool _onKey(KeyEvent event) {
    // Holding a button down must not fire again and again.
    if (event is! KeyDownEvent || !mounted || !_boardInFront) return false;
    final key = event.logicalKey;
    if (_clapKeys.contains(key)) {
      _clap();
    } else if (_takeUpKeys.contains(key)) {
      _bumpTake(1);
    } else if (_takeDownKeys.contains(key)) {
      _bumpTake(-1);
    } else {
      return false;
    }
    return true;
  }

  void _onPointerDown(PointerDownEvent event) {
    if (event.kind != PointerDeviceKind.mouse || !_boardInFront) return;
    final button = switch (_mouseClap) {
      'right' => kSecondaryMouseButton,
      'middle' => kMiddleMouseButton,
      _ => 0,
    };
    if (button != 0 && event.buttons & button != 0) _clap();
  }

  // In the browser a right click opens the page's context menu; turn that
  // off while the right button is the clap button.
  Future<void> _applyContextMenu() async {
    if (!kIsWeb) return;
    try {
      if (_mouseClap == 'right') {
        await BrowserContextMenu.disableContextMenu();
      } else {
        await BrowserContextMenu.enableContextMenu();
      }
    } catch (_) {}
  }

  // ---------------------------------------------------------------------------
  // Field mutation
  // ---------------------------------------------------------------------------

  void _bumpScene(int delta) {
    setState(() {
      _data.scene = _adjustNumeric(_data.scene, delta);
    });
    _saveData();
  }

  void _bumpTake(int delta) {
    setState(() {
      _data.take = _adjustNumeric(_data.take, delta);
    });
    _saveData();
  }

  String _adjustNumeric(String current, int delta) {
    final n = int.tryParse(current.trim());
    if (n == null) return delta > 0 ? '1' : '0';
    final next = n + delta;
    return (next < 0 ? 0 : next).toString();
  }

  // Clear used by SCENE/TAKE X: push current to history (if any), then clear.
  void _clearWithHistory(String field, String current, void Function() mutate) {
    if (current.isNotEmpty) _pushHistory(field, current);
    setState(mutate);
    _saveData();
  }

  // Tap on a cell — show the saved history of that field as a popup menu
  // anchored to the cell's bottom-left. Selecting an entry sets the field's
  // value and moves that entry back to the top of the history. No-op if the
  // history is empty.
  Future<void> _showHistoryMenuAt(
    BuildContext cellContext,
    String field,
    void Function(String) onSet,
  ) async {
    final history = _history[field] ?? const <String>[];
    if (history.isEmpty) return;
    final RenderBox box = cellContext.findRenderObject() as RenderBox;
    final RenderBox overlay =
        Overlay.of(cellContext).context.findRenderObject() as RenderBox;
    final topLeft = box.localToGlobal(Offset.zero, ancestor: overlay);
    final bottomRight = box.localToGlobal(
      box.size.bottomRight(Offset.zero),
      ancestor: overlay,
    );
    final selected = await showMenu<String>(
      context: cellContext,
      position: RelativeRect.fromLTRB(
        topLeft.dx,
        bottomRight.dy,
        overlay.size.width - bottomRight.dx,
        overlay.size.height - bottomRight.dy,
      ),
      items: history
          .map((h) => PopupMenuItem<String>(
                value: h,
                child: Text(displayValue(field, h)),
              ))
          .toList(),
    );
    if (selected != null) {
      setState(() => onSet(selected));
      _pushHistory(field, selected);
      _saveData();
    }
  }

  // Long-press on a cell — push the current value to history (so it can be
  // recalled later), then open an *empty* edit dialog for fresh input. On OK,
  // also push the new value to history.
  Future<void> _longPressEdit(
    String label,
    String field,
    String current,
    void Function(String) onSet, {
    TextInputType keyboard = TextInputType.text,
  }) async {
    if (current.trim().isNotEmpty) {
      _pushHistory(field, current);
    }
    final controller = TextEditingController();
    final affix = kFieldAffixes[field];
    final typed = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Edit $label'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: keyboard,
          textCapitalization: TextCapitalization.characters,
          decoration: InputDecoration(
            hintText: label,
            // The fixed parts ("f/", "1/…s") are shown, not typed.
            prefixText: affix?.prefix,
            suffixText: affix?.suffix,
          ),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, controller.text),
              child: const Text('OK')),
        ],
      ),
    );
    if (typed != null) {
      final value = stripAffixes(field, typed);
      setState(() => onSet(value));
      if (value.trim().isNotEmpty) {
        _pushHistory(field, value);
      }
      _saveData();
    }
  }

  // Opens the full-screen editor for every field's remembered values, then
  // stores what comes back: blanks dropped, duplicates collapsed.
  Future<void> _editLists() async {
    final slots = <String, List<String>>{
      for (final (field, _) in _listFields)
        field: List<String>.generate(_maxHistory, (i) {
          final h = _history[field] ?? const <String>[];
          return i < h.length ? stripAffixes(field, h[i]) : '';
        }),
    };
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => _ListsEditorPage(fields: _listFields, slots: slots),
    ));
    final next = Map<String, List<String>>.of(_history);
    slots.forEach((field, values) {
      final seen = <String>{};
      final cleaned = [
        for (final v in values.map((v) => stripAffixes(field, v).trim()))
          if (v.isNotEmpty && seen.add(v)) v,
      ];
      if (cleaned.isEmpty) {
        next.remove(field);
      } else {
        next[field] = cleaned;
      }
    });
    _history = next;
    if (mounted) setState(() {});
    await _saveHistory();
  }

  // ---------------------------------------------------------------------------
  // Menu and dialogs
  // ---------------------------------------------------------------------------

  Future<void> _openMenu() async {
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.grey[900],
      // Size to the content and scroll when the screen is too short for it.
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.save, color: Colors.white),
              title: const Text('Save preset',
                  style: TextStyle(color: Colors.white)),
              onTap: () => Navigator.pop(ctx, 'save'),
            ),
            ListTile(
              leading: const Icon(Icons.folder_open, color: Colors.white),
              title: const Text('Load preset',
                  style: TextStyle(color: Colors.white)),
              onTap: () => Navigator.pop(ctx, 'load'),
            ),
            ListTile(
              leading: const Icon(Icons.edit_note, color: Colors.white),
              title: const Text('Edit remembered values',
                  style: TextStyle(color: Colors.white)),
              onTap: () => Navigator.pop(ctx, 'lists'),
            ),
            const Divider(color: Colors.white24, height: 1),
            ListTile(
              leading: Icon(
                _showSceneRow
                    ? Icons.check_box
                    : Icons.check_box_outline_blank,
                color: Colors.white,
              ),
              title: const Text('Show SCENE / TAKE / ROLL row',
                  style: TextStyle(color: Colors.white)),
              onTap: () => Navigator.pop(ctx, 'scenerow'),
            ),
            ListTile(
              leading: const Icon(Icons.height, color: Colors.white),
              title: const Text('Reset row heights',
                  style: TextStyle(color: Colors.white)),
              onTap: () => Navigator.pop(ctx, 'resetrows'),
            ),
            const Divider(color: Colors.white24, height: 1),
            ListTile(
              leading: Icon(
                _countdownOn
                    ? Icons.check_box
                    : Icons.check_box_outline_blank,
                color: Colors.white,
              ),
              title: Text(
                  _countdownOn
                      ? 'Countdown before clap: $_countdownSecs s'
                      : 'Countdown before clap',
                  style: const TextStyle(color: Colors.white)),
              onTap: () => Navigator.pop(ctx, 'countdown'),
            ),
            ListTile(
              leading: const Icon(Icons.gradient, color: Colors.white),
              title: Text(
                  'Color calibration sheet: ${_chartModes[_chartMode]}',
                  style: const TextStyle(color: Colors.white)),
              onTap: () => Navigator.pop(ctx, 'chart'),
            ),
            ListTile(
              leading: const Icon(Icons.mouse, color: Colors.white),
              title: Text(
                  'Mouse click to clap: ${_mouseClapModes[_mouseClap]}',
                  style: const TextStyle(color: Colors.white)),
              onTap: () => Navigator.pop(ctx, 'mouse'),
            ),
            const Divider(color: Colors.white24, height: 1),
            ListTile(
              leading: const Icon(Icons.format_size, color: Colors.white),
              title: Text('Text size: $_textSize',
                  style: const TextStyle(color: Colors.white)),
              onTap: () => Navigator.pop(ctx, 'textsize'),
            ),
            ListTile(
              leading: const Icon(Icons.swap_horiz, color: Colors.white),
              title: const Text('Reverse colors',
                  style: TextStyle(color: Colors.white)),
              onTap: () => Navigator.pop(ctx, 'reverse'),
            ),
            ListTile(
              leading: const Icon(Icons.format_color_fill, color: Colors.white),
              title: const Text('Background color',
                  style: TextStyle(color: Colors.white)),
              onTap: () => Navigator.pop(ctx, 'bg'),
            ),
            ListTile(
              leading: const Icon(Icons.format_color_text, color: Colors.white),
              title: const Text('Text color',
                  style: TextStyle(color: Colors.white)),
              onTap: () => Navigator.pop(ctx, 'fg'),
            ),
            const Divider(color: Colors.white24, height: 1),
            ListTile(
              leading: const Icon(Icons.refresh, color: Colors.white),
              title: const Text('Reset scene & take to 1',
                  style: TextStyle(color: Colors.white)),
              onTap: () => Navigator.pop(ctx, 'reset'),
            ),
          ],
          ),
        ),
      ),
    );
    if (!mounted) return;
    switch (action) {
      case 'lists':
        await _editLists();
        break;
      case 'scenerow':
        setState(() => _showSceneRow = !_showSceneRow);
        await _prefs?.setBool(_kShowSceneRowKey, _showSceneRow);
        break;
      case 'resetrows':
        setState(() => _rowSizes = {});
        await _saveRowSizes();
        break;
      case 'save':
        await _savePresetDialog();
        break;
      case 'load':
        await _loadPresetDialog();
        break;
      case 'textsize':
        await _textSizeDialog();
        break;
      case 'reverse':
        setState(() {
          final tmp = _bgColor;
          _bgColor = _fgColor;
          _fgColor = tmp;
        });
        await _saveColors();
        break;
      case 'bg':
        final picked = await _pickColor('Background color', _bgColor);
        if (picked != null) {
          setState(() => _bgColor = picked);
          await _saveColors();
        }
        break;
      case 'fg':
        final picked = await _pickColor('Text color', _fgColor);
        if (picked != null) {
          setState(() => _fgColor = picked);
          await _saveColors();
        }
        break;
      case 'countdown':
        await _toggleCountdown();
        break;
      case 'chart':
        final picked = await _pickOption(
            'Color calibration sheet', _chartModes, _chartMode);
        if (picked != null) {
          setState(() => _chartMode = picked);
          await _prefs?.setString(_kChartModeKey, picked);
        }
        break;
      case 'mouse':
        final picked = await _pickOption(
            'Mouse click to clap', _mouseClapModes, _mouseClap);
        if (picked != null) {
          setState(() => _mouseClap = picked);
          await _prefs?.setString(_kMouseClapKey, picked);
          await _applyContextMenu();
        }
        break;
      case 'reset':
        setState(() {
          _data.scene = '1';
          _data.take = '1';
        });
        _saveData();
        break;
    }
  }

  // Unchecking turns the countdown off. Checking it asks for the number of
  // seconds first (last value used, 10 to begin with).
  Future<void> _toggleCountdown() async {
    if (_countdownOn) {
      setState(() => _countdownOn = false);
      await _prefs?.setBool(_kCountdownOnKey, false);
      return;
    }
    final text = '$_countdownSecs';
    final controller = TextEditingController(text: text)
      ..selection = TextSelection(baseOffset: 0, extentOffset: text.length);
    final typed = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Countdown before clap'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(suffixText: 'seconds'),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, controller.text),
              child: const Text('OK')),
        ],
      ),
    );
    if (typed == null) return;
    final secs = int.tryParse(typed.trim());
    setState(() {
      _countdownOn = true;
      // Anything that isn't a usable number keeps the previous value.
      if (secs != null && secs >= 1) {
        _countdownSecs = math.min(secs, _maxCountdownSecs);
      }
    });
    await _prefs?.setBool(_kCountdownOnKey, true);
    await _prefs?.setInt(_kCountdownSecsKey, _countdownSecs);
  }

  // A list of choices with a check next to the current one.
  Future<String?> _pickOption(
    String title,
    Map<String, String> options,
    String current,
  ) {
    return showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(title),
        children: options.entries
            .map((e) => SimpleDialogOption(
                  onPressed: () => Navigator.pop(ctx, e.key),
                  child: Row(
                    children: [
                      Text(e.value),
                      if (e.key == current) ...const [
                        SizedBox(width: 12),
                        Icon(Icons.check, size: 18),
                      ],
                    ],
                  ),
                ))
            .toList(),
      ),
    );
  }

  Future<void> _textSizeDialog() async {
    final picked = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Text size'),
        children: _textScales.keys
            .map((k) => SimpleDialogOption(
                  onPressed: () => Navigator.pop(ctx, k),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 40,
                        child: Text(k,
                            style: const TextStyle(
                                fontWeight: FontWeight.bold)),
                      ),
                      Text('× ${_textScales[k]!.toStringAsFixed(2)}'),
                      if (k == _textSize) ...const [
                        SizedBox(width: 12),
                        Icon(Icons.check, size: 18),
                      ],
                    ],
                  ),
                ))
            .toList(),
      ),
    );
    if (picked != null) {
      setState(() => _textSize = picked);
      await _prefs?.setString(_kTextSizeKey, picked);
    }
  }

  Future<Color?> _pickColor(String title, Color current) async {
    return showDialog<Color>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 360,
          child: Wrap(
            spacing: 10,
            runSpacing: 10,
            children: _swatches.map((c) {
              final selected = _colorToInt(c) == _colorToInt(current);
              return InkWell(
                onTap: () => Navigator.pop(ctx, c),
                child: Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: c,
                    border: Border.all(
                      color: selected ? Colors.blue : Colors.grey.shade400,
                      width: selected ? 3 : 1,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
        ],
      ),
    );
  }

  Future<void> _savePresetDialog() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Preset name'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'e.g. Scene 1 setup'),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, controller.text),
              child: const Text('Save')),
        ],
      ),
    );
    if (name == null || name.trim().isEmpty) return;
    final preset = Preset.fromClap(name.trim(), _data);
    setState(() {
      _presets.removeWhere((p) => p.name == preset.name);
      _presets.add(preset);
    });
    await _savePresets();
  }

  Future<void> _loadPresetDialog() async {
    if (_presets.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No presets saved yet')),
      );
      return;
    }
    final picked = await showDialog<Preset>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Load preset'),
        children: _presets
            .map((p) => SimpleDialogOption(
                  onPressed: () => Navigator.pop(ctx, p),
                  child: Row(
                    children: [
                      Expanded(child: Text(p.name)),
                      IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () async {
                          setState(() => _presets.remove(p));
                          await _savePresets();
                          if (ctx.mounted) Navigator.pop(ctx);
                        },
                      ),
                    ],
                  ),
                ))
            .toList(),
      ),
    );
    if (picked != null) {
      setState(() {
        _data.title = picked.title;
        _data.roll = picked.roll;
        _data.camera = picked.camera;
        _data.aperture = picked.aperture;
        _data.fps = picked.fps;
        _data.shutter = picked.shutter;
        _data.lens = picked.lens;
        _data.sound = picked.sound;
      });
      _saveData();
    }
  }

  String _fmtDateTime(DateTime d) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)}  '
        '${two(d.hour)}:${two(d.minute)}:${two(d.second)}';
  }

  // ---------------------------------------------------------------------------
  // Row layout
  // ---------------------------------------------------------------------------

  List<String> get _visibleRows => [
        for (final r in _rowOrder)
          if (r != 'scene' || _showSceneRow) r,
      ];

  bool _isFixedRow(String row) => _fixedRowBase.containsKey(row);

  double _rowSize(String row) => _rowSizes[row] ?? _defaultRowSizes[row]!;

  // Height in px of a fixed row whose size multiplier is 1.0. Follows the text
  // size setting, and shrinks on short screens (phones in landscape) so the
  // fixed rows don't starve the grid.
  double _fixedUnit(String row, double avail) =>
      _fixedRowBase[row]! * _scale * (avail / 500).clamp(0.5, 1.0);

  // Heights in px of the visible rows, given the height left for them once the
  // dividers between them are subtracted.
  Map<String, double> _rowHeights(double avail) {
    final rows = _visibleRows;
    final heights = <String, double>{};
    var fixedSum = 0.0;
    var weightSum = 0.0;
    for (final r in rows) {
      if (_isFixedRow(r)) {
        final h = _fixedUnit(r, avail) * _rowSize(r);
        heights[r] = h;
        fixedSum += h;
      } else {
        weightSum += _rowSize(r);
      }
    }
    final maxFixed = avail * _maxFixedShare;
    if (fixedSum > maxFixed) {
      final f = maxFixed / fixedSum;
      heights.updateAll((_, h) => h * f);
      fixedSum = maxFixed;
    }
    final rest = math.max(0.0, avail - fixedSum);
    for (final r in rows) {
      if (!_isFixedRow(r)) heights[r] = rest * _rowSize(r) / weightSum;
    }
    return heights;
  }

  // Drag of the horizontal divider below visible row [index]. The line under
  // a row sizes that row: it grows by [dy], and the space comes out of the
  // next row down that flexes (the header rows never give up height for each
  // other, they just shift). Fonts follow because every cell sizes its text
  // from its own height.
  void _dragDivider(int index, double dy, double avail) {
    final rows = _visibleRows;
    if (index < 0 || index >= rows.length - 1) return;
    final h = _rowHeights(avail);
    final above = rows[index];
    var j = index + 1;
    while (j < rows.length - 1 && _isFixedRow(rows[j])) {
      j++;
    }
    final below = rows[j];
    final lo = math.min(0.0, _minRowPx - h[above]!);
    final hi = math.max(0.0, h[below]! - _minRowPx);
    final d = dy.clamp(lo, hi).toDouble();
    if (d == 0) return;

    double fixedTotal() => rows
        .where(_isFixedRow)
        .fold(0.0, (sum, r) => sum + h[r]!);
    final fixedBefore = fixedTotal();
    h[above] = h[above]! + d;
    h[below] = h[below]! - d;
    final fixedAfter = fixedTotal();
    if (fixedAfter > fixedBefore && fixedAfter > avail * _maxFixedShare) return;

    // Convert the new pixel heights back into stored sizes: multipliers for
    // the fixed rows, flex weights (same total as before) for the grid rows.
    final grid = rows.where((r) => !_isFixedRow(r)).toList();
    final weightSum = grid.fold(0.0, (sum, r) => sum + _rowSize(r));
    final gridPx = grid.fold(0.0, (sum, r) => sum + h[r]!);
    setState(() {
      for (final r in rows) {
        if (_isFixedRow(r)) {
          _rowSizes[r] = h[r]! / _fixedUnit(r, avail);
        } else if (gridPx > 0) {
          _rowSizes[r] = h[r]! * weightSum / gridPx;
        }
      }
    });
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final bg = _clapping ? _fgColor : _bgColor;
    final fg = _clapping ? _bgColor : _fgColor;
    final dimFg = fg.withValues(alpha: 0.45);
    final divider = fg.withValues(alpha: 0.7);

    // The sheet gives way to the plain inverted screen during the flash, so
    // the flash stays unmistakable.
    final chartBehindAll = _chartMode == 'full' && !_clapping;

    // The Listener sees every mouse press anywhere on the board, before (and
    // without taking it from) the cell underneath.
    return Scaffold(
      backgroundColor: bg,
      // Keep the board still when the keyboard opens for an edit dialog.
      resizeToAvoidBottomInset: false,
      body: Listener(onPointerDown: _onPointerDown, child: Stack(
        fit: StackFit.expand,
        children: [
          if (chartBehindAll) const _ColorChart(),
          _haloed(
            on: chartBehindAll,
            color: bg,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(_frameMargin),
                // Outer frame. Container insets its child by the border width.
                child: Container(
                  decoration: BoxDecoration(
                    border:
                        Border.all(color: divider, width: _dividerThickness),
                  ),
                  child: LayoutBuilder(
                    builder: (_, c) => _buildBoard(c, fg, dimFg, divider, bg),
                  ),
                ),
              ),
            ),
          ),
        ],
      )),
    );
  }

  // Gives text and icons a halo in the background colour, so they stay
  // readable on top of the colour sheet. A no-op when [on] is false.
  Widget _haloed({
    required bool on,
    required Color color,
    required Widget child,
  }) {
    final shadows = on
        ? [
            Shadow(color: color, blurRadius: 2),
            Shadow(color: color, blurRadius: 6),
            Shadow(color: color, blurRadius: 12),
          ]
        : null;
    return DefaultTextStyle.merge(
      style: TextStyle(shadows: shadows),
      child: IconTheme.merge(
        data: IconThemeData(shadows: shadows),
        child: child,
      ),
    );
  }

  Widget _buildBoard(
    BoxConstraints c,
    Color fg,
    Color dimFg,
    Color divider,
    Color bg,
  ) {
    final portrait = c.maxHeight > c.maxWidth;
    final rows = _visibleRows;
    final avail =
        math.max(0.0, c.maxHeight - _dividerThickness * (rows.length - 1));
    final heights = _rowHeights(avail);

    final cells = <Widget>[];
    final handles = <Widget>[];
    var y = 0.0;
    for (var i = 0; i < rows.length; i++) {
      final row = rows[i];
      final h = heights[row]!;
      cells.add(Positioned(
        left: 0,
        right: 0,
        top: y,
        height: h,
        child:
            _buildRow(row, h, c.maxWidth, portrait, fg, dimFg, divider, bg),
      ));
      y += h;
      if (i == rows.length - 1) break;
      cells.add(Positioned(
        left: 0,
        right: 0,
        top: y,
        height: _dividerThickness,
        child: ColoredBox(color: divider),
      ));
      // Invisible grab strip centred on the divider line.
      handles.add(Positioned(
        left: 0,
        right: 0,
        top: y + (_dividerThickness - _dragHandleHeight) / 2,
        height: _dragHandleHeight,
        child: _RowDragHandle(
          key: ValueKey('divider-$row'),
          onDrag: (dy) => _dragDivider(i, dy, avail),
          onEnd: _saveRowSizes,
        ),
      ));
      y += _dividerThickness;
    }

    return Stack(
      children: [
        ...cells,
        ...handles,
        // Tiny build-number overlay in the bottom-right corner, inside the
        // frame so rounded screen corners can't clip it.
        if (_buildInfo.isNotEmpty)
          Positioned(
            right: 4,
            bottom: 2,
            child: IgnorePointer(
              child: Text(
                'v$_buildInfo',
                style: TextStyle(
                  color: dimFg.withValues(alpha: 0.5),
                  fontSize: 9,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildRow(
    String row,
    double h,
    double width,
    bool portrait,
    Color fg,
    Color dimFg,
    Color divider,
    Color bg,
  ) {
    switch (row) {
      case 'title':
        return _HeaderCell(
          label: 'TITLE',
          value: _data.title,
          fg: fg,
          height: h,
          onTap: (ctx) =>
              _showHistoryMenuAt(ctx, 'title', (v) => _data.title = v),
          onLongPress: () => _longPressEdit(
              'TITLE', 'title', _data.title, (v) => _data.title = v),
        );
      case 'date':
        return _HeaderCell(
          label: 'DATE/TIME',
          value: _fmtDateTime(_now),
          fg: fg,
          height: h,
          valueOnly: true,
        );
      case 'scene':
        return _tripleRow(divider, [
          _bumpCell('SCENE', 'scene', fg, dimFg, _bumpScene),
          _bumpCell('TAKE', 'take', fg, dimFg, _bumpTake),
          _simpleCell('ROLL', 'roll', fg),
        ]);
      case 'camera':
        return _tripleRow(divider, [
          _simpleCell('CAMERA', 'camera', fg),
          _simpleCell('APERTURE', 'aperture', fg),
          _simpleCell(
            'FPS',
            'fps',
            fg,
            labelRight: true,
            keyboard: const TextInputType.numberWithOptions(decimal: true),
          ),
        ]);
      case 'shutter':
        return _tripleRow(divider, [
          _simpleCell('SHUTTER', 'shutter', fg),
          _simpleCell('LENS', 'lens', fg),
          _simpleCell('SOUND', 'sound', fg),
        ]);
      default:
        return _buildBar(h, width, portrait, fg, dimFg, divider, bg);
    }
  }

  Widget _tripleRow(Color divider, List<Widget> cells) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: cells[0]),
        _VDivider(color: divider, thickness: _dividerThickness),
        Expanded(child: cells[1]),
        _VDivider(color: divider, thickness: _dividerThickness),
        Expanded(child: cells[2]),
      ],
    );
  }

  Widget _simpleCell(
    String label,
    String field,
    Color fg, {
    bool labelRight = false,
    TextInputType keyboard = TextInputType.text,
  }) {
    final value = _data.get(field);
    return _SimpleCell(
      label: label,
      value: displayValue(field, value),
      fg: fg,
      labelRight: labelRight,
      onTap: (ctx) =>
          _showHistoryMenuAt(ctx, field, (v) => _data.set(field, v)),
      onLongPress: () => _longPressEdit(
        label,
        field,
        value,
        (v) => _data.set(field, v),
        keyboard: keyboard,
      ),
    );
  }

  Widget _bumpCell(
    String label,
    String field,
    Color fg,
    Color dimFg,
    void Function(int) bump,
  ) {
    final value = _data.get(field);
    return _BumpCell(
      label: label,
      value: value,
      fg: fg,
      dimFg: dimFg,
      onTap: (ctx) =>
          _showHistoryMenuAt(ctx, field, (v) => _data.set(field, v)),
      onPlus: () => bump(1),
      onMinus: () => bump(-1),
      onClear: () =>
          _clearWithHistory(field, value, () => _data.set(field, '')),
      onLongPress: () =>
          _longPressEdit(label, field, value, (v) => _data.set(field, v)),
    );
  }

  // Bottom bar. Landscape: CLAP (1/3) | NOTES (2/3) | menu, side by side.
  // Portrait: NOTES across the full width, with CLAP | menu underneath, so
  // nothing is squeezed into a sliver on a narrow screen.
  Widget _buildBar(
    double h,
    double width,
    bool portrait,
    Color fg,
    Color dimFg,
    Color divider,
    Color bg,
  ) {
    // Countdown readout: whole seconds left, then the same millisecond timer
    // as the flash, running once per second.
    final secondsLeft = (_countdownRemainingMs + 999) ~/ 1000;
    final msInSecond = _countdownRemainingMs - (secondsLeft - 1) * 1000;

    Widget clap(double fontRef) => InkWell(
          onTap: _clap,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: _clapping
                    ? Text(
                        _clapRemainingMs.toString().padLeft(4, '0'),
                        style: TextStyle(
                          color: fg,
                          fontSize: fontRef * 0.44,
                          fontWeight: FontWeight.bold,
                          fontFeatures: const [
                            FontFeature.tabularFigures(),
                          ],
                          letterSpacing: 4,
                        ),
                      )
                    : _countingDown
                        ? Text.rich(
                            key: const ValueKey('clap-countdown'),
                            TextSpan(
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontFeatures: [FontFeature.tabularFigures()],
                              ),
                              children: [
                                TextSpan(
                                  text: '$secondsLeft',
                                  style: TextStyle(
                                    color: fg,
                                    fontSize: fontRef * 0.44,
                                  ),
                                ),
                                TextSpan(
                                  text: '  ${msInSecond.toString().padLeft(4, '0')}',
                                  style: TextStyle(
                                    color: dimFg,
                                    fontSize: fontRef * 0.22,
                                    letterSpacing: 2,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : Text(
                            'CLAP',
                            style: TextStyle(
                              color: dimFg,
                              fontSize: fontRef / 3,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 8,
                            ),
                          ),
              ),
            ),
          ),
        );

    final chartBehindNotes = _chartMode == 'notes' && !_clapping;
    Widget notes(double fontRef) => Stack(
          fit: StackFit.expand,
          children: [
            if (chartBehindNotes) const _ColorChart(),
            _haloed(
              on: chartBehindNotes,
              color: bg,
              child: _NotesPanel(
                notes: _data.notes,
                fg: fg,
                dimFg: dimFg,
                clapping: _clapping,
                creditText: _clapCredit,
                fontRef: fontRef,
                // Leave the sheet clean when there are no notes.
                showPlaceholder: !chartBehindNotes,
                onTap: (ctx) =>
                    _showHistoryMenuAt(ctx, 'notes', (v) => _data.notes = v),
                onLongPress: () => _longPressEdit(
                    'NOTES', 'notes', _data.notes, (v) => _data.notes = v),
              ),
            ),
          ],
        );

    Widget menu(double rowH) {
      final w = math.min(72 * _scale, width * 0.25);
      return SizedBox(
        width: w,
        child: IconButton(
          icon: Icon(
            Icons.menu,
            color: dimFg,
            size: math.min(32 * _scale, math.min(w, rowH) * 0.7),
          ),
          onPressed: _openMenu,
        ),
      );
    }

    if (!portrait) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(flex: 1, child: clap(h)),
          _VDivider(color: divider, thickness: _dividerThickness),
          Expanded(flex: 2, child: notes(h)),
          _VDivider(color: divider, thickness: _dividerThickness),
          menu(h),
        ],
      );
    }

    final notesH = math.max(0.0, (h - _dividerThickness) * 0.4);
    final clapH = math.max(0.0, h - _dividerThickness - notesH);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(height: notesH, child: notes(notesH * 2)),
        Container(height: _dividerThickness, color: divider),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: clap(clapH * 1.5)),
              _VDivider(color: divider, thickness: _dividerThickness),
              menu(clapH),
            ],
          ),
        ),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// Cells
// -----------------------------------------------------------------------------

// Inner padding of a grid cell: 10 px, less when the row is dragged very short.
double _cellPadding(double cellHeight) =>
    (cellHeight * 0.08).clamp(2.0, 10.0).toDouble();

class _HeaderCell extends StatelessWidget {
  final String label;
  final String value;
  final Color fg;
  final double height;
  final bool valueOnly;
  final void Function(BuildContext)? onTap;
  final VoidCallback? onLongPress;

  const _HeaderCell({
    required this.label,
    required this.value,
    required this.fg,
    required this.height,
    this.valueOnly = false,
    this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final shown = valueOnly ? value : (value.isEmpty ? label : value);
    return Builder(builder: (ctx) {
      return GestureDetector(
        onTap: onTap == null ? null : () => onTap!(ctx),
        onLongPress: onLongPress,
        behavior: HitTestBehavior.opaque,
        child: Container(
          height: height,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              shown,
              style: TextStyle(
                color: fg,
                fontSize: height * 0.55,
                letterSpacing: 2,
                fontWeight: valueOnly ? FontWeight.w500 : FontWeight.w600,
              ),
              maxLines: 1,
            ),
          ),
        ),
      );
    });
  }
}

class _SimpleCell extends StatelessWidget {
  final String label;
  final String value;
  final Color fg;
  // Put the label in the top-right corner, a bit larger, so it reads as a
  // unit after the value (used for FPS).
  final bool labelRight;
  final void Function(BuildContext) onTap;
  final VoidCallback onLongPress;

  const _SimpleCell({
    required this.label,
    required this.value,
    required this.fg,
    this.labelRight = false,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return Builder(builder: (ctx) {
      return LayoutBuilder(
        builder: (_, c) {
          final h = c.maxHeight;
          final labelH = h * 0.27;
          return GestureDetector(
            onTap: () => onTap(ctx),
            onLongPress: onLongPress,
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: EdgeInsets.all(_cellPadding(h)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: double.infinity,
                    height: labelH,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: labelRight
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      child: Text(
                        label,
                        style: TextStyle(
                          color: fg,
                          fontSize: labelH * (labelRight ? 0.85 : 0.7),
                          letterSpacing: 2,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Center(
                      child: value.isEmpty
                          ? const SizedBox.shrink()
                          : FittedBox(
                              fit: BoxFit.contain,
                              child: Text(
                                value,
                                style: TextStyle(
                                  color: fg,
                                  fontSize: 100,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    });
  }
}

class _BumpCell extends StatelessWidget {
  final String label;
  final String value;
  final Color fg;
  final Color dimFg;
  final void Function(BuildContext) onTap;
  final VoidCallback onPlus;
  final VoidCallback onMinus;
  final VoidCallback onClear;
  final VoidCallback onLongPress;

  const _BumpCell({
    required this.label,
    required this.value,
    required this.fg,
    required this.dimFg,
    required this.onTap,
    required this.onPlus,
    required this.onMinus,
    required this.onClear,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return Builder(builder: (ctx) {
      return LayoutBuilder(
        builder: (_, c) {
          final h = c.maxHeight;
          final labelH = h * 0.22;
          final bumpH = h * 0.18;
          return Padding(
            padding: EdgeInsets.all(_cellPadding(h)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  height: labelH,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      label,
                      style: TextStyle(
                        color: fg,
                        fontSize: labelH * 0.7,
                        letterSpacing: 2,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: GestureDetector(
                    onTap: () => onTap(ctx),
                    onLongPress: onLongPress,
                    behavior: HitTestBehavior.opaque,
                    child: Center(
                      child: value.isEmpty
                          ? const SizedBox.shrink()
                          : FittedBox(
                              fit: BoxFit.contain,
                              child: Text(
                                value,
                                style: TextStyle(
                                  color: fg,
                                  fontSize: 120,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                    ),
                  ),
                ),
                SizedBox(
                  height: bumpH,
                  child: Row(
                    children: [
                      Expanded(
                        child: _BumpButton(
                          symbol: '−',
                          fg: dimFg,
                          size: bumpH * 0.75,
                          onTap: onMinus,
                        ),
                      ),
                      Expanded(
                        child: _BumpButton(
                          symbol: 'X',
                          fg: dimFg,
                          size: bumpH * 0.6,
                          onTap: onClear,
                        ),
                      ),
                      Expanded(
                        child: _BumpButton(
                          symbol: '+',
                          fg: dimFg,
                          size: bumpH * 0.75,
                          onTap: onPlus,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      );
    });
  }
}

class _BumpButton extends StatelessWidget {
  final String symbol;
  final Color fg;
  final double size;
  final VoidCallback onTap;

  const _BumpButton({
    required this.symbol,
    required this.fg,
    required this.size,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Center(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            symbol,
            style: TextStyle(
              color: fg,
              fontSize: size,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }
}

class _NotesPanel extends StatelessWidget {
  final String notes;
  final Color fg;
  final Color dimFg;
  final bool clapping;
  final String creditText;
  // Height the font sizes are derived from (144 = the default bar height).
  final double fontRef;
  // Whether to show the dim "— notes —" hint when there are no notes.
  final bool showPlaceholder;
  final void Function(BuildContext) onTap;
  final VoidCallback onLongPress;

  const _NotesPanel({
    required this.notes,
    required this.fg,
    required this.dimFg,
    required this.clapping,
    required this.creditText,
    required this.fontRef,
    this.showPlaceholder = true,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final k = fontRef / 144;
    return Builder(builder: (ctx) {
      return GestureDetector(
        onTap: () => onTap(ctx),
        onLongPress: onLongPress,
        behavior: HitTestBehavior.opaque,
        child: Padding(
        padding: EdgeInsets.symmetric(
            horizontal: 16, vertical: math.min(8.0, fontRef * 0.05)),
        child: Center(
          child: clapping
              ? FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    creditText,
                    style: TextStyle(
                      color: fg,
                      fontSize: 36 * k,
                      fontStyle: FontStyle.italic,
                      letterSpacing: 1,
                    ),
                  ),
                )
              : (notes.isEmpty && !showPlaceholder
                  ? const SizedBox.shrink()
                  : notes.isEmpty
                  ? FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        '— notes —',
                        style: TextStyle(
                          color: dimFg.withValues(alpha: 0.5),
                          fontSize: 20 * k,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    )
                  : FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        notes,
                        style: TextStyle(
                          color: fg,
                          fontSize: 28 * k,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    )),
          ),
        ),
      );
    });
  }
}

// Colour calibration sheet: seven ramps stacked with no gaps between them
// (blue, green, cyan, red, magenta, yellow, grey), each stepping from black
// on the left to full brightness on the right.
class _ColorChart extends StatelessWidget {
  const _ColorChart();

  @override
  Widget build(BuildContext context) {
    return const IgnorePointer(
      child: CustomPaint(
        key: ValueKey('color-chart'),
        painter: _ColorChartPainter(),
        size: Size.infinite,
      ),
    );
  }
}

class _ColorChartPainter extends CustomPainter {
  const _ColorChartPainter();

  static const int _steps = 32;
  // Which of red, green and blue each ramp uses, top to bottom.
  static const List<(int, int, int)> _ramps = [
    (0, 0, 1),
    (0, 1, 0),
    (0, 1, 1),
    (1, 0, 0),
    (1, 0, 1),
    (1, 1, 0),
    (1, 1, 1),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    // No anti-aliasing: neighbouring patches share exact pixel edges, so no
    // seams show between them.
    final paint = Paint()..isAntiAlias = false;
    for (var row = 0; row < _ramps.length; row++) {
      final (r, g, b) = _ramps[row];
      final top = size.height * row / _ramps.length;
      final bottom = size.height * (row + 1) / _ramps.length;
      for (var i = 0; i < _steps; i++) {
        final v = (255 * i / (_steps - 1)).round();
        paint.color = Color.fromARGB(255, r * v, g * v, b * v);
        canvas.drawRect(
          Rect.fromLTRB(
            size.width * i / _steps,
            top,
            size.width * (i + 1) / _steps,
            bottom,
          ),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_ColorChartPainter oldDelegate) => false;
}

class _VDivider extends StatelessWidget {
  final Color color;
  final double thickness;
  const _VDivider({required this.color, required this.thickness});

  @override
  Widget build(BuildContext context) {
    return Container(width: thickness, color: color);
  }
}

// -----------------------------------------------------------------------------
// Row drag handle
// -----------------------------------------------------------------------------

// Invisible strip laid over a horizontal divider. Dragging it vertically
// resizes the two rows it separates. It is translucent to hit testing, so taps
// and long-presses still reach the cells underneath.
class _RowDragHandle extends StatelessWidget {
  final void Function(double dy) onDrag;
  final VoidCallback onEnd;

  const _RowDragHandle({super.key, required this.onDrag, required this.onEnd});

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeRow,
      opaque: false,
      hitTestBehavior: HitTestBehavior.translucent,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onVerticalDragUpdate: (d) => onDrag(d.delta.dy),
        onVerticalDragEnd: (_) => onEnd(),
        onVerticalDragCancel: onEnd,
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Remembered-values editor
// -----------------------------------------------------------------------------

// Full-screen editor for the per-field remembered values: one block per field,
// each with a fixed number of text rows. Edits are written straight into
// [slots]; the caller cleans them up and saves once this page is closed.
class _ListsEditorPage extends StatefulWidget {
  final List<(String, String)> fields; // (field key, label)
  final Map<String, List<String>> slots;

  const _ListsEditorPage({required this.fields, required this.slots});

  @override
  State<_ListsEditorPage> createState() => _ListsEditorPageState();
}

class _ListsEditorPageState extends State<_ListsEditorPage> {
  late final Map<String, List<TextEditingController>> _controllers;

  @override
  void initState() {
    super.initState();
    _controllers = {
      for (final (field, _) in widget.fields)
        field: [
          for (final v in widget.slots[field]!) TextEditingController(text: v),
        ],
    };
  }

  @override
  void dispose() {
    for (final list in _controllers.values) {
      for (final c in list) {
        c.dispose();
      }
    }
    super.dispose();
  }

  Widget _section(String field, String label) {
    final prefix = kFieldAffixes[field]?.prefix ?? '';
    final suffix = kFieldAffixes[field]?.suffix ?? '';
    const affixStyle = TextStyle(fontSize: 16, color: Colors.white70);
    final controllers = _controllers[field]!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            letterSpacing: 2,
          ),
        ),
        const SizedBox(height: 8),
        for (var i = 0; i < controllers.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                SizedBox(
                  width: 26,
                  child: Text(
                    '${i + 1}',
                    style: const TextStyle(color: Colors.white54),
                  ),
                ),
                // The fixed parts sit outside the box: only the middle is typed.
                if (prefix.isNotEmpty) ...[
                  Text(prefix, style: affixStyle),
                  const SizedBox(width: 6),
                ],
                Expanded(
                  child: TextField(
                    key: ValueKey('list-$field-$i'),
                    controller: controllers[i],
                    textCapitalization: TextCapitalization.characters,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      isDense: true,
                      border: OutlineInputBorder(),
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                    ),
                    onChanged: (v) => widget.slots[field]![i] = v,
                  ),
                ),
                if (suffix.isNotEmpty) ...[
                  const SizedBox(width: 6),
                  Text(suffix, style: affixStyle),
                ],
              ],
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Remembered values'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Done'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (_, c) {
            const gap = 16.0;
            final cols = ((c.maxWidth - gap) / (170 + gap))
                .floor()
                .clamp(1, widget.fields.length);
            final colW =
                ((c.maxWidth - gap * (cols + 1)) / cols).floorToDouble();
            return SingleChildScrollView(
              padding: const EdgeInsets.all(gap),
              child: Wrap(
                spacing: gap,
                runSpacing: gap * 1.5,
                children: [
                  for (final (field, label) in widget.fields)
                    SizedBox(width: colW, child: _section(field, label)),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
