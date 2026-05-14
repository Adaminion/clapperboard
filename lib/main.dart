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

class ClapData {
  String title;
  String scene;
  String take;
  String roll;
  String camera;
  String fps;
  String sound;

  ClapData({
    this.title = '',
    this.scene = '1',
    this.take = '1',
    this.roll = '',
    this.camera = '',
    this.fps = '',
    this.sound = '',
  });

  Map<String, dynamic> toJson() => {
        'title': title,
        'scene': scene,
        'take': take,
        'roll': roll,
        'camera': camera,
        'fps': fps,
        'sound': sound,
      };

  factory ClapData.fromJson(Map<String, dynamic> j) => ClapData(
        title: j['title'] ?? '',
        scene: j['scene'] ?? '1',
        take: j['take'] ?? '1',
        roll: j['roll'] ?? '',
        camera: j['camera'] ?? '',
        fps: j['fps'] ?? '',
        sound: j['sound'] ?? '',
      );
}

class Preset {
  final String name;
  final String title;
  final String roll;
  final String camera;
  final String fps;
  final String sound;

  Preset({
    required this.name,
    required this.title,
    required this.roll,
    required this.camera,
    required this.fps,
    required this.sound,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'title': title,
        'roll': roll,
        'camera': camera,
        'fps': fps,
        'sound': sound,
      };

  factory Preset.fromJson(Map<String, dynamic> j) => Preset(
        name: j['name'] ?? '',
        title: j['title'] ?? '',
        roll: j['roll'] ?? '',
        camera: j['camera'] ?? '',
        fps: j['fps'] ?? '',
        sound: j['sound'] ?? '',
      );

  factory Preset.fromClap(String name, ClapData c) => Preset(
        name: name,
        title: c.title,
        roll: c.roll,
        camera: c.camera,
        fps: c.fps,
        sound: c.sound,
      );
}

class ClapperboardScreen extends StatefulWidget {
  const ClapperboardScreen({super.key});

  @override
  State<ClapperboardScreen> createState() => _ClapperboardScreenState();
}

class _ClapperboardScreenState extends State<ClapperboardScreen> {
  static const _kDataKey = 'clap_data';
  static const _kPresetsKey = 'clap_presets';
  static const _kTextSizeKey = 'text_size';

  static const Map<String, double> _textScales = {
    'S': 0.85,
    'M': 1.0,
    'L': 1.5,
    'XL': 2.0,
  };

  static const int _clapDurationMs = 1000;

  ClapData _data = ClapData();
  List<Preset> _presets = [];
  String _textSize = 'M';
  DateTime? _clapStart;
  DateTime _now = DateTime.now();
  Timer? _clockTimer;
  Timer? _clapTimer;
  SharedPreferences? _prefs;

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

  void _clearField(void Function() mutate) {
    setState(mutate);
    _saveData();
  }

