import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';

import '../controllers/app_controller.dart';
import '../engine/builder.dart' show BuildResult, BookReport, LinkFileReport, formatBytes;
import '../engine/inputs.dart';
import '../engine/validator.dart';
import '../theme/app_surfaces.dart';
import '../theme/app_tokens.dart';
import '../widgets/app_card.dart';
import '../widgets/common_widgets.dart';

/// המסך הראשי: מוסיפים ספרים, הערות וקישורים, בונים מסד ובודקים אותו.
class BuildScreen extends StatefulWidget {
  const BuildScreen({super.key, required this.controller, required this.onGoSettings});

  final AppController controller;
  final VoidCallback onGoSettings;

  @override
  State<BuildScreen> createState() => _BuildScreenState();
}

class _BuildScreenState extends State<BuildScreen> {
  late final _name = TextEditingController(text: widget.controller.settings.displayName);
  late final _outName = TextEditingController(text: widget.controller.settings.outName);
  final _scroll = ScrollController();
  late BuildResult? _seenResult = widget.controller.lastResult;
  var _dragging = false;

  @override
  void dispose() {
    _name.dispose();
    _outName.dispose();
    _scroll.dispose();
    super.dispose();
  }

  AppController get c => widget.controller;

  Future<void> _pickFiles() async {
    final files = await FilePicker.pickFiles(
      dialogTitle: 'בחירת ספרים, הערות וקובצי קישורים',
      type: FileType.custom,
      allowedExtensions: const ['txt', 'json'],
    );
    final paths = [for (final f in files) ?f.path];
    if (paths.isNotEmpty) c.addFiles(paths);
  }

  Future<void> _pickFolder() async {
    final dir = await FilePicker.getDirectoryPath(dialogTitle: 'בחירת תיקייה (כל ה-TXT וקובצי ‎_links.json‎ שבה)');
    if (dir != null) c.addFolder(dir);
  }

