# בודק המרות לאוצריא

תוכנת Windows שבודקת שספר שהומר לפורמט אוצריא ייראה בדיוק כמו ספר בספרייה הרשמית —
עוד לפני שהוא נכנס לבנייה השבועית של `seforim.db`.

מוסיפים את קובצי הספר (TXT), את קובצי "הערות על X" ואת קובצי `<שם הספר>_links.json`.
כשמוסיפים ספר, התוכנה מוסיפה אליו אוטומטית את "הערות על X" מאותה תיקייה ואת
`X_links.json` מתיקיית `links` של המקור (`<מקור>/links`), אם הם קיימים.
התוכנה בונה **מסד ספרים אישי נפרד** (סכמה 7, כמו `seforim.db` הרשמי) שמכיל רק אותם, לפי
כל כללי המחולל הרשמי (SeforimLibrary), ומריצה עליו את בודק המסדים של אוצריא.
את המסד מצרפים באוצריא: **הגדרות ← ספרייה ← מסדי ספרים אישיים ← ייבא קובץ מסד**.

## מה נבדק ונבנה

- **מיקום**: נתיב `<מקור>/ספרים/אוצריא/…` קובע מקור וקטגוריה; אחרת ספר קיים באותו שם
  ב-otzaria-library (לפי `BOOK_ROOTS`); אחרת התיקייה שנוספה או ברירת המחדל שבהגדרות.
  שמות קטגוריות מותאמים לעץ הרשמי (למשל "רמחל" ← "רמח״ל").
- **שם הספר**: הנרמול של `CategoryLabels.bookTitle` (גרשיים, גרש, רווחים, תנך ← תנ״ך).
- **שורות ותוכן עניינים**: `lines()` של Kotlin, BOM, heRef `"<שם> <מספר>"` לשורה רגילה, כותרות
  h1–h6 עם הטקסט שמנקה Jsoup, הורה = הכותרת הפתוחה הקרובה, `line_toc`, `charCount`.
  כותרת ריקה מושמטת מהמסד (כמו במחולל) ומדווחת.
- **הערות על X**: אותה תוכנית מיזוג של המחולל (`HearotCompanionMerge`): ימוזגו כהערות שוליים
  (`line_note`) רק אם כל התנאים מתקיימים; אחרת נשארות ספר עצמאי עם קישורי FOOTNOTES ומפרש
  ברירת מחדל. הדוח מציג את ההחלטה ואת התנאי שנכשל.
- **קישורים**: `Conection Type` (באיות של המחולל), היפוך `source`, כלל ספר הבסיס, דילוג על
  כותרות ושורות מחוץ לטווח, `linker`, עוגנים, טווחים, `book_has_links` ודגלי `has*Connection`.
  קישור לספר שאינו במסד ← `external_link` לספרייה הרשמית (אפשרות).
- **מטא-דאטה**, נשמרת בתוך המסד (לא תלויה בספרייה הרשמית): מחבר (`metadata.json`), דור
  (`ForDB/book_info.csv`), תיאור קצר ומלא (`sefaria_metadata_changes.csv`), שנה ומקום הדפסה
  (`metadata.json` + `all_metadata.json`), נושאים, באנר והגנה (`book_banners.csv`,
  `book_protection.csv`), `orderIndex`, ספר בסיס (`priority.txt`), תיאורי קטגוריות.
- **אינדקסים**: `line_ref`, `line_dh`, `book.contentHash` (זהה לערך במסד הרשמי).

לא נעשה כאן קישור אוטומטי לספרייה הרשמית (linker, התאמת דיבור המתחיל וכו').

## הרצה

- `OtzariaBookChecker.exe` מתוך ה-Release (קובץ יחיד, בלי התקנה), או `OtzariaBookChecker-windows.zip`.
- בהגדרות: תיקיית otzaria-library, ותיקיית מאגר הקוד של אוצריא (להרצת
  `dart run tool/validate_personal_db.dart`; דורש Flutter מותקן ו-`flutter pub get` במאגר).

משורת הפקודה (אותו מנוע):

```
dart run tool/check_books.dart --out x.db --library <otzaria-library> [--otzaria <מאגר אוצריא>]
    [--library-links] [--no-external] [--category <נתיב>] [--source <שם>] <קבצים או תיקיות>
```

## פיתוח

```
flutter pub get
flutter analyze
flutter test
flutter build windows --release
```

הבדיקות שתלויות ב-otzaria-library במחשב מדלגות כשהיא חסרה (למשל ב-CI).

## גרסאות ו-Releases

כל push ל-`main` (או הרצה ידנית של ה-workflow) מריץ את `.github/workflows/build.yml`: בדיקות,
בנייה ל-Windows, ואריזה ל-`OtzariaBookChecker.exe` (קובץ יחיד) ול-`OtzariaBookChecker-windows.zip`,
שמצורפים ל-Release חדש. מספר הגרסה הוא `vMAJOR.MINOR.PATCH`: התג הגבוה ביותר עולה ב-1 במספר
האחרון (הראשון: `v1.0.1`). לשינוי MAJOR/MINOR יוצרים תג ידני (למשל `v1.1.0`), והריצות הבאות
ממשיכות ממנו.

פרויקט קהילתי שאינו קשור לתוכנת אוצריא הרשמית.
