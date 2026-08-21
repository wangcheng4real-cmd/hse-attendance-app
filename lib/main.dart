import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';

import 'data/app_database.dart';
import 'models/inspection_record.dart';
import 'services/excel_exporter.dart';
import 'services/photo_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppDatabase.instance.database;
  runApp(const HseApp());
}

class HseApp extends StatelessWidget {
  const HseApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'HSE现场打卡',
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff0b5c75)),
      useMaterial3: true,
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
        filled: true,
        fillColor: Color(0xfff7f9fa),
      ),
      cardTheme: const CardThemeData(
        elevation: 0,
        color: Color(0xfff4f7f8),
        margin: EdgeInsets.zero,
      ),
    ),
    home: const AppShell(),
  );
}

class AppShell extends StatefulWidget {
  const AppShell({super.key});
  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;
  int _revision = 0;
  bool _checkedName = false;
  final db = AppDatabase.instance;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_checkedName) {
      _checkedName = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _ensureInspector());
    }
  }

  Future<void> _ensureInspector() async {
    if ((await db.getSetting('inspector_name'))?.trim().isNotEmpty == true ||
        !mounted)
      return;
    final controller = TextEditingController();
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('欢迎使用'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 30,
          decoration: const InputDecoration(
            labelText: '巡检员姓名',
            hintText: '用于导出文件命名',
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () async {
              final name = controller.text.trim();
              if (name.isEmpty) return;
              await db.setSetting('inspector_name', name);
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('开始使用'),
          ),
        ],
      ),
    );
  }

  Future<void> _openForm([InspectionRecord? record]) async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => RecordFormPage(record: record)),
    );
    if (changed == true && mounted) setState(() => _revision++);
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      HomePage(
        key: ValueKey('home$_revision'),
        onAdd: _openForm,
        onHistory: () => setState(() => _index = 1),
      ),
      HistoryPage(
        key: ValueKey('history$_revision'),
        onEdit: _openForm,
        onChanged: () => setState(() => _revision++),
      ),
      ExportPage(key: ValueKey('export$_revision')),
      SettingsPage(key: ValueKey('settings$_revision')),
    ];
    return Scaffold(
      appBar: AppBar(title: Text(['现场巡检', '历史记录', '导出检查表', '设置'][_index])),
      body: SafeArea(child: pages[_index]),
      floatingActionButton: _index < 2
          ? FloatingActionButton.extended(
              onPressed: () => _openForm(),
              icon: const Icon(Icons.add_a_photo_outlined),
              label: const Text('新增打卡'),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (v) => setState(() => _index = v),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: '首页',
          ),
          NavigationDestination(icon: Icon(Icons.history), label: '记录'),
          NavigationDestination(
            icon: Icon(Icons.file_download_outlined),
            label: '导出',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            label: '设置',
          ),
        ],
      ),
    );
  }
}

class HomePage extends StatelessWidget {
  const HomePage({super.key, required this.onAdd, required this.onHistory});
  final VoidCallback onAdd;
  final VoidCallback onHistory;
  @override
  Widget build(BuildContext context) => FutureBuilder<(int, int)>(
    future: AppDatabase.instance.todaySummary(),
    builder: (context, snapshot) {
      final summary = snapshot.data ?? (0, 0);
      return ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            DateFormat('yyyy年M月d日').format(DateTime.now()),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: _SummaryCard(
                  label: '今日打卡',
                  value: '${summary.$1}',
                  icon: Icons.fact_check_outlined,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _SummaryCard(
                  label: '缺岗记录',
                  value: '${summary.$2}',
                  icon: Icons.warning_amber_rounded,
                  warning: summary.$2 > 0,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.camera_alt_outlined),
            label: const Padding(
              padding: EdgeInsets.symmetric(vertical: 14),
              child: Text('新增安全员在岗检查'),
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: onHistory,
            icon: const Icon(Icons.manage_search),
            label: const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('查看历史记录'),
            ),
          ),
          const SizedBox(height: 28),
          const Card(
            child: Padding(
              padding: EdgeInsets.all(18),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.offline_bolt_outlined),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text('所有记录和照片仅保存在本机，无需网络即可使用。请勿随意卸载应用，以免数据丢失。'),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    },
  );
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.label,
    required this.value,
    required this.icon,
    this.warning = false,
  });
  final String label, value;
  final IconData icon;
  final bool warning;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            color: warning
                ? Colors.orange.shade800
                : Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 14),
          Text(
            value,
            style: Theme.of(context).textTheme.headlineMedium
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          Text(label),
        ],
      ),
    ),
  );
}

