import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
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

class _ClapperboardScreenState extends State<ClapperboardScreen> {
  static const _kDataKey = 'clap_data';
  static const _kPresetsKey = 'clap_presets';
  static const _kTextSizeKey = 'text_size';
  static const _kBgColorKey = 'bg_color';
  static const _kFgColorKey = 'fg_color';
  static const _kHistoryKey = 'clap_history';

  static const int _clapDurationMs = 1000;
  static const int _maxHistory = 5;
  static const String _clapCredit = 'Clapboard by Adaminion';

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
  DateTime? _clapStart;
  DateTime _now = DateTime.now();
  Timer? _clockTimer;
  Timer? _clapTimer;
  SharedPreferences? _prefs;
  String _buildInfo = '';

  double get _scale => _textScales[_textSize] ?? 1.0;

  bool get _clapping => _clapStart != null;

  int get _clapRemainingMs {
    if (_clapStart == null) return 0;
    final elapsed = DateTime.now().difference(_clapStart!).inMilliseconds;
    final rem = _clapDurationMs - elapsed;
    return rem < 0 ? 0 : rem;
  }

  @override
  void initState() {
    super.initState();
    _load();
    _loadBuildInfo();
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    _clapTimer?.cancel();
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
    if (mounted) setState(() {});
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
    final v = value.trim();
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

  void _clap() {
    HapticFeedback.heavyImpact();
    _clapTimer?.cancel();
    setState(() => _clapStart = DateTime.now());
    _clapTimer = Timer.periodic(const Duration(milliseconds: 16), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      if (_clapRemainingMs <= 0) {
        t.cancel();
        setState(() => _clapStart = null);
      } else {
        setState(() {});
      }
    });
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
                child: Text(h),
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
    final value = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Edit $label'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: keyboard,
          textCapitalization: TextCapitalization.characters,
          decoration: InputDecoration(hintText: label),
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
    if (value != null) {
      setState(() => onSet(value));
      if (value.trim().isNotEmpty) {
        _pushHistory(field, value);
      }
      _saveData();
    }
  }

  // ---------------------------------------------------------------------------
  // Menu and dialogs
  // ---------------------------------------------------------------------------