  Future<void> _editField(
    String label,
    String current,
    void Function(String) onSet, {
    TextInputType keyboard = TextInputType.text,
  }) async {
    final controller = TextEditingController(text: current);
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
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, controller.text),
              child: const Text('OK')),
        ],
      ),
    );
    if (value != null) {
      setState(() => onSet(value));
      _saveData();
    }
  }

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
            ListTile(
              leading: const Icon(Icons.format_size, color: Colors.white),
              title: Text('Text size: $_textSize',
                  style: const TextStyle(color: Colors.white)),
              onTap: () => Navigator.pop(ctx, 'textsize'),
            ),
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
    if (action == 'save') await _savePresetDialog();
    if (action == 'load') await _loadPresetDialog();
    if (action == 'textsize') await _textSizeDialog();
    if (action == 'reset') {
      setState(() {
        _data.scene = '1';
        _data.take = '1';
      });
      _saveData();
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
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
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
        _data.fps = picked.fps;
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

  @override
  Widget build(BuildContext context) {
    final bg = _clapping ? Colors.white : Colors.black;
    final fg = _clapping ? Colors.black : Colors.white;
    final dimFg = fg.withValues(alpha: 0.45);
    final divider = fg.withValues(alpha: 0.7);
    final scale = _scale;
    const dividerThickness = 5.0;

    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: Column(
          children: [
            _HeaderCell(
              label: 'TITLE',
              value: _data.title,
              fg: fg,
              divider: divider,
              dividerThickness: dividerThickness,
              height: 56 * scale,
              scale: scale,
              onLongPress: () =>
                  _editField('TITLE', _data.title, (v) => _data.title = v),
            ),
            _HeaderCell(
              label: 'DATE/TIME',
              value: _fmtDateTime(_now),
              fg: fg,
              divider: divider,
              dividerThickness: dividerThickness,
              height: 44 * scale,
              scale: scale,
              valueOnly: true,
            ),
            Expanded(
              child: Row(
                children: [
                  Expanded(
                    child: _BumpCell(
                      label: 'SCENE',
                      value: _data.scene,
                      fg: fg,
                      dimFg: dimFg,
                      scale: scale,
                      onPlus: () => _bumpScene(1),
                      onMinus: () => _bumpScene(-1),
                      onClear: () => _clearField(() => _data.scene = ''),
                      onLongPress: () => _editField(
                        'SCENE',
                        _data.scene,
                        (v) => _data.scene = v,
                      ),
                    ),
                  ),
                  _VDivider(color: divider, thickness: dividerThickness),
                  Expanded(
                    child: _BumpCell(
                      label: 'TAKE',
                      value: _data.take,
                      fg: fg,
                      dimFg: dimFg,
                      scale: scale,
                      onPlus: () => _bumpTake(1),
                      onMinus: () => _bumpTake(-1),
                      onClear: () => _clearField(() => _data.take = ''),
                      onLongPress: () => _editField(
                        'TAKE',
                        _data.take,
                        (v) => _data.take = v,
                      ),
                    ),
                  ),
                  _VDivider(color: divider, thickness: dividerThickness),
                  Expanded(
                    child: _SimpleCell(
                      label: 'ROLL',
                      value: _data.roll,
                      fg: fg,
                      scale: scale,
                      onLongPress: () => _editField(
                          'ROLL', _data.roll, (v) => _data.roll = v),
                    ),
                  ),
                ],
              ),
            ),
            Container(height: dividerThickness, color: divider),
            Expanded(
              child: Row(
                children: [
                  Expanded(
                    child: _SimpleCell(
                      label: 'CAMERA',
                      value: _data.camera,
                      fg: fg,
                      scale: scale,
                      onLongPress: () => _editField(
                          'CAMERA', _data.camera, (v) => _data.camera = v),
                    ),
                  ),
                  _VDivider(color: divider, thickness: dividerThickness),
                  Expanded(
                    child: _SimpleCell(
                      label: 'FPS',
                      value: _data.fps,
                      fg: fg,
                      scale: scale,
                      onLongPress: () => _editField(
                        'FPS',
                        _data.fps,
                        (v) => _data.fps = v,
                        keyboard:
                            const TextInputType.numberWithOptions(decimal: true),
                      ),
                    ),
                  ),
                  _VDivider(color: divider, thickness: dividerThickness),
                  Expanded(
                    child: _SimpleCell(
                      label: 'SOUND',
                      value: _data.sound,
                      fg: fg,
                      scale: scale,
                      onLongPress: () => _editField(
                          'SOUND', _data.sound, (v) => _data.sound = v),
                    ),
                  ),
                ],
              ),
            ),
            Container(height: dividerThickness, color: divider),
            SizedBox(
              height: 72 * scale,
              child: Row(
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: _clap,
                      child: Center(
                        child: _clapping
                            ? Text(
                                _clapRemainingMs
                                    .toString()
                                    .padLeft(4, '0'),
                                style: TextStyle(
                                  color: fg,
                                  fontSize: 44 * scale,
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
                                  fontSize: 32 * scale,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 8,
                                ),
                              ),
                      ),
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
      ),
    );
  }
}

class _HeaderCell extends StatelessWidget {
  final String label;
  final String value;
  final Color fg;
  final Color divider;
  final double dividerThickness;
  final double height;
  final double scale;
  final bool valueOnly;
  final VoidCallback? onLongPress;

  const _HeaderCell({
    required this.label,
    required this.value,
    required this.fg,
    required this.divider,
    required this.dividerThickness,
    required this.height,
    required this.scale,
    this.valueOnly = false,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final shown = valueOnly ? value : (value.isEmpty ? label : value);
    return GestureDetector(
      onLongPress: onLongPress,
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: height,
        decoration: BoxDecoration(
          border: Border(
              bottom: BorderSide(color: divider, width: dividerThickness)),
        ),
        alignment: Alignment.center,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            shown,
            style: TextStyle(
              color: fg,
              fontSize: (valueOnly ? 22 : 26) * scale,
              letterSpacing: 2,
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
          ),
        ),
      ),
    );
  }
}

class _SimpleCell extends StatelessWidget {
  final String label;
  final String value;
  final Color fg;
  final double scale;
  final VoidCallback onLongPress;

  const _SimpleCell({
    required this.label,
    required this.value,
    required this.fg,
    required this.scale,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onLongPress: onLongPress,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: TextStyle(
                    color: fg, fontSize: 18 * scale, letterSpacing: 2)),
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
                            fontSize: 56,
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
  }
}

class _BumpCell extends StatelessWidget {
  final String label;
  final String value;
  final Color fg;
  final Color dimFg;
  final double scale;
  final VoidCallback onPlus;
  final VoidCallback onMinus;
  final VoidCallback onClear;
  final VoidCallback onLongPress;

  const _BumpCell({
    required this.label,
    required this.value,
    required this.fg,
    required this.dimFg,
    required this.scale,
    required this.onPlus,
    required this.onMinus,
    required this.onClear,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: TextStyle(
                  color: fg, fontSize: 18 * scale, letterSpacing: 2)),
          Expanded(
            child: GestureDetector(
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
                            fontSize: 72,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
              ),
            ),
          ),
          SizedBox(
            height: 44 * scale,
            child: Row(
              children: [
                Expanded(
                    child:
                        _BumpButton(symbol: '−', fg: dimFg, scale: scale, onTap: onMinus)),
                Expanded(
                    child:
                        _BumpButton(symbol: 'X', fg: dimFg, scale: scale, onTap: onClear)),
                Expanded(
                    child:
                        _BumpButton(symbol: '+', fg: dimFg, scale: scale, onTap: onPlus)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BumpButton extends StatelessWidget {
  final String symbol;
  final Color fg;
  final double scale;
  final VoidCallback onTap;

  const _BumpButton({
    required this.symbol,
    required this.fg,
    required this.scale,
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
            fontSize: 28 * scale,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
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
