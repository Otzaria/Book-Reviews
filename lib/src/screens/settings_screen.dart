import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';

import '../controllers/app_controller.dart';
import '../services/settings_store.dart';
import '../theme/app_tokens.dart';
import '../widgets/app_card.dart';
import '../widgets/common_widgets.dart';

/// גרסת התוכנה (מוזרקת בבנייה ב-GitHub Actions).
const appVersion = String.fromEnvironment('APP_VERSION');

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.controller});

  final AppController controller;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  AppController get c => widget.controller;
  late final _category = TextEditingController(text: c.settings.defaultCategory);
  late final _source = TextEditingController(text: c.settings.defaultSource);
  late final _author = TextEditingController(text: c.settings.author);

  @override
  void dispose() {
    _category.dispose();
    _source.dispose();
    _author.dispose();
    super.dispose();
  }

  Future<String?> _dir(String title) => FilePicker.getDirectoryPath(dialogTitle: title);

  Widget _pathRow(String label, String value, VoidCallback? onPick, {String? status, bool bad = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label),
        const SizedBox(height: AppTokens.spaceXS),
        Row(
          children: [
            Expanded(child: value.isEmpty ? const Hint('לא נבחרה תיקייה.') : PathText(value, maxLines: 2)),
            const SizedBox(width: AppTokens.spaceSM),
            OutlinedButton.icon(
              onPressed: onPick,
              icon: const Icon(FluentIcons.folder_open_24_regular),
              label: const Text('בחר'),
            ),
          ],
        ),
        if (status != null) ...[const SizedBox(height: AppTokens.spaceXS), Hint(status, error: bad)],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final s = c.settings;
        return PageBody(
          children: [
            AppCard(
              title: 'מקורות',
              icon: FluentIcons.folder_link_24_regular,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _pathRow(
                    'תיקיית otzaria-library (מיקום הספרים, metadata.json ו-ForDB)',
                    s.libraryPath,
                    c.busy
                        ? null
                        : () async {
                            final d = await _dir('בחירת תיקיית otzaria-library');
                            if (d != null) await c.setLibraryPath(d);
                          },
                    status: c.indexing
                        ? 'סורק…'
                        : c.libraryError ?? 'נמצאו ${c.libraryBookCount} ספרים בשורשים הנארזים (BOOK_ROOTS).',
                    bad: c.libraryError != null,
                  ),
                  const SizedBox(height: AppTokens.spaceMD),
                  _pathRow(
                    'מאגר הקוד של אוצריא (otzaria) — להרצת tool/validate_personal_db.dart',
                    s.otzariaRepo,
                    c.busy
                        ? null
                        : () async {
                            final d = await _dir('בחירת מאגר הקוד של אוצריא');
                            if (d != null) c.setOtzariaRepo(d);
                          },
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('להריץ את בודק המסדים של אוצריא אחרי הבנייה'),
                    subtitle: const Text('דורש Flutter/Dart מותקן ו-flutter pub get במאגר אוצריא'),
                    value: s.runValidator,
                    onChanged: c.busy ? null : c.setRunValidator,
                  ),
                ],
              ),
            ),
            AppCard(
              title: 'קישורים',
              icon: FluentIcons.link_24_regular,
              child: Column(
                children: [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('גם קישורי _links.json שבספרייה עבור הספרים שהוספתי'),
                    subtitle: const Text(
                      'לכל ספר שנוסף נלקח גם <שם>_links.json מתיקיות הקישורים הנארזות (ו-<שם>_alt_toc.json), '
                      'אם לא הוספתם קובץ באותו שם בעצמכם.',
                    ),
                    value: s.useLibraryLinks,
                    onChanged: c.busy ? null : c.setUseLibraryLinks,
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('קישורים לספרים שאינם במסד ← קישור חיצוני לספרייה הרשמית'),
                    subtitle: const Text(
                      'נשמרים בטבלה external_link, ואוצריא מציגה אותם מול הספר הרשמי. כבוי: הקישורים נשמטים (ונספרים בדוח).',
                    ),
                    value: s.externalLinks,
                    onChanged: c.busy ? null : c.setExternalLinks,
                  ),
                ],
              ),
            ),
            AppCard(
              title: 'ברירות מחדל למיקום',
              icon: FluentIcons.folder_24_regular,
              info:
                  'לקובץ שאינו בנתיב <מקור>/ספרים/אוצריא/…, שאינו קיים בספרייה ושלא נוסף דרך תיקייה. '
                  'המקור קובע גם באנר והגנה מ-ForDB (book_banners.csv / book_protection.csv).',
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _category,
                      enabled: !c.busy,
                      decoration: const InputDecoration(labelText: 'קטגוריה (אפשר נתיב עם /)', border: OutlineInputBorder()),
                      onChanged: c.setDefaultCategory,
                    ),
                  ),
                  const SizedBox(width: AppTokens.spaceSM),
                  Expanded(
                    child: TextField(
                      controller: _source,
                      enabled: !c.busy,
                      decoration: const InputDecoration(labelText: 'שם המקור (source)', border: OutlineInputBorder()),
                      onChanged: c.setDefaultSource,
                    ),
                  ),
                ],
              ),
            ),
            AppCard(
              title: 'ערכת נושא',
              icon: FluentIcons.paint_brush_24_regular,
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: SegmentedButton<ThemeMode>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: ThemeMode.system, icon: Icon(FluentIcons.desktop_24_regular, size: 18), label: Text('מערכת')),
                    ButtonSegment(value: ThemeMode.light, icon: Icon(FluentIcons.weather_sunny_24_regular, size: 18), label: Text('בהיר')),
                    ButtonSegment(value: ThemeMode.dark, icon: Icon(FluentIcons.weather_moon_24_regular, size: 18), label: Text('כהה')),
                  ],
                  selected: {c.themeMode},
                  onSelectionChanged: (v) => c.setThemeMode(v.first),
                ),
              ),
            ),
            Card(
              child: Theme(
                data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  leading: const Icon(FluentIcons.wrench_24_regular),
                  title: const Text('מתקדם'),
                  subtitle: const Text('מזהה המסד, שם העורך, קובץ ההגדרות'),
                  childrenPadding: const EdgeInsets.all(AppTokens.spaceMD),
                  expandedCrossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('מזהה המסד (library_id) של הקלט הנוכחי'),
                    const SizedBox(height: AppTokens.spaceXS),
                    Row(
                      children: [
                        Expanded(child: SelectableText(c.libraryId, style: const TextStyle(fontFamily: 'Consolas'))),
                        CopyButton(c.libraryId, onCopied: () => c.showMessage('המזהה הועתק.')),
                      ],
                    ),
                    const Hint('נגזר מקבוצת הקבצים שהוספת: אותם קבצים ← אותו מזהה (אוצריא מזהה עדכון גרסה), קבצים אחרים ← מזהה אחר (מסד נפרד).'),
                    const SizedBox(height: AppTokens.spaceSM),
                    const SizedBox(height: AppTokens.spaceMD),
                    TextField(
                      controller: _author,
                      enabled: !c.busy,
                      decoration: const InputDecoration(labelText: 'שם העורך (schema_meta.author, לא חובה)', border: OutlineInputBorder()),
                      onChanged: c.setAuthor,
                    ),
                    const Divider(height: AppTokens.spaceLG * 2),
                    const Text('קובץ ההגדרות'),
                    const SizedBox(height: AppTokens.spaceXS),
                    PathText(SettingsStore.configDir()),
                  ],
                ),
              ),
            ),
            AppCard(
              title: 'אודות',
              icon: FluentIcons.info_24_regular,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('בודק המרות לאוצריא'),
                  const SizedBox(height: 4),
                  Hint(appVersion.isEmpty ? 'גרסת פיתוח' : 'גרסה $appVersion'),
                  const SizedBox(height: AppTokens.spaceSM),
                  const Hint(
                    'בונה מסד ספרים אישי (סכמה 7) לפי כללי המחולל הרשמי של אוצריא (SeforimLibrary), '
                    'עם המטא-דאטה מ-otzaria-library, ומאמת אותו בבודק המסדים של אוצריא. '
                    'פרויקט קהילתי שאינו קשור לתוכנת אוצריא הרשמית.',
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
