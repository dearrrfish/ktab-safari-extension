DROP TABLE IF EXISTS `bookmarks`;
CREATE TABLE `bookmarks` (
    id TEXT NOT NULL PRIMARY KEY,
    url TEXT NOT NULL,
    visit INTEGER DEFAULT 0,
    favorite BOOLEAN DEFAULT false,
    title TEXT,
    favicon TEXT,
    created TEXT NOT NULL DEFAULT '1987-01-09T00:00:00'
);

DROP TABLE IF EXISTS `tags`;
CREATE TABLE `tags` (
    id TEXT NOT NULL PRIMARY KEY,
    name TEXT NOT NULL UNIQUE,
    created TEXT NOT NULL DEFAULT '1987-01-09T00:00:00'
);

DROP TABLE IF EXISTS `link-bookmark-tag`;
CREATE TABLE `link-bookmark-tag` (
    bookmark_id TEXT NOT NULL,
    tag_id TEXT NOT NULL,
    created TEXT NOT NULL DEFAULT '1987-01-09T00:00:00',
    FOREIGN KEY (bookmark_id) REFERENCES bookmarks (id),
    FOREIGN KEY (tag_id) REFERENCES tags (id),
    CONSTRAINT pk_bookmarkTag PRIMARY KEY (bookmark_id, tag_id)
);

DROP TABLE IF EXISTS `hotkeys`;
CREATE TABLE `hotkeys` (
    key INTEGER NOT NULL,
    fkey INTEGER NOT NULL,
    bookmark_id INTEGER NOT NULL,
    hotkey_string TEXT,
    created TEXT NOT NULL DEFAULT '1987-01-09T00:00:00',
    FOREIGN KEY (bookmark_id) REFERENCES bookmarks (id),
    CONSTRAINT pk_hotkey PRIMARY KEY (key, fkey)
);