  Future<void> _pickOutDir() async {
    final dir = await FilePicker.getDirectoryPath(dialogTitle: 'היכן לשמור את המסד');
    if (dir != null) c.setOutDir(dir);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final result = c.lastResult != null && c.activity == null ? c.lastResult : null;
        if (result != null && !identical(result, _seenResult)) {
          _seenResult = result;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted || !_scroll.hasClients) return;
            _scroll.animateTo(
              _scroll.position.maxScrollExtent,
              duration: AppTokens.animNormal * 2,
              curve: Curves.easeOutCubic,
            );
          });
        }
        return Column(
          children: [
            Expanded(
              child: PageBody(
                controller: _scroll,
                children: [
                  _inputsCard(context),
                  _outputCard(context),
                  if (result != null) _ResultCard(controller: c, result: result),
                ],
              ),
            ),
            _buildBar(context),
          ],
        );
      },
    );
  }

  Widget _inputsCard(BuildContext context) {
    final items = c.items;
    final cs = Theme.of(context).colorScheme;
    final counts = <InputRole, int>{};
    for (final i in items) {
      counts[i.role] = (counts[i.role] ?? 0) + 1;
    }
    final card = AppCard(
      title: '1. קבצים לבדיקה',
      icon: FluentIcons.document_bullet_list_24_regular,
      done: (counts[InputRole.book] ?? 0) > 0,
      info:
          'מוסיפים ספרים (TXT בפורמט אוצריא), קובצי "הערות על X" וקובצי <שם הספר>_links.json — '
          'קבצים בודדים, כמה יחד או תיקייה שלמה. אפשר גם לגרור לכאן. '
          'המיקום (מקור וקטגוריה) נקבע לפי הנתיב <מקור>/ספרים/אוצריא/…, אחרת לפי הספר הקיים בספרייה, '
          'אחרת לפי התיקייה שנוספה או ברירת המחדל שבהגדרות.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (items.isEmpty)
            const SizedBox(
              width: double.infinity,
              child: EmptyState(
                icon: FluentIcons.document_add_24_regular,
                title: 'עדיין לא נוספו קבצים',
                message: 'הוסיפו ספרים, הערות וקובצי קישורים — או גררו אותם לכאן.',
              ),
            )
          else ...[
            Wrap(
              spacing: AppTokens.spaceSM,
              runSpacing: AppTokens.spaceXS,
              children: [
                for (final r in InputRole.values)
                  if ((counts[r] ?? 0) > 0)
                    Tag('${counts[r]} ${r.label}', kind: r == InputRole.unknown ? TagKind.error : TagKind.neutral),
                if (c.indexing) const Tag('סורק את otzaria-library…'),
                if (!c.indexing && c.libraryError != null) Tag(c.libraryError!, kind: TagKind.warn),
              ],
            ),
            const SizedBox(height: AppTokens.spaceSM),
            for (final item in items) _InputRow(item: item, onRemove: c.busy ? null : () => c.removeInput(item.path)),
          ],
          const SizedBox(height: AppTokens.spaceMD),
          Wrap(
            spacing: AppTokens.spaceSM,
            runSpacing: AppTokens.spaceSM,
            children: [
              FilledButton.icon(
                onPressed: c.busy ? null : _pickFiles,
                icon: const Icon(FluentIcons.document_add_24_regular),
                label: const Text('הוסף קבצים'),
              ),
              OutlinedButton.icon(
                onPressed: c.busy ? null : _pickFolder,
                icon: const Icon(FluentIcons.folder_add_24_regular),
                label: const Text('הוסף תיקייה'),
              ),
              if (items.isNotEmpty)
                TextButton.icon(
                  onPressed: c.busy ? null : c.clearInputs,
                  icon: const Icon(FluentIcons.delete_24_regular),
                  label: const Text('נקה הכל'),
                ),
            ],
          ),
        ],
      ),
    );
    return DropTarget(
      onDragEntered: (_) => setState(() => _dragging = true),
      onDragExited: (_) => setState(() => _dragging = false),
      onDragDone: (d) {
        setState(() => _dragging = false);
        if (!c.busy) c.addFiles([for (final f in d.files) f.path]);
      },
      child: AnimatedContainer(
        duration: AppTokens.animFast,
        decoration: BoxDecoration(
          borderRadius: AppTokens.borderRadiusAll,
          border: Border.all(color: _dragging ? cs.primary : Colors.transparent, width: 2),
        ),
        child: card,
      ),
    );
  }

  Widget _outputCard(BuildContext context) {
    final s = c.settings;
    final exists = s.outPath.isNotEmpty && File(s.outPath).existsSync();
    return AppCard(
      title: '2. קובץ המסד',
      done: s.outPath.isNotEmpty,
      icon: FluentIcons.database_24_regular,
      info:
          'הקובץ שייווצר. באוצריא: הגדרות ← ספרייה ← מסדי ספרים אישיים ← ייבא קובץ מסד. '
          'בנייה חוזרת לאותו קובץ מעלה את הגרסה, כך שאוצריא מחליפה את הקודם.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: s.outDir.isEmpty ? const Hint('לא נבחרה תיקייה.') : PathText(s.outDir, maxLines: 2)),
              const SizedBox(width: AppTokens.spaceSM),
              OutlinedButton.icon(
                onPressed: c.busy ? null : _pickOutDir,
                icon: const Icon(FluentIcons.folder_open_24_regular),
                label: const Text('בחר תיקייה'),
              ),
            ],
          ),
          const SizedBox(height: AppTokens.spaceMD),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _outName,
                  enabled: !c.busy,
                  decoration: const InputDecoration(labelText: 'שם הקובץ', suffixText: '.db', border: OutlineInputBorder()),
                  onChanged: c.setOutName,
                ),
              ),
              const SizedBox(width: AppTokens.spaceSM),
              Expanded(
                child: TextField(
                  controller: _name,
                  enabled: !c.busy,
                  decoration: const InputDecoration(labelText: 'שם התצוגה באוצריא', border: OutlineInputBorder()),
                  onChanged: c.setDisplayName,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppTokens.spaceSM),
          Hint(exists ? 'הקובץ קיים: הוא יוחלף בגרסה הבאה.' : 'קובץ חדש ייווצר.'),
        ],
      ),
    );
  }

  Widget _buildBar(BuildContext context) {
    final blocker = c.buildBlocker;
    final theme = Theme.of(context);
    final enabled = blocker == null && !c.busy;
    final hint = blocker ??
        (c.settings.runValidator
            ? 'אחרי הבנייה יורץ בודק המסדים של אוצריא.'
            : 'בודק המסדים של אוצריא כבוי (בהגדרות).');
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppSurfaces.card(context),
        border: Border(top: BorderSide(color: AppSurfaces.divider(context))),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppTokens.spaceMD, vertical: AppTokens.spaceSM + 2),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: AppTokens.contentMaxWidth),
            child: Row(
              children: [
                Expanded(child: Hint(hint)),
                const SizedBox(width: AppTokens.spaceMD),
                SizedBox(
                  height: 46,
                  child: FilledButton.icon(
                    onPressed: enabled ? c.build : null,
                    icon: c.busy
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(FluentIcons.database_arrow_right_20_regular),
                    label: Text(
                      c.validating ? 'מריץ את הבודק…' : 'בנה ובדוק',
                      style: theme.textTheme.titleMedium?.copyWith(color: enabled ? theme.colorScheme.onPrimary : null),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _InputRow extends StatelessWidget {
  const _InputRow({required this.item, required this.onRemove});

  final InputItem item;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (icon, kind) = switch (item.role) {
      InputRole.book => (FluentIcons.book_24_regular, TagKind.good),
      InputRole.notes => (FluentIcons.note_24_regular, TagKind.warn),
      InputRole.links => (FluentIcons.link_24_regular, TagKind.neutral),
      InputRole.altToc => (FluentIcons.text_bullet_list_tree_24_regular, TagKind.neutral),
      InputRole.unknown => (FluentIcons.error_circle_24_regular, TagKind.error),
    };
    final pl = item.placement;
    return Container(
      margin: const EdgeInsets.only(bottom: AppTokens.spaceXS),
      padding: const EdgeInsets.symmetric(horizontal: AppTokens.spaceSM, vertical: 6),
      decoration: BoxDecoration(color: AppSurfaces.inset(context), borderRadius: AppTokens.borderRadiusAll),
      child: Row(
        children: [
          Icon(icon, size: 20, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: AppTokens.spaceSM),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Tooltip(
                  message: item.path,
                  child: Text(item.name, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodyMedium),
                ),
                if (pl != null)
                  Text(
                    '${pl.source} · ${pl.categoryTitles.join(' / ')} · ${pl.kind.label}',
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                if (!item.exists) const Hint('הקובץ לא נמצא', error: true),
              ],
            ),
          ),
          Tag(item.role.label, kind: kind),
          IconButton(
            tooltip: 'הסר',
            visualDensity: VisualDensity.compact,
            onPressed: onRemove,
            icon: const Icon(FluentIcons.dismiss_24_regular, size: 18),
          ),
        ],
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({required this.controller, required this.result});

  final AppController controller;
  final BuildResult result;

  @override
  Widget build(BuildContext context) {
    final r = result;
    final v = controller.lastValidation;
    final errors = r.bookReports.fold(0, (s, b) => s + b.errors.length);
    return AppCard(
      title: 'המסד נבנה',
      done: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PathText(r.outPath),
          const SizedBox(height: AppTokens.spaceMD),
          Wrap(
            spacing: AppTokens.spaceSM,
            runSpacing: AppTokens.spaceSM,
            children: [
              StatTile('${r.books}', 'ספרים'),
              StatTile('${r.lines}', 'שורות'),
              StatTile('${r.links}', 'קישורים'),
              if (r.externalLinks > 0) StatTile('${r.externalLinks}', 'קישורים לספרייה הרשמית'),
              if (r.lineNotes > 0) StatTile('${r.lineNotes}', 'הערות שוליים'),
              StatTile('${r.version}', 'גרסה'),
              StatTile(formatBytes(r.sizeBytes), 'גודל'),
            ],
          ),
          if (errors > 0) ...[
            const SizedBox(height: AppTokens.spaceSM),
            Hint('$errors בעיות שדורשות תשומת לב (מסומנות באדום למטה).', error: true),
          ],
          for (final w in r.warnings) ...[const SizedBox(height: AppTokens.spaceXS), Hint(w, error: true)],
          const SizedBox(height: AppTokens.spaceMD),
          _ValidatorPanel(controller: controller, result: v),
          const SizedBox(height: AppTokens.spaceMD),
          if (r.notes.isNotEmpty) ...[
            Text('הערות שוליים (הערות על X)', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: AppTokens.spaceXS),
            for (final n in r.notes)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Tag(n.merged ? 'ימוזג' : 'ספר עצמאי', kind: n.merged ? TagKind.good : TagKind.warn),
                    const SizedBox(width: AppTokens.spaceSM),
                    Expanded(child: SelectableText('${n.notesTitle} ← ${n.baseTitle}: ${n.reason}')),
                  ],
                ),
              ),
            const SizedBox(height: AppTokens.spaceSM),
          ],
          Text('ספרים', style: Theme.of(context).textTheme.titleSmall),
          for (final b in r.bookReports) _BookTile(report: b),
          if (r.linkFiles.isNotEmpty) ...[
            const SizedBox(height: AppTokens.spaceSM),
            Text('קובצי קישורים', style: Theme.of(context).textTheme.titleSmall),
            for (final l in r.linkFiles) _LinkTile(report: l),
          ],
          const SizedBox(height: AppTokens.spaceMD),
          const Text('לצפייה באוצריא: הגדרות ← ספרייה ← מסדי ספרים אישיים ← ייבא קובץ מסד.'),
          const SizedBox(height: AppTokens.spaceMD),
          Wrap(
            spacing: AppTokens.spaceSM,
            runSpacing: AppTokens.spaceSM,
            children: [
              FilledButton.icon(
                onPressed: () => AppController.reveal(r.outPath),
                icon: const Icon(FluentIcons.folder_open_24_regular),
                label: const Text('פתח תיקייה'),
              ),
              OutlinedButton.icon(
                onPressed: () async {
                  final text = '${r.toText()}\n\n${v == null ? '' : 'בודק המסדים (קוד ${v.exitCode}):\n${v.output}'}';
                  await Clipboard.setData(ClipboardData(text: text));
                  controller.showMessage('הדוח הועתק.');
                },
                icon: const Icon(FluentIcons.copy_24_regular),
                label: const Text('העתק דוח מלא'),
              ),
              TextButton.icon(
                onPressed: controller.busy ? null : controller.validate,
                icon: const Icon(FluentIcons.arrow_sync_24_regular),
                label: const Text('הרץ שוב את הבודק'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ValidatorPanel extends StatelessWidget {
  const _ValidatorPanel({required this.controller, required this.result});

  final AppController controller;
  final ValidatorResult? result;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final v = result;
    if (controller.validating) {
      return const Row(
        children: [
          SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
          SizedBox(width: AppTokens.spaceSM),
          Hint('מריץ את בודק המסדים של אוצריא (dart run tool/validate_personal_db.dart)…'),
        ],
      );
    }
    if (v == null) {
      return Hint(
        controller.settings.runValidator ? 'הבודק לא הורץ.' : 'בודק המסדים של אוצריא כבוי בהגדרות.',
      );
    }
    final (color, label) = v.ok
        ? (cs.primary, 'בודק המסדים של אוצריא: תקין (קוד 0)')
        : v.exitCode == 1
        ? (cs.error, 'בודק המסדים של אוצריא: נמצאה בעיה חוסמת (קוד 1)')
        : (cs.tertiary, 'בודק המסדים של אוצריא לא רץ');
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppTokens.spaceSM),
      decoration: BoxDecoration(
        color: AppSurfaces.tint(color),
        borderRadius: AppTokens.borderRadiusAll,
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                v.ok ? FluentIcons.checkmark_circle_24_filled : FluentIcons.error_circle_24_filled,
                color: color,
                size: 20,
              ),
              const SizedBox(width: AppTokens.spaceSM),
              Text(label, style: TextStyle(color: color, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: AppTokens.spaceXS),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 320),
            child: SingleChildScrollView(
              child: Directionality(
                textDirection: TextDirection.ltr,
                child: SizedBox(
                  width: double.infinity,
                  child: SelectableText(
                    v.output.isEmpty ? '(אין פלט)' : v.output,
                    style: const TextStyle(fontFamily: 'Consolas', fontSize: 12),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BookTile extends StatelessWidget {
  const _BookTile({required this.report});

  final BookReport report;

  @override
  Widget build(BuildContext context) {
    final r = report;
    final theme = Theme.of(context);
    final status = !r.imported
        ? (r.mergedInto != null ? const Tag('מוזג כהערות', kind: TagKind.good) : const Tag('לא נכנס', kind: TagKind.error))
        : r.errors.isNotEmpty
        ? Tag('${r.errors.length} בעיות', kind: TagKind.error)
        : (r.warnings.isNotEmpty || r.tocIssues.isNotEmpty || r.missingMetadata.isNotEmpty)
        ? const Tag('לבדיקה', kind: TagKind.warn)
        : const Tag('תקין', kind: TagKind.good);
    String v(Object? x) => x == null || (x is List && x.isEmpty) ? '—' : (x is List ? x.join('; ') : '$x');
    Widget row(String k, String val, {bool bad = false}) => Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 150, child: Text(k, style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600))),
          Expanded(
            child: SelectableText(
              val,
              style: theme.textTheme.bodySmall?.copyWith(color: bad ? theme.colorScheme.error : null),
            ),
          ),
        ],
      ),
    );
    return Theme(
      data: theme.copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsetsDirectional.only(start: AppTokens.spaceMD, bottom: AppTokens.spaceSM),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        title: Text(r.title, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
        subtitle: Text(
          '${r.role} · ${r.source} · ${r.categoryPath.join(' / ')}',
          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        trailing: status,
        children: [
          row('קובץ', r.path),
          row('מיקום', r.placement),
          for (final t in r.titleChanges) row('נרמול שם', t),
          if (r.notesDecision != null)
            row(
              'הערות',
              '${r.notesDecision!.merged ? 'ימוזגו לתוך' : 'ספר עצמאי, לא ימוזגו לתוך'} "${r.notesDecision!.baseTitle}": '
                  '${r.notesDecision!.reason}',
              bad: !r.notesDecision!.merged,
            ),
          if (r.imported) ...[
            row(
              'שורות',
              '${r.totalLines}${r.storedLines != r.totalLines ? ' (נשמרו ${r.storedLines})' : ''}'
                  ' · כותרות ${r.tocEntries} (${r.tocLevels.entries.map((e) => 'h${e.key}: ${e.value}').join(', ')})',
            ),
            row('מחבר', v(r.authors), bad: r.authors.isEmpty),
            row('דור', v(r.generation), bad: r.generation == null),
            row('תיאור קצר', v(r.heShortDesc), bad: r.heShortDesc == null),
            row('תיאור מלא', v(r.heDesc), bad: r.heDesc == null),
            row('שנת הדפסה', v(r.pubDates)),
            row('מקום הדפסה', v(r.pubPlaces)),
            row('נושאים', v(r.topics)),
            row('סדר (orderIndex)', '${r.orderIndex}${r.isBaseBook ? ' · ספר בסיס (priority.txt)' : ''}'),
            row('באנר', v(r.banner)),
            row('הגנה', r.protection == null ? '—' : 'רמה ${r.protection}'),
            if (r.mergedNotes > 0)
              row(
                'הערות שמוזגו',
                '${r.mergedNotes}${r.mergedNotesAppended > 0 ? ' (מהן ${r.mergedNotesAppended} נוספו בסוף השורה, כי לא נמצא סימון תואם)' : ''}',
                bad: r.mergedNotesAppended > 0,
              ),
            row('line_note / line_ref / line_dh', '${r.lineNotes} / ${r.lineRefRows} / ${r.lineDhRows}'),
            if (r.defaultCommentators.isNotEmpty) row('מפרש ברירת מחדל', v(r.defaultCommentators)),
            if (r.linkFiles.isNotEmpty) row('קובצי קישורים', v(r.linkFiles)),
            row('contentHash', '${r.contentHash}'),
          ],
          for (final t in r.tocIssues) row('תוכן עניינים', t, bad: true),
          for (final e in r.errors) row('שגיאה', e, bad: true),
          for (final w in r.warnings) row('אזהרה', w, bad: true),
        ],
      ),
    );
  }
}

class _LinkTile extends StatelessWidget {
  const _LinkTile({required this.report});

  final LinkFileReport report;

  @override
  Widget build(BuildContext context) {
    final l = report;
    final theme = Theme.of(context);
    final bad = l.parseError != null || l.sourceProblem != null;
    final lines = <(String, bool)>[
      if (l.parseError != null) ('הקובץ לא נקרא — המחולל טוען 0 קישורים ממנו: ${l.parseError}', true),
      if (l.sourceProblem != null) (l.sourceProblem!, true),
      if (l.parseError == null)
        ('סה"כ ${l.total} · נשמרו ${l.stored} · כפולים ${l.duplicates} · הופכו ${l.flipped} · לספרייה הרשמית ${l.external}'
            ' · מוזגו כהערות ${l.mergedIntoNotes} · עוגנים ${l.anchors} · טווחים ${l.ranges}', false),
      if (l.byType.isNotEmpty) ('לפי סוג: ${l.byType.entries.map((e) => '${e.key} ${e.value}').join(', ')}', false),
      for (final e in l.dropped.entries) ('נשמטו — ${e.key}: ${e.value}', true),
      if (l.anchorsDropped > 0) ('עוגנים שנשמטו (מחוץ לטווח השורה): ${l.anchorsDropped}', true),
      if (l.rangesDropped > 0) ('טווחים שנשמטו: ${l.rangesDropped}', true),
      if (l.connectionTypeMisspelled > 0)
        ('${l.connectionTypeMisspelled} רשומות כתובות "Connection Type" — המחולל קורא רק "Conection Type", ולכן הן OTHER', true),
      for (final e in l.unknownTypes.entries) ('סוג לא מוכר "${e.key}" (${e.value}) ← OTHER', true),
      for (final e in l.missingTargets.entries.take(15)) ('ספר יעד שאינו במסד: ${e.key} (${e.value})', false),
    ];
    return Theme(
      data: theme.copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsetsDirectional.only(start: AppTokens.spaceMD, bottom: AppTokens.spaceSM),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        title: Text(l.fileName, style: theme.textTheme.bodyMedium),
        subtitle: Text(
          '${l.origin} · ${l.stored} נשמרו מתוך ${l.total}${l.droppedTotal > 0 ? ' · ${l.droppedTotal} נשמטו' : ''}',
          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        trailing: Tag(bad ? 'בעיה' : '${l.stored + l.external + l.mergedIntoNotes}', kind: bad ? TagKind.error : TagKind.good),
        children: [
          for (final (t, isBad) in lines)
            SelectableText(t, style: theme.textTheme.bodySmall?.copyWith(color: isBad ? theme.colorScheme.error : null)),
        ],
      ),
    );
  }
}
