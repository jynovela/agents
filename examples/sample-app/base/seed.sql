DROP TABLE IF EXISTS items;
CREATE TABLE items (id INTEGER PRIMARY KEY, name TEXT NOT NULL);
INSERT INTO items (id, name) VALUES
  (1, 'apple'), (2, 'banana'), (3, 'cherry'), (4, 'date'), (5, 'elderberry'),
  (6, 'fig'), (7, 'grape'), (8, 'honeydew'), (9, 'kiwi'), (10, 'lemon'),
  (11, 'mango'), (12, 'nectarine');