class RecordFormPage extends StatefulWidget {
  const RecordFormPage({super.key, this.record});
  final InspectionRecord? record;
  @override
  State<RecordFormPage> createState() => _RecordFormPageState();
}

class _RecordFormPageState extends State<RecordFormPage> {
  final _formKey = GlobalKey<FormState>();
  final _contractor = TextEditingController();
  final _area = TextEditingController();
  final _count = TextEditingController();
  final _absence = TextEditingController();
  final _action = TextEditingController();
  final _photoStore = PhotoStore();
  final _picker = ImagePicker();
  late DateTime _time;
  late String _shift;
  late bool _allPresent;
  late List<String> _photos;
  final _newPhotos = <String>{};
  bool _saving = false;
  bool _committed = false;

  @override
  void initState() {
    super.initState();
    final r = widget.record;
    _time = r?.inspectedAt ?? DateTime.now();
    _shift = r?.shift ?? '白班';
    _allPresent = r?.allPresent ?? true;
    _photos = [...?r?.photoPaths];
    _contractor.text = r?.contractor ?? '';
    _area.text = r?.area ?? '';
    _count.text = r == null ? '' : '${r.reportedCount}';
    _absence.text = r?.absenceDescription ?? '';
    _action.text = r?.improvementAction ?? '';
  }

