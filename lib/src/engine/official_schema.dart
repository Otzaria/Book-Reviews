// מבנה הטבלאות של seforim.db הרשמי בסכמה 7, מועתק כלשונו מ-sqlite_master של
// seforim.db הרשמי (C:/ProgramData/otzaria/books, db_version 36). נוצר אוטומטית; לא לערוך ביד.
// בלי zstd_dict (המסד הזה אינו דחוס) ובלי sqlite_stat*.

const officialTables = <String, String>{
  'schema_meta': r'''CREATE TABLE schema_meta (
    key   TEXT PRIMARY KEY NOT NULL,
    value TEXT NOT NULL
)''',
  'category': r'''CREATE TABLE category (
    id INTEGER PRIMARY KEY NOT NULL,
    parentId INTEGER,
    title TEXT NOT NULL,
    level INTEGER NOT NULL DEFAULT 0,
    orderIndex INTEGER NOT NULL DEFAULT 999,
    heShortDesc TEXT DEFAULT NULL,
    heDesc TEXT DEFAULT NULL,
    FOREIGN KEY (parentId) REFERENCES category(id) ON DELETE CASCADE
)''',
  'category_closure': r'''CREATE TABLE category_closure (
    ancestorId INTEGER NOT NULL,
    descendantId INTEGER NOT NULL,
    PRIMARY KEY (ancestorId, descendantId),
    FOREIGN KEY (ancestorId) REFERENCES category(id) ON DELETE CASCADE,
    FOREIGN KEY (descendantId) REFERENCES category(id) ON DELETE CASCADE
)''',
  'author': r'''CREATE TABLE author (
    id INTEGER PRIMARY KEY NOT NULL,
    name TEXT NOT NULL UNIQUE
)''',
  'topic': r'''CREATE TABLE topic (
    id INTEGER PRIMARY KEY NOT NULL,
    name TEXT NOT NULL UNIQUE
)''',
  'pub_place': r'''CREATE TABLE pub_place (
    id INTEGER PRIMARY KEY NOT NULL,
    name TEXT NOT NULL UNIQUE
)''',
  'pub_date': r'''CREATE TABLE pub_date (
    id INTEGER PRIMARY KEY NOT NULL,
    date TEXT NOT NULL UNIQUE
)''',
  'source': r'''CREATE TABLE source (
    id INTEGER PRIMARY KEY NOT NULL,
    name TEXT NOT NULL UNIQUE
)''',
  'book': r'''CREATE TABLE book (
    id INTEGER PRIMARY KEY NOT NULL,
    categoryId INTEGER NOT NULL,
    sourceId INTEGER NOT NULL,
    title TEXT NOT NULL,
    heRef TEXT,
    heShortDesc TEXT,
    -- Full (long) description in Hebrew. heShortDesc holds the one-line summary.
    heDesc TEXT,
    -- Legacy, no longer populated: 'הערות על <title>' files are standalone linked books
    notesContent TEXT,
    orderIndex INTEGER NOT NULL DEFAULT 999,
    totalLines INTEGER NOT NULL DEFAULT 0,
    isBaseBook INTEGER NOT NULL DEFAULT 0,
    hasTargumConnection INTEGER NOT NULL DEFAULT 0,
    hasReferenceConnection INTEGER NOT NULL DEFAULT 0,
    hasSourceConnection INTEGER NOT NULL DEFAULT 0,
    hasCommentaryConnection INTEGER NOT NULL DEFAULT 0,
    hasOtherConnection INTEGER NOT NULL DEFAULT 0,
    hasAltStructures INTEGER NOT NULL DEFAULT 0,
    hasTeamim INTEGER NOT NULL DEFAULT 0,
    hasNekudot INTEGER NOT NULL DEFAULT 0,
    -- Raw case-normalized dependence from schema: 'Commentary'|'Targum'|'Midrash'|'Guides';
    -- unknown future value kept verbatim (trim only). isDependant derived = NOT NULL.
    dependenceType TEXT DEFAULT NULL,
    -- schema collective_title.he (explicit grouping only; NULL when absent)
    collectiveTitleHe TEXT DEFAULT NULL,
    -- schema collective_title.en
    collectiveTitleEn TEXT DEFAULT NULL,
    -- Schema 7. Opaque 64-bit fingerprint of the book's line text and line_note rows,
    -- written by stampSchemaVersion (BookContentHash.kt). 0 = unknown.
    contentHash INTEGER NOT NULL DEFAULT 0,
    FOREIGN KEY (categoryId) REFERENCES category(id) ON DELETE CASCADE,
    FOREIGN KEY (sourceId) REFERENCES source(id) ON DELETE RESTRICT
)''',
  'book_pub_place': r'''CREATE TABLE book_pub_place (
    bookId INTEGER NOT NULL,
    pubPlaceId INTEGER NOT NULL,
    PRIMARY KEY (bookId, pubPlaceId),
    FOREIGN KEY (bookId) REFERENCES book(id) ON DELETE CASCADE,
    FOREIGN KEY (pubPlaceId) REFERENCES pub_place(id) ON DELETE CASCADE
)''',
  'book_pub_date': r'''CREATE TABLE book_pub_date (
    bookId INTEGER NOT NULL,
    pubDateId INTEGER NOT NULL,
    PRIMARY KEY (bookId, pubDateId),
    FOREIGN KEY (bookId) REFERENCES book(id) ON DELETE CASCADE,
    FOREIGN KEY (pubDateId) REFERENCES pub_date(id) ON DELETE CASCADE
)''',
  'book_topic': r'''CREATE TABLE book_topic (
    bookId INTEGER NOT NULL,
    topicId INTEGER NOT NULL,
    PRIMARY KEY (bookId, topicId),
    FOREIGN KEY (bookId) REFERENCES book(id) ON DELETE CASCADE,
    FOREIGN KEY (topicId) REFERENCES topic(id) ON DELETE CASCADE
)''',
  'book_author': r'''CREATE TABLE book_author (
    bookId INTEGER NOT NULL,
    authorId INTEGER NOT NULL,
    PRIMARY KEY (bookId, authorId),
    FOREIGN KEY (bookId) REFERENCES book(id) ON DELETE CASCADE,
    FOREIGN KEY (authorId) REFERENCES author(id) ON DELETE CASCADE
)''',
  'book_base_text': r'''CREATE TABLE book_base_text (
    bookId INTEGER NOT NULL REFERENCES book(id) ON DELETE CASCADE,
    baseBookId INTEGER NOT NULL REFERENCES book(id) ON DELETE CASCADE,
    PRIMARY KEY (bookId, baseBookId)
)''',
  'generation': r'''CREATE TABLE generation (
    id INTEGER PRIMARY KEY NOT NULL,
    name TEXT NOT NULL UNIQUE
)''',
  'book_generation': r'''CREATE TABLE book_generation (
    bookId INTEGER NOT NULL,
    generationId INTEGER NOT NULL,
    PRIMARY KEY (bookId, generationId),
    FOREIGN KEY (bookId) REFERENCES book(id) ON DELETE CASCADE,
    FOREIGN KEY (generationId) REFERENCES generation(id) ON DELETE CASCADE
)''',
  'line': r'''CREATE TABLE line (
    id INTEGER PRIMARY KEY NOT NULL,
    bookId INTEGER NOT NULL,
    lineIndex INTEGER NOT NULL,
    heRef TEXT,
    tocEntryId INTEGER,
    -- Visible character count of this line (HTML stripped). Used to compute scrollbar
    -- thumb size from the currently visible lines.
    charCount INTEGER NOT NULL DEFAULT 0,
    FOREIGN KEY (bookId) REFERENCES book(id) ON DELETE CASCADE,
    FOREIGN KEY (tocEntryId) REFERENCES tocEntry(id) ON DELETE SET NULL
)''',
  'line_ref': r'''CREATE TABLE line_ref (
    bookId INTEGER NOT NULL,
    refKeyHash INTEGER NOT NULL,
    lineIndex INTEGER NOT NULL,
    PRIMARY KEY (bookId, refKeyHash, lineIndex)
) WITHOUT ROWID''',
  'line_dh': r'''CREATE TABLE line_dh (
    bookId INTEGER NOT NULL,
    dhText TEXT NOT NULL,
    lineIndex INTEGER NOT NULL,
    dhDisplay TEXT NOT NULL,
    PRIMARY KEY (bookId, dhText, lineIndex)
) WITHOUT ROWID''',
  'tocText': r'''CREATE TABLE tocText (
    id INTEGER PRIMARY KEY NOT NULL,
    text TEXT NOT NULL UNIQUE
)''',
  'tocEntry': r'''CREATE TABLE tocEntry (
    id INTEGER PRIMARY KEY NOT NULL,
    bookId INTEGER NOT NULL,
    parentId INTEGER,
    textId INTEGER NOT NULL,
    level INTEGER NOT NULL,
    lineId INTEGER,
    isLastChild INTEGER NOT NULL DEFAULT 0,
    hasChildren INTEGER NOT NULL DEFAULT 0,
    FOREIGN KEY (bookId) REFERENCES book(id) ON DELETE CASCADE,
    FOREIGN KEY (parentId) REFERENCES tocEntry(id) ON DELETE CASCADE,
    FOREIGN KEY (textId) REFERENCES tocText(id) ON DELETE CASCADE,
    FOREIGN KEY (lineId) REFERENCES line(id) ON DELETE SET NULL
)''',
  'connection_type': r'''CREATE TABLE connection_type (
    id INTEGER PRIMARY KEY NOT NULL,
    name TEXT NOT NULL UNIQUE
)''',
  'link': r'''CREATE TABLE link (
    id INTEGER PRIMARY KEY NOT NULL,
    sourceBookId INTEGER NOT NULL,
    targetBookId INTEGER NOT NULL,
    sourceLineId INTEGER NOT NULL,
    targetLineId INTEGER NOT NULL,
    targetLineIndex INTEGER NOT NULL,
    targetBookOrderIndex INTEGER NOT NULL,
    connectionTypeId INTEGER NOT NULL,
    -- Orientation provenance: 0=NONE, 1=INFERRED_TITLE ("X on Y" parse),
    -- 2=SEFARIA_DECLARED (`base_text_titles`). Boosts declared > inferred >
    -- lateral citations in the SOURCE virtual view's ORDER BY clause.
    baseProvenance INTEGER NOT NULL DEFAULT 0,
    FOREIGN KEY (sourceBookId) REFERENCES book(id) ON DELETE CASCADE,
    FOREIGN KEY (targetBookId) REFERENCES book(id) ON DELETE CASCADE,
    FOREIGN KEY (sourceLineId) REFERENCES line(id) ON DELETE CASCADE,
    FOREIGN KEY (targetLineId) REFERENCES line(id) ON DELETE CASCADE,
    FOREIGN KEY (connectionTypeId) REFERENCES connection_type(id) ON DELETE CASCADE
)''',
  'link_anchor': r'''CREATE TABLE link_anchor (
    linkId INTEGER NOT NULL,
    side INTEGER NOT NULL DEFAULT 0,
    charStart INTEGER NOT NULL,
    charEnd INTEGER,
    label TEXT,
    PRIMARY KEY (linkId, side, charStart),
    FOREIGN KEY (linkId) REFERENCES link(id) ON DELETE CASCADE
)''',
  'link_range': r'''CREATE TABLE link_range (
    linkId INTEGER NOT NULL,
    side INTEGER NOT NULL,
    endLineId INTEGER NOT NULL,
    -- Denormalized line.lineIndex of endLineId, for display/ordering without a JOIN.
    endLineIndex INTEGER NOT NULL,
    PRIMARY KEY (linkId, side),
    FOREIGN KEY (linkId) REFERENCES link(id) ON DELETE CASCADE,
    FOREIGN KEY (endLineId) REFERENCES line(id) ON DELETE CASCADE
)''',
  'link_coverage': r'''CREATE TABLE link_coverage (
    lineId INTEGER NOT NULL,
    linkId INTEGER NOT NULL,
    side INTEGER NOT NULL,
    PRIMARY KEY (lineId, linkId, side),
    FOREIGN KEY (lineId) REFERENCES line(id) ON DELETE CASCADE,
    FOREIGN KEY (linkId) REFERENCES link(id) ON DELETE CASCADE
)''',
  'link_suppressed_side': r'''CREATE TABLE link_suppressed_side (
    linkId INTEGER NOT NULL,
    side INTEGER NOT NULL CHECK(side IN (0, 1)),
    reasonMask INTEGER NOT NULL CHECK(reasonMask > 0 AND (reasonMask & -16) = 0),
    PRIMARY KEY (linkId, side),
    FOREIGN KEY (linkId) REFERENCES link(id) ON DELETE CASCADE
)''',
  'book_has_links': r'''CREATE TABLE book_has_links (
    bookId INTEGER PRIMARY KEY,
    hasSourceLinks INTEGER NOT NULL DEFAULT 0, -- 0 = false, 1 = true
    hasTargetLinks INTEGER NOT NULL DEFAULT 0, -- 0 = false, 1 = true
    FOREIGN KEY (bookId) REFERENCES book(id) ON DELETE CASCADE
)''',
  'book_version': r'''CREATE TABLE book_version (
    id INTEGER PRIMARY KEY NOT NULL,
    bookId INTEGER NOT NULL,
    versionTitle TEXT NOT NULL,
    heVersionTitle TEXT,
    versionSource TEXT,
    priority REAL,
    license TEXT,
    versionNotes TEXT,
    heVersionNotes TEXT,
    hasContent INTEGER NOT NULL DEFAULT 0,
    UNIQUE (bookId, versionTitle),
    FOREIGN KEY (bookId) REFERENCES book(id) ON DELETE CASCADE
)''',
  'line_toc': r'''CREATE TABLE line_toc (
    lineId INTEGER PRIMARY KEY,
    tocEntryId INTEGER NOT NULL,
    FOREIGN KEY (lineId) REFERENCES line(id) ON DELETE CASCADE,
    FOREIGN KEY (tocEntryId) REFERENCES tocEntry(id) ON DELETE CASCADE
)''',
  'alt_toc_structure': r'''CREATE TABLE alt_toc_structure (
    id INTEGER PRIMARY KEY NOT NULL,
    bookId INTEGER NOT NULL,
    -- Stable key for the structure (e.g., "Parasha")
    key TEXT NOT NULL,
    title TEXT,
    heTitle TEXT,
    UNIQUE (bookId, key),
    FOREIGN KEY (bookId) REFERENCES book(id) ON DELETE CASCADE
)''',
  'alt_toc_entry': r'''CREATE TABLE alt_toc_entry (
    id INTEGER PRIMARY KEY NOT NULL,
    structureId INTEGER NOT NULL,
    parentId INTEGER,
    textId INTEGER NOT NULL,
    level INTEGER NOT NULL,
    lineId INTEGER,
    isLastChild INTEGER NOT NULL DEFAULT 0,
    hasChildren INTEGER NOT NULL DEFAULT 0,
    FOREIGN KEY (structureId) REFERENCES alt_toc_structure(id) ON DELETE CASCADE,
    FOREIGN KEY (parentId) REFERENCES alt_toc_entry(id) ON DELETE CASCADE,
    FOREIGN KEY (textId) REFERENCES tocText(id) ON DELETE CASCADE,
    FOREIGN KEY (lineId) REFERENCES line(id) ON DELETE SET NULL
)''',
  'line_alt_toc': r'''CREATE TABLE line_alt_toc (
    lineId INTEGER NOT NULL,
    structureId INTEGER NOT NULL,
    altTocEntryId INTEGER NOT NULL,
    PRIMARY KEY (lineId, structureId),
    FOREIGN KEY (lineId) REFERENCES line(id) ON DELETE CASCADE,
    FOREIGN KEY (structureId) REFERENCES alt_toc_structure(id) ON DELETE CASCADE,
    FOREIGN KEY (altTocEntryId) REFERENCES alt_toc_entry(id) ON DELETE CASCADE
)''',
  'book_acronym': r'''CREATE TABLE book_acronym (
    bookId INTEGER NOT NULL,
    term TEXT NOT NULL,
    PRIMARY KEY (bookId, term),
    FOREIGN KEY (bookId) REFERENCES book(id) ON DELETE CASCADE
)''',
  'default_commentator': r'''CREATE TABLE default_commentator (
    bookId INTEGER NOT NULL,
    commentatorBookId INTEGER NOT NULL,
    position INTEGER NOT NULL,
    PRIMARY KEY (bookId, commentatorBookId),
    FOREIGN KEY (bookId) REFERENCES book(id) ON DELETE CASCADE,
    FOREIGN KEY (commentatorBookId) REFERENCES book(id) ON DELETE CASCADE
)''',
  'default_targum': r'''CREATE TABLE default_targum (
    bookId INTEGER NOT NULL,
    targumBookId INTEGER NOT NULL,
    position INTEGER NOT NULL,
    PRIMARY KEY (bookId, targumBookId),
    FOREIGN KEY (bookId) REFERENCES book(id) ON DELETE CASCADE,
    FOREIGN KEY (targumBookId) REFERENCES book(id) ON DELETE CASCADE
)''',
  'banner': r'''CREATE TABLE banner (
    id INTEGER PRIMARY KEY NOT NULL,
    text TEXT NOT NULL
)''',
  'book_banner': r'''CREATE TABLE book_banner (
    bookId INTEGER PRIMARY KEY NOT NULL REFERENCES book(id) ON DELETE CASCADE,
    bannerId INTEGER NOT NULL REFERENCES banner(id)
)''',
  'book_protection': r'''CREATE TABLE book_protection (
    bookId INTEGER PRIMARY KEY NOT NULL REFERENCES book(id) ON DELETE CASCADE,
    level INTEGER NOT NULL CHECK (level >= 1)
)''',
  'line_divine_name': r'''CREATE TABLE line_divine_name (
    lineId INTEGER NOT NULL REFERENCES line(id) ON DELETE CASCADE,
    charStart INTEGER NOT NULL,
    span INTEGER NOT NULL,
    PRIMARY KEY (lineId, charStart)
) WITHOUT ROWID''',
  'line_note': r'''CREATE TABLE line_note (
    lineId INTEGER NOT NULL REFERENCES line(id) ON DELETE CASCADE,
    noteIndex INTEGER NOT NULL,
    charPos INTEGER NOT NULL,
    hasMarker INTEGER NOT NULL,
    body TEXT NOT NULL,
    PRIMARY KEY (lineId, noteIndex)
) WITHOUT ROWID''',
  'line_note_divine_name': r'''CREATE TABLE line_note_divine_name (
    lineId INTEGER NOT NULL,
    noteIndex INTEGER NOT NULL,
    charStart INTEGER NOT NULL,
    span INTEGER NOT NULL,
    PRIMARY KEY (lineId, noteIndex, charStart),
    FOREIGN KEY (lineId, noteIndex) REFERENCES line_note(lineId, noteIndex) ON DELETE CASCADE
) WITHOUT ROWID''',
  'line_content': r'''CREATE TABLE line_content (
    id INTEGER PRIMARY KEY NOT NULL,
    content TEXT NOT NULL,
    FOREIGN KEY (id) REFERENCES line(id) ON DELETE CASCADE
)''',
  'version_line': r'''CREATE TABLE version_line (
    versionId INTEGER NOT NULL,
    lineId INTEGER NOT NULL,
    content TEXT,
    charCount INTEGER NOT NULL DEFAULT 0,
    PRIMARY KEY (versionId, lineId),
    FOREIGN KEY (versionId) REFERENCES book_version(id) ON DELETE CASCADE,
    FOREIGN KEY (lineId) REFERENCES line(id) ON DELETE CASCADE
)''',
};