  Future<void> _openMenu() async {
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.grey[900],
      builder: (ctx) => SafeArea(
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
    );
    if (!mounted) return;
    switch (action) {
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
      case 'reset':
        setState(() {
          _data.scene = '1';
          _data.take = '1';
        });
        _saveData();
        break;
    }
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
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final bg = _clapping ? _fgColor : _bgColor;
    final fg = _clapping ? _bgColor : _fgColor;
    final dimFg = fg.withValues(alpha: 0.45);
    final divider = fg.withValues(alpha: 0.7);
    final scale = _scale;
    const dividerThickness = 5.0;

    final body = SafeArea(
      child: Column(
        children: [
          _HeaderCell(
            label: 'TITLE',
            value: _data.title,
            fg: fg,
            divider: divider,
            dividerThickness: dividerThickness,
            height: 56 * scale,
            onTap: (ctx) => _showHistoryMenuAt(
                ctx, 'title', (v) => _data.title = v),
            onLongPress: () => _longPressEdit(
                'TITLE', 'title', _data.title, (v) => _data.title = v),
          ),
          _HeaderCell(
            label: 'DATE/TIME',
            value: _fmtDateTime(_now),
            fg: fg,
            divider: divider,
            dividerThickness: dividerThickness,
            height: 44 * scale,
            valueOnly: true,
          ),
          // SCENE / TAKE / ROLL row — twice as tall as the lower rows
          Expanded(
            flex: 2,
            child: Row(
              children: [
                Expanded(
                  child: _BumpCell(
                    label: 'SCENE',
                    value: _data.scene,
                    fg: fg,
                    dimFg: dimFg,
                    onTap: (ctx) => _showHistoryMenuAt(
                        ctx, 'scene', (v) => _data.scene = v),
                    onPlus: () => _bumpScene(1),
                    onMinus: () => _bumpScene(-1),
                    onClear: () => _clearWithHistory(
                        'scene', _data.scene, () => _data.scene = ''),
                    onLongPress: () => _longPressEdit(
                        'SCENE', 'scene', _data.scene,
                        (v) => _data.scene = v),
                  ),
                ),
                _VDivider(color: divider, thickness: dividerThickness),
                Expanded(
                  child: _BumpCell(
                    label: 'TAKE',
                    value: _data.take,
                    fg: fg,
                    dimFg: dimFg,
                    onTap: (ctx) => _showHistoryMenuAt(
                        ctx, 'take', (v) => _data.take = v),
                    onPlus: () => _bumpTake(1),
                    onMinus: () => _bumpTake(-1),
                    onClear: () => _clearWithHistory(
                        'take', _data.take, () => _data.take = ''),
                    onLongPress: () => _longPressEdit(
                        'TAKE', 'take', _data.take,
                        (v) => _data.take = v),
                  ),
                ),
                _VDivider(color: divider, thickness: dividerThickness),
                Expanded(
                  child: _SimpleCell(
                    label: 'ROLL',
                    value: _data.roll,
                    fg: fg,
                    onTap: (ctx) => _showHistoryMenuAt(
                        ctx, 'roll', (v) => _data.roll = v),
                    onLongPress: () => _longPressEdit(
                        'ROLL', 'roll', _data.roll,
                        (v) => _data.roll = v),
                  ),
                ),
              ],
            ),
          ),
          Container(height: dividerThickness, color: divider),
          // CAMERA / APERTURE / FPS
          Expanded(
            flex: 1,
            child: Row(
              children: [
                Expanded(
                  child: _SimpleCell(
                    label: 'CAMERA',
                    value: _data.camera,
                    fg: fg,
                    onTap: (ctx) => _showHistoryMenuAt(
                        ctx, 'camera', (v) => _data.camera = v),
                    onLongPress: () => _longPressEdit(
                        'CAMERA', 'camera', _data.camera,
                        (v) => _data.camera = v),
                  ),
                ),
                _VDivider(color: divider, thickness: dividerThickness),
                Expanded(
                  child: _SimpleCell(
                    label: 'APERTURE',
                    value: _data.aperture,
                    fg: fg,
                    onTap: (ctx) => _showHistoryMenuAt(
                        ctx, 'aperture', (v) => _data.aperture = v),
                    onLongPress: () => _longPressEdit(
                        'APERTURE', 'aperture', _data.aperture,
                        (v) => _data.aperture = v),
                  ),
                ),
                _VDivider(color: divider, thickness: dividerThickness),
                Expanded(
                  child: _SimpleCell(
                    label: 'FPS',
                    value: _data.fps,
                    fg: fg,
                    onTap: (ctx) => _showHistoryMenuAt(
                        ctx, 'fps', (v) => _data.fps = v),
                    onLongPress: () => _longPressEdit(
                      'FPS',
                      'fps',
                      _data.fps,
                      (v) => _data.fps = v,
                      keyboard:
                          const TextInputType.numberWithOptions(decimal: true),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Container(height: dividerThickness, color: divider),
          // SHUTTER / LENS / SOUND
          Expanded(
            flex: 1,
            child: Row(
              children: [
                Expanded(
                  child: _SimpleCell(
                    label: 'SHUTTER',
                    value: _data.shutter,
                    fg: fg,
                    onTap: (ctx) => _showHistoryMenuAt(
                        ctx, 'shutter', (v) => _data.shutter = v),
                    onLongPress: () => _longPressEdit(
                        'SHUTTER', 'shutter', _data.shutter,
                        (v) => _data.shutter = v),
                  ),
                ),
                _VDivider(color: divider, thickness: dividerThickness),
                Expanded(
                  child: _SimpleCell(
                    label: 'LENS',
                    value: _data.lens,
                    fg: fg,
                    onTap: (ctx) => _showHistoryMenuAt(
                        ctx, 'lens', (v) => _data.lens = v),
                    onLongPress: () => _longPressEdit(
                        'LENS', 'lens', _data.lens,
                        (v) => _data.lens = v),
                  ),
                ),
                _VDivider(color: divider, thickness: dividerThickness),
                Expanded(
                  child: _SimpleCell(
                    label: 'SOUND',
                    value: _data.sound,
                    fg: fg,
                    onTap: (ctx) => _showHistoryMenuAt(
                        ctx, 'sound', (v) => _data.sound = v),
                    onLongPress: () => _longPressEdit(
                        'SOUND', 'sound', _data.sound,
                        (v) => _data.sound = v),
                  ),
                ),
              ],
            ),
          ),
          Container(height: dividerThickness, color: divider),
          // CLAP bar — double-tall, split CLAP (1/3) / NOTES (2/3) / menu
          SizedBox(
            height: 144 * scale,
            child: Row(
              children: [
                Expanded(
                  flex: 1,
                  child: InkWell(
                    onTap: _clap,
                    child: Center(
                      child: _clapping
                          ? Text(
                              _clapRemainingMs.toString().padLeft(4, '0'),
                              style: TextStyle(
                                color: fg,
                                fontSize: 64 * scale,
                                fontWeight: FontWeight.bold,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                                letterSpacing: 4,
                              ),
                            )
                          : Text(
                              'CLAP',
                              style: TextStyle(
                                color: dimFg,
                                fontSize: 48 * scale,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 8,
                              ),
                            ),
                    ),
                  ),
                ),
                _VDivider(color: divider, thickness: dividerThickness),
                Expanded(
                  flex: 2,
                  child: _NotesPanel(
                    notes: _data.notes,
                    fg: fg,
                    dimFg: dimFg,
                    clapping: _clapping,
                    creditText: _clapCredit,
                    onTap: (ctx) => _showHistoryMenuAt(
                        ctx, 'notes', (v) => _data.notes = v),
                    onLongPress: () => _longPressEdit(
                        'NOTES', 'notes', _data.notes,
                        (v) => _data.notes = v),
                  ),
                ),
                Container(width: dividerThickness, color: divider),
                SizedBox(
                  width: 72 * scale,
                  child: IconButton(
                    icon: Icon(Icons.menu, color: dimFg, size: 32 * scale),
                    onPressed: _openMenu,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    return Scaffold(
      backgroundColor: bg,
      body: Stack(
        children: [
          body,
          // Tiny build-number overlay in the bottom-right corner.
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
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Cells
// -----------------------------------------------------------------------------

class _HeaderCell extends StatelessWidget {
  final String label;
  final String value;
  final Color fg;
  final Color divider;
  final double dividerThickness;
  final double height;
  final bool valueOnly;
  final void Function(BuildContext)? onTap;
  final VoidCallback? onLongPress;

  const _HeaderCell({
    required this.label,
    required this.value,
    required this.fg,
    required this.divider,
    required this.dividerThickness,
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
          decoration: BoxDecoration(
            border: Border(
                bottom: BorderSide(color: divider, width: dividerThickness)),
          ),
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
  final void Function(BuildContext) onTap;
  final VoidCallback onLongPress;

  const _SimpleCell({
    required this.label,
    required this.value,
    required this.fg,
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
              padding: const EdgeInsets.all(10),
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
            padding: const EdgeInsets.all(10),
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
        child: Text(
          symbol,
          style: TextStyle(
            color: fg,
            fontSize: size,
            fontWeight: FontWeight.bold,
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
  final void Function(BuildContext) onTap;
  final VoidCallback onLongPress;

  const _NotesPanel({
    required this.notes,
    required this.fg,
    required this.dimFg,
    required this.clapping,
    required this.creditText,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return Builder(builder: (ctx) {
      return GestureDetector(
        onTap: () => onTap(ctx),
        onLongPress: onLongPress,
        behavior: HitTestBehavior.opaque,
        child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Center(
          child: clapping
              ? FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    creditText,
                    style: TextStyle(
                      color: fg,
                      fontSize: 36,
                      fontStyle: FontStyle.italic,
                      letterSpacing: 1,
                    ),
                  ),
                )
              : (notes.isEmpty
                  ? Text(
                      '— notes —',
                      style: TextStyle(
                        color: dimFg.withValues(alpha: 0.5),
                        fontSize: 20,
                        fontStyle: FontStyle.italic,
                      ),
                    )
                  : FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        notes,
                        style: TextStyle(
                          color: fg,
                          fontSize: 28,
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

class _VDivider extends StatelessWidget {
  final Color color;
  final double thickness;
  const _VDivider({required this.color, required this.thickness});

  @override
  Widget build(BuildContext context) {
    return Container(width: thickness, color: color);
  }
}
