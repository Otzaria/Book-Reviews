import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';

import '../theme/app_tokens.dart';
import '../widgets/app_card.dart';
import '../widgets/common_widgets.dart';

/// עזרה: מה הכלי עושה ואיך קוראים את הדוח.
class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const SelectionArea(
      child: PageBody(
        children: [
          _Section(
            title: 'איך זה עובד',
            icon: FluentIcons.lightbulb_24_regular,
            children: [
              _Steps([
                'מוסיפים את הספרים שהומרו (TXT), קובצי "הערות על X" וקובצי <שם הספר>_links.json — '
                    'קבצים בודדים, כמה יחד, תיקייה שלמה או בגרירה. כשמוסיפים ספר, נוספים אליו אוטומטית '
                    '"הערות על X" מאותה תיקייה ו-X_links.json מתיקיית links של המקור (<מקור>/links), אם הם קיימים.',
                'לוחצים "בנה ובדוק". נבנה מסד אישי שמכיל רק את הקבצים האלה, לפי כל כללי המחולל הרשמי, '
                    'והמסד נבדק בבודק המסדים של אוצריא.',
                'באוצריא: הגדרות ← ספרייה ← מסדי ספרים אישיים ← ייבא קובץ מסד, ובוחרים את הקובץ. '
                    'הספרים נראים כמו שייראו בספרייה הרשמית אחרי הבנייה השבועית.',
              ]),
              SizedBox(height: AppTokens.spaceSM),
              Hint(
                'המסד עומד בפני עצמו: המחבר, הדור, התיאורים, שנת ומקום ההדפסה, הבאנר וההגנה נלקחים מ-otzaria-library '
                '(metadata.json ו-ForDB) ונשמרים בתוכו. שום דבר אינו נקרא מהספרייה הרשמית המותקנת.',
              ),
            ],
          ),
          _Section(
            title: 'מיקום הספר (מקור וקטגוריה)',
            icon: FluentIcons.folder_24_regular,
            children: [
              _Bullets([
                'קובץ בנתיב <מקור>/ספרים/אוצריא/… (למשל בתוך otzaria-library): המקור הוא שם התיקייה, '
                    'והקטגוריה היא התיקיות שאחרי "אוצריא".',
                'אחרת, ספר שכבר קיים בספרייה באותו שם: נכנס לאותו מקום (מתאים להמרה מחדש של ספר קיים).',
                'אחרת, קובץ מתיקייה שנוספה: הקטגוריה לפי התיקיות שבתוכה; קובץ בודד: ברירת המחדל שבהגדרות.',
                '"הערות על X" הולך יחד עם X, אם אין לו מיקום משלו.',
              ]),
            ],
          ),
          _Section(
            title: 'מה בודקים בדוח',
            icon: FluentIcons.clipboard_task_list_ltr_24_regular,
            children: [
              _Bullets([
                'הערות על X: האם ימוזגו לתוך X כהערות שוליים (כמו במחולל), ואם לא — התנאי שנכשל '
                    '(שורת הערה בלי קישור, קישור מחוץ לטווח, תגית <i> בהערה, טווחים, עוגן מילה ועוד).',
                'מטא-דאטה: מחבר, דור, תיאור קצר ומלא, שנת ומקום הדפסה, באנר והגנה — ומה חסר. '
                    'כותרת ב-metadata.json עם רווח מיותר מסומנת, כי המחולל הרשמי לא ימצא אותה.',
                'שם הספר אחרי הנרמול (גרשיים ″/״, תנך ← תנ״ך) והקטגוריה הסופית.',
                'שורות וכותרות: כותרת ריקה (המחולל משמיט את השורה), קפיצת רמה, שורות לפני הכותרת הראשונה.',
                'קישורים: לכל קובץ — כמה נשמרו, כמה נשמטו ולמה (ספר חסר, מחוץ לטווח, שורת כותרת, linker), '
                    'סוג לא מוכר, "Connection Type" במקום "Conection Type", וקישורים לספרייה הרשמית.',
              ]),
            ],
          ),
          _Section(
            title: 'בודק המסדים של אוצריא',
            icon: FluentIcons.shield_checkmark_24_regular,
            children: [
              Text('אחרי הבנייה התוכנה מריצה מתוך מאגר הקוד של אוצריא:'),
              _Code('dart run tool/validate_personal_db.dart <המסד>'),
              Hint(
                'קוד 0 = תקין (ירוק), 1 = בעיה חוסמת (אדום). צריך Flutter מותקן ו-flutter pub get במאגר אוצריא; '
                'את הנתיב קובעים בהגדרות.',
              ),
            ],
          ),
          _Section(
            title: 'משורת הפקודה',
            icon: FluentIcons.code_24_regular,
            children: [
              _Code(
                'dart run tool/check_books.dart --out x.db [--library <otzaria-library>]\n'
                '    [--otzaria <מאגר אוצריא>] [--library-links] [--no-external] <קבצים או תיקיות>',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.icon, required this.children});

  final String title;
  final IconData icon;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => AppCard(
    title: title,
    icon: icon,
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
  );
}

class _Steps extends StatelessWidget {
  const _Steps(this.steps);

  final List<String> steps;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      for (var i = 0; i < steps.length; i++)
        Padding(
          padding: const EdgeInsets.only(bottom: AppTokens.spaceXS),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: 24, child: Text('${i + 1}.', style: const TextStyle(fontWeight: FontWeight.bold))),
              Expanded(child: Text(steps[i])),
            ],
          ),
        ),
    ],
  );
}

class _Bullets extends StatelessWidget {
  const _Bullets(this.items);

  final List<String> items;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      for (final t in items)
        Padding(
          padding: const EdgeInsets.only(bottom: AppTokens.spaceXS),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(width: 18, child: Text('•')),
              Expanded(child: Text(t)),
            ],
          ),
        ),
    ],
  );
}

class _Code extends StatelessWidget {
  const _Code(this.code);

  final String code;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    margin: const EdgeInsets.symmetric(vertical: AppTokens.spaceSM),
    padding: const EdgeInsets.all(AppTokens.spaceSM),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: AppTokens.borderRadiusAll,
    ),
    child: Directionality(
      textDirection: TextDirection.ltr,
      child: Text(code, style: const TextStyle(fontFamily: 'Consolas', fontSize: 13)),
    ),
  );
}