const officialIndexes = <String>[
  r'''CREATE INDEX idx_category_parent ON category(parentId)''',
  r'''CREATE INDEX idx_category_order ON category(orderIndex)''',
  r'''CREATE INDEX idx_category_closure_ancestor ON category_closure(ancestorId)''',
  r'''CREATE INDEX idx_category_closure_descendant ON category_closure(descendantId)''',
  r'''CREATE INDEX idx_author_name ON author(name)''',
  r'''CREATE INDEX idx_topic_name ON topic(name)''',
  r'''CREATE INDEX idx_pub_place_name ON pub_place(name)''',
  r'''CREATE INDEX idx_pub_date_date ON pub_date(date)''',
  r'''CREATE INDEX idx_source_name ON source(name)''',
  r'''CREATE INDEX idx_book_category ON book(categoryId)''',
  r'''CREATE INDEX idx_book_title ON book(title)''',
  r'''CREATE INDEX idx_book_order ON book(orderIndex)''',
  r'''CREATE INDEX idx_book_source ON book(sourceId)''',
  r'''CREATE INDEX idx_book_heref ON book(heRef)''',
  r'''CREATE INDEX idx_book_pub_place_book ON book_pub_place(bookId)''',
  r'''CREATE INDEX idx_book_pub_place_place ON book_pub_place(pubPlaceId)''',
  r'''CREATE INDEX idx_book_pub_date_book ON book_pub_date(bookId)''',
  r'''CREATE INDEX idx_book_pub_date_date ON book_pub_date(pubDateId)''',
  r'''CREATE INDEX idx_book_topic_book ON book_topic(bookId)''',
  r'''CREATE INDEX idx_book_topic_topic ON book_topic(topicId)''',
  r'''CREATE INDEX idx_book_author_book ON book_author(bookId)''',
  r'''CREATE INDEX idx_book_author_author ON book_author(authorId)''',
  r'''CREATE INDEX idx_book_base_text_base ON book_base_text(baseBookId)''',
  r'''CREATE INDEX idx_book_generation_generation ON book_generation(generationId)''',
  r'''CREATE INDEX idx_line_book_index ON line(bookId, lineIndex)''',
  r'''CREATE INDEX idx_line_toc ON line(tocEntryId)''',
  r'''CREATE INDEX idx_toc_text ON tocText(text)''',
  r'''CREATE INDEX idx_toctext_text_length ON tocText(text, length(text))''',
  r'''CREATE INDEX idx_toc_book ON tocEntry(bookId)''',
  r'''CREATE INDEX idx_toc_parent ON tocEntry(parentId)''',
  r'''CREATE INDEX idx_toc_text_id ON tocEntry(textId)''',
  r'''CREATE INDEX idx_toc_line ON tocEntry(lineId)''',
  r'''CREATE INDEX idx_tocentry_text_level ON tocEntry(textId, level)''',
  r'''CREATE INDEX idx_tocentry_level_book ON tocEntry(level, bookId)''',
  r'''CREATE INDEX idx_connection_type_name ON connection_type(name)''',
  r'''CREATE INDEX idx_link_source_book ON link(sourceBookId)''',
  r'''CREATE INDEX idx_link_target_book ON link(targetBookId)''',
  r'''CREATE INDEX idx_link_target_line ON link(targetLineId)''',
  r'''CREATE INDEX idx_link_type_source_line ON link(connectionTypeId, sourceLineId)''',
  r'''CREATE INDEX idx_link_source_targetorder ON link(sourceLineId, targetBookOrderIndex, targetLineIndex)''',
  r'''CREATE INDEX idx_link_type_target_line ON link(connectionTypeId, targetLineId)''',
  r'''CREATE INDEX idx_link_range_end_line ON link_range(endLineId)''',
  r'''CREATE INDEX idx_link_coverage_link ON link_coverage(linkId)''',
  r'''CREATE INDEX idx_book_has_source_links ON book_has_links(hasSourceLinks)''',
  r'''CREATE INDEX idx_book_has_target_links ON book_has_links(hasTargetLinks)''',
  r'''CREATE INDEX idx_book_version_book ON book_version(bookId)''',
  r'''CREATE INDEX idx_linetoc_toc ON line_toc(tocEntryId)''',
  r'''CREATE INDEX idx_alt_toc_structure_book ON alt_toc_structure(bookId)''',
  r'''CREATE INDEX idx_alt_toc_structure_key ON alt_toc_structure(key)''',
  r'''CREATE INDEX idx_alt_toc_entry_structure ON alt_toc_entry(structureId)''',
  r'''CREATE INDEX idx_alt_toc_entry_parent ON alt_toc_entry(parentId)''',
  r'''CREATE INDEX idx_alt_toc_entry_text ON alt_toc_entry(textId)''',
  r'''CREATE INDEX idx_alt_toc_entry_line ON alt_toc_entry(lineId)''',
  r'''CREATE INDEX idx_line_alt_toc_entry ON line_alt_toc(altTocEntryId)''',
  r'''CREATE INDEX idx_line_alt_toc_structure ON line_alt_toc(structureId)''',
  r'''CREATE INDEX idx_book_acronym_term ON book_acronym(term)''',
  r'''CREATE INDEX idx_default_commentator_book ON default_commentator(bookId)''',
  r'''CREATE INDEX idx_default_commentator_commentator ON default_commentator(commentatorBookId)''',
  r'''CREATE INDEX idx_default_targum_book ON default_targum(bookId)''',
  r'''CREATE INDEX idx_default_targum_target ON default_targum(targumBookId)''',
  r'''CREATE INDEX idx_version_line_line ON version_line(lineId)''',
];