  @override
  void dispose() {
    if (!_committed) unawaited(_photoStore.deleteAll(_newPhotos));
    for (final c in [_contractor, _area, _count, _absence, _action]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickDateTime() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _time,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_time),
    );
    if (time != null)
      setState(
        () => _time = DateTime(
          date.year,
          date.month,
          date.day,
          time.hour,
          time.minute,
        ),
      );
  }

  Future<void> _takePhoto() async {
    if (_photos.length >= 3) return;
    final status = await Permission.camera.request();
    if (!status.isGranted) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('需要相机权限才能拍照'),
          action: status.isPermanentlyDenied
              ? SnackBarAction(label: '去设置', onPressed: openAppSettings)
              : null,
        ),
      );
      return;
    }
    try {
      final photo = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 82,
        maxWidth: 1800,
      );
      if (photo == null) return;
      final relative = await _photoStore.importPhoto(photo.path, _time);
      _newPhotos.add(relative);
      if (mounted) setState(() => _photos.add(relative));
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('拍照失败：$e')));
    }
  }

  Future<void> _removePhoto(int index) async {
    final path = _photos[index];
    setState(() => _photos.removeAt(index));
    if (_newPhotos.remove(path)) {
      await _photoStore.deleteAll([path]);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_photos.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('请至少拍摄1张现场照片')));
      return;
    }
    setState(() => _saving = true);
    try {
      final now = DateTime.now();
      final old = widget.record;
      final record = InspectionRecord(
        id: old?.id,
        inspectedAt: _time,
        contractor: _contractor.text.trim(),
        area: _area.text.trim(),
        shift: _shift,
        reportedCount: int.parse(_count.text),
        allPresent: _allPresent,
        absenceDescription: _absence.text.trim(),
        improvementAction: _action.text.trim(),
        photoPaths: _photos,
        createdAt: old?.createdAt ?? now,
        updatedAt: now,
      );
      await AppDatabase.instance.save(record);
      final removed =
          old?.photoPaths.where((p) => !_photos.contains(p)) ??
          const Iterable<String>.empty();
      await _photoStore.deleteAll(removed);
      _committed = true;
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('保存失败：$e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.record == null ? '新增打卡' : '编辑打卡')),
    body: Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          _Section(
            title: '检查信息',
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('检查时间'),
                subtitle: Text(DateFormat('yyyy-MM-dd HH:mm').format(_time)),
                trailing: const Icon(Icons.edit_calendar_outlined),
                onTap: _pickDateTime,
              ),
              _SuggestionField(
                controller: _contractor,
                kind: 'contractor',
                label: '施工单位 *',
              ),
              const SizedBox(height: 14),
              _SuggestionField(
                controller: _area,
                kind: 'area',
                label: '检查区域 *',
              ),
              const SizedBox(height: 14),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(
                    value: '白班',
                    label: Text('白班'),
                    icon: Icon(Icons.light_mode_outlined),
                  ),
                  ButtonSegment(
                    value: '夜班',
                    label: Text('夜班'),
                    icon: Icon(Icons.dark_mode_outlined),
                  ),
                ],
                selected: {_shift},
                onSelectionChanged: (v) => setState(() => _shift = v.first),
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _count,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: '报送安全人员数量 *'),
                validator: (v) {
                  final n = int.tryParse(v ?? '');
                  return n == null || n < 0 ? '请输入非负整数' : null;
                },
              ),
            ],
          ),
          const SizedBox(height: 16),
          _Section(
            title: '在岗情况',
            children: [
              DropdownButtonFormField<bool>(
                initialValue: _allPresent,
                decoration: const InputDecoration(labelText: '安全人员是否全部在岗 *'),
                items: const [
                  DropdownMenuItem(value: true, child: Text('是，全部在岗')),
                  DropdownMenuItem(value: false, child: Text('否，存在缺岗')),
                ],
                onChanged: (v) => setState(() => _allPresent = v ?? true),
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _absence,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: _allPresent ? '缺岗情况描述（选填）' : '缺岗情况描述 *',
                ),
                validator: (v) => !_allPresent && (v?.trim().isEmpty ?? true)
                    ? '存在缺岗时必须填写'
                    : null,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _action,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: _allPresent ? '改进行动（选填）' : '改进行动 *',
                ),
                validator: (v) => !_allPresent && (v?.trim().isEmpty ?? true)
                    ? '存在缺岗时必须填写'
                    : null,
              ),
            ],
          ),
          const SizedBox(height: 16),
          _Section(
            title: '打卡照片（${_photos.length}/3）',
            children: [
              if (_photos.isNotEmpty)
                SizedBox(
                  height: 112,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _photos.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 10),
                    itemBuilder: (_, i) => FutureBuilder<File>(
                      future: _photoStore.resolve(_photos[i]),
                      builder: (_, snap) => Stack(
                        children: [
                          Container(
                            width: 112,
                            decoration: BoxDecoration(
                              color: Colors.grey.shade200,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: snap.hasData
                                ? Image.file(
                                    snap.data!,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) =>
                                        const Icon(Icons.broken_image),
                                  )
                                : const Center(
                                    child: CircularProgressIndicator(),
                                  ),
                          ),
                          Positioned(
                            right: 3,
                            top: 3,
                            child: IconButton.filledTonal(
                              icon: const Icon(Icons.close, size: 18),
                              onPressed: () => _removePhoto(i),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              if (_photos.isNotEmpty) const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _photos.length >= 3 ? null : _takePhoto,
                icon: const Icon(Icons.camera_alt_outlined),
                label: Text(_photos.isEmpty ? '拍摄现场照片（至少1张）' : '继续拍照'),
              ),
            ],
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_outlined),
            label: Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Text(_saving ? '正在保存…' : '保存打卡'),
            ),
          ),
          const SizedBox(height: 30),
        ],
      ),
    ),
  );
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});
  final String title;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    ),
  );
}

class _SuggestionField extends StatefulWidget {
  const _SuggestionField({
    required this.controller,
    required this.kind,
    required this.label,
  });
  final TextEditingController controller;
  final String kind, label;
  @override
  State<_SuggestionField> createState() => _SuggestionFieldState();
}

class _SuggestionFieldState extends State<_SuggestionField> {
  final _focus = FocusNode();
  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<String>>(
    future: AppDatabase.instance.suggestions(widget.kind),
    builder: (_, snap) => RawAutocomplete<String>(
      textEditingController: widget.controller,
      focusNode: _focus,
      optionsBuilder: (value) => (snap.data ?? []).where(
        (e) => e.toLowerCase().contains(value.text.toLowerCase()),
      ),
      fieldViewBuilder: (_, c, f, onSubmit) => TextFormField(
        controller: c,
        focusNode: f,
        decoration: InputDecoration(labelText: widget.label),
        validator: (v) => v?.trim().isEmpty ?? true ? '此项必填' : null,
        onFieldSubmitted: (_) => onSubmit(),
      ),
      optionsViewBuilder: (_, onSelected, options) => Align(
        alignment: Alignment.topLeft,
        child: Material(
          elevation: 4,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 180, maxWidth: 340),
            child: ListView(
              padding: EdgeInsets.zero,
              shrinkWrap: true,
              children: options
                  .map(
                    (e) => ListTile(title: Text(e), onTap: () => onSelected(e)),
                  )
                  .toList(),
            ),
          ),
        ),
      ),
    ),
  );
}

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key, required this.onEdit, required this.onChanged});
  final ValueChanged<InspectionRecord> onEdit;
  final VoidCallback onChanged;
  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  DateTime? _start, _end;
  String? _shift;
  final _contractor = TextEditingController();
  final _area = TextEditingController();
  Future<List<InspectionRecord>> _load() => AppDatabase.instance.records(
    filter: RecordFilter(
      start: _start == null
          ? null
          : DateTime(_start!.year, _start!.month, _start!.day),
      end: _end == null
          ? null
          : DateTime(_end!.year, _end!.month, _end!.day, 23, 59, 59),
      contractor: _contractor.text,
      area: _area.text,
      shift: _shift,
    ),
  );
  Future<void> _delete(InspectionRecord record) async {
    final ok =
        await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('删除这条记录？'),
            content: const Text('记录和对应照片将永久删除。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('删除'),
              ),
            ],
          ),
        ) ??
        false;
    if (!ok) return;
    await AppDatabase.instance.delete(record.id!);
    await PhotoStore().deleteAll(record.photoPaths);
    widget.onChanged();
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _contractor.dispose();
    _area.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      ExpansionTile(
        title: const Text('筛选记录'),
        leading: const Icon(Icons.filter_alt_outlined),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () async {
                    final v = await showDatePicker(
                      context: context,
                      initialDate: _start ?? DateTime.now(),
                      firstDate: DateTime(2020),
                      lastDate: DateTime.now(),
                    );
                    if (v != null) setState(() => _start = v);
                  },
                  child: Text(
                    _start == null
                        ? '开始日期'
                        : DateFormat('yyyy-MM-dd').format(_start!),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: () async {
                    final v = await showDatePicker(
                      context: context,
                      initialDate: _end ?? DateTime.now(),
                      firstDate: _start ?? DateTime(2020),
                      lastDate: DateTime.now(),
                    );
                    if (v != null) setState(() => _end = v);
                  },
                  child: Text(
                    _end == null
                        ? '结束日期'
                        : DateFormat('yyyy-MM-dd').format(_end!),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _contractor,
            decoration: const InputDecoration(labelText: '施工单位'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _area,
            decoration: const InputDecoration(labelText: '检查区域'),
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String?>(
            initialValue: _shift,
            decoration: const InputDecoration(labelText: '班次'),
            items: const [
              DropdownMenuItem(value: null, child: Text('全部')),
              DropdownMenuItem(value: '白班', child: Text('白班')),
              DropdownMenuItem(value: '夜班', child: Text('夜班')),
            ],
            onChanged: (v) => _shift = v,
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () {
                    _contractor.clear();
                    _area.clear();
                    setState(() {
                      _start = null;
                      _end = null;
                      _shift = null;
                    });
                  },
                  child: const Text('重置'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton(
                  onPressed: () => setState(() {}),
                  child: const Text('应用筛选'),
                ),
              ),
            ],
          ),
        ],
      ),
      Expanded(
        child: FutureBuilder<List<InspectionRecord>>(
          future: _load(),
          builder: (_, snap) {
            if (snap.connectionState != ConnectionState.done)
              return const Center(child: CircularProgressIndicator());
            final rows = snap.data ?? [];
            if (rows.isEmpty) return const Center(child: Text('暂无符合条件的记录'));
            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 100),
              itemCount: rows.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (_, i) {
                final r = rows[i];
                return Card(
                  child: ListTile(
                    isThreeLine: true,
                    leading: CircleAvatar(
                      backgroundColor: r.allPresent
                          ? Colors.green.shade50
                          : Colors.orange.shade50,
                      child: Icon(
                        r.allPresent ? Icons.check : Icons.warning_amber,
                        color: r.allPresent
                            ? Colors.green.shade800
                            : Colors.orange.shade800,
                      ),
                    ),
                    title: Text('${r.contractor} · ${r.area}'),
                    subtitle: Text(
                      '${DateFormat('yyyy-MM-dd HH:mm').format(r.inspectedAt)}  ${r.shift}\n报送${r.reportedCount}人 · ${r.allPresent ? '全部在岗' : '存在缺岗'} · 照片${r.photoPaths.length}张',
                    ),
                    trailing: PopupMenuButton<String>(
                      onSelected: (v) =>
                          v == 'edit' ? widget.onEdit(r) : _delete(r),
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'edit', child: Text('编辑')),
                        PopupMenuItem(value: 'delete', child: Text('删除')),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    ],
  );
}

class ExportPage extends StatefulWidget {
  const ExportPage({super.key});
  @override
  State<ExportPage> createState() => _ExportPageState();
}

class _ExportPageState extends State<ExportPage> {
  static const _platform = MethodChannel('com.hse.hse_attendance/share');
  DateTime _start = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime _end = DateTime.now();
  bool _busy = false;
  Future<void> _select(bool start) async {
    final value = await showDatePicker(
      context: context,
      initialDate: start ? _start : _end,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (value != null)
      setState(() {
        if (start)
          _start = value;
        else
          _end = value;
      });
  }

  Future<void> _export() async {
    if (_start.isAfter(_end)) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('开始日期不能晚于结束日期')));
      return;
    }
    setState(() => _busy = true);
    try {
      final records = await AppDatabase.instance.records(
        filter: RecordFilter(
          start: DateTime(_start.year, _start.month, _start.day),
          end: DateTime(_end.year, _end.month, _end.day, 23, 59, 59),
        ),
        ascending: true,
      );
      if (records.isEmpty) {
        if (mounted)
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('所选日期范围内没有记录')));
        return;
      }
      final inspector =
          await AppDatabase.instance.getSetting('inspector_name') ?? '巡检员';
      final result = await ExcelExporter(PhotoStore())
          .export(records, inspector);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('导出成功'),
          content: Text(
            '已导出 ${records.length} 条记录。${result.missingPhotos > 0 ? '\n有 ${result.missingPhotos} 张照片文件缺失，未能嵌入。' : ''}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('完成'),
            ),
            FilledButton.icon(
              onPressed: () => _platform.invokeMethod<void>('shareFile', {
                'path': result.file.path,
              }),
              icon: const Icon(Icons.share),
              label: const Text('分享'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('导出失败：$e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      const Card(
        child: Padding(
          padding: EdgeInsets.all(18),
          child: Row(
            children: [
              Icon(Icons.table_view_outlined),
              SizedBox(width: 12),
              Expanded(
                child: Text('导出文件包含固定表头、全部明细和每条记录的现场照片，可直接在 Excel 中查看。'),
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 20),
      Text(
        '选择日期范围',
        style: Theme.of(context).textTheme.titleMedium
            ?.copyWith(fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: 12),
      Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => _select(true),
              icon: const Icon(Icons.date_range),
              label: Text(DateFormat('yyyy-MM-dd').format(_start)),
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8),
            child: Text('至'),
          ),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => _select(false),
              icon: const Icon(Icons.event),
              label: Text(DateFormat('yyyy-MM-dd').format(_end)),
            ),
          ),
        ],
      ),
      const SizedBox(height: 24),
      FilledButton.icon(
        onPressed: _busy ? null : _export,
        icon: _busy
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.file_download_outlined),
        label: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Text(_busy ? '正在生成…' : '生成并保存 Excel'),
        ),
      ),
    ],
  );
}

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _name = TextEditingController();
  bool _loading = true;
  @override
  void initState() {
    super.initState();
    AppDatabase.instance.getSetting('inspector_name').then((v) {
      _name.text = v ?? '';
      if (mounted) setState(() => _loading = false);
    });
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final value = _name.text.trim();
    if (value.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('巡检员姓名不能为空')));
      return;
    }
    await AppDatabase.instance.setSetting('inspector_name', value);
    if (mounted)
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('已保存')));
  }

  @override
  Widget build(BuildContext context) => _loading
      ? const Center(child: CircularProgressIndicator())
      : ListView(
          padding: const EdgeInsets.all(20),
          children: [
            TextField(
              controller: _name,
              maxLength: 30,
              decoration: const InputDecoration(
                labelText: '巡检员姓名',
                helperText: '用于导出文件命名',
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.save_outlined),
              label: const Text('保存设置'),
            ),
            const SizedBox(height: 28),
            const ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.info_outline),
              title: Text('HSE现场打卡 V1.0'),
              subtitle: Text('离线保存 · Android 8.0及以上'),
            ),
          ],
        );
}
