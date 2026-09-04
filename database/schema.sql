CREATE TABLE IF NOT EXISTS settings (
  key VARCHAR(80) PRIMARY KEY, value TEXT NOT NULL
);
INSERT INTO settings (key,value) VALUES ('session_timeout_minutes','24') ON CONFLICT (key) DO NOTHING;
INSERT INTO settings (key,value) VALUES
  ('login_max_attempts','5'),
  ('login_window_minutes','15'),
  ('login_lockout_minutes','15'),
  ('password_min_length','12'),
  ('password_min_strength','strong'),
  ('breach_check_enabled','true')
ON CONFLICT (key) DO NOTHING;
CREATE TABLE IF NOT EXISTS users (
  id BIGSERIAL PRIMARY KEY,
  name VARCHAR(100) NOT NULL,
  password_hash VARCHAR(255) NOT NULL,
  role VARCHAR(20) NOT NULL DEFAULT 'user' CHECK (role IN ('superadmin','admin','user')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
ALTER TABLE users DROP COLUMN IF EXISTS email;
CREATE UNIQUE INDEX IF NOT EXISTS users_name_unique ON users (lower(name));
CREATE UNIQUE INDEX IF NOT EXISTS one_superadmin ON users ((role)) WHERE role = 'superadmin';
CREATE TABLE IF NOT EXISTS login_throttles (
  username VARCHAR(100) NOT NULL,
  ip_address VARCHAR(45) NOT NULL,
  failed_attempts INT NOT NULL DEFAULT 0,
  window_started TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  locked_until TIMESTAMPTZ,
  PRIMARY KEY(username,ip_address)
);
CREATE INDEX IF NOT EXISTS login_throttles_expiry_idx ON login_throttles(locked_until);
CREATE TABLE IF NOT EXISTS cuisines (
  id BIGSERIAL PRIMARY KEY, name VARCHAR(80) NOT NULL UNIQUE, is_active BOOLEAN NOT NULL DEFAULT TRUE
);
CREATE TABLE IF NOT EXISTS tags (
  id BIGSERIAL PRIMARY KEY, name VARCHAR(80) NOT NULL UNIQUE, is_active BOOLEAN NOT NULL DEFAULT TRUE
);
INSERT INTO cuisines(name) VALUES ('American'),('Caribbean'),('Chinese'),('French'),('Greek'),('Indian'),('Italian'),('Japanese'),('Korean'),('Mediterranean'),('Mexican'),('Middle Eastern'),('Thai'),('Vietnamese'),('Other') ON CONFLICT(name) DO NOTHING;
INSERT INTO tags(name) VALUES ('Air fryer'),('Baked'),('Braised'),('Broiled'),('Dairy-free'),('Deep-fried'),('Gluten-free'),('Grilled'),('High protein'),('Instant Pot'),('Kid-friendly'),('Low carb'),('Meal prep'),('No-cook / No-bake'),('One-pot'),('Pan-fried'),('Pressure cooked'),('Quick'),('Roasted'),('Sautéed'),('Slow cooker'),('Smoked'),('Sous vide'),('Spicy'),('Steamed'),('Stir-fried'),('Vegan'),('Vegetarian') ON CONFLICT(name) DO NOTHING;
CREATE TABLE IF NOT EXISTS recipes (
  id BIGSERIAL PRIMARY KEY,
  user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  forked_from_id BIGINT REFERENCES recipes(id) ON DELETE SET NULL,
  cuisine_id BIGINT REFERENCES cuisines(id) ON DELETE SET NULL,
  source_url TEXT,
  source_name VARCHAR(120),
  source_author VARCHAR(180),
  title VARCHAR(180) NOT NULL,
  summary TEXT NOT NULL DEFAULT '',
  ingredients TEXT NOT NULL,
  instructions TEXT NOT NULL,
  notes TEXT NOT NULL DEFAULT '',
  is_public BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  search_vector TSVECTOR GENERATED ALWAYS AS (
    setweight(to_tsvector('english', coalesce(title,'')), 'A') ||
    setweight(to_tsvector('english', coalesce(summary,'')), 'B') ||
    setweight(to_tsvector('english', coalesce(ingredients,'')), 'C')
  ) STORED
);
ALTER TABLE recipes ADD COLUMN IF NOT EXISTS cuisine_id BIGINT REFERENCES cuisines(id) ON DELETE SET NULL;
ALTER TABLE recipes ADD COLUMN IF NOT EXISTS source_url TEXT;
ALTER TABLE recipes ADD COLUMN IF NOT EXISTS source_name VARCHAR(120);
ALTER TABLE recipes ADD COLUMN IF NOT EXISTS source_author VARCHAR(180);
CREATE INDEX IF NOT EXISTS recipes_search_idx ON recipes USING GIN(search_vector);
CREATE INDEX IF NOT EXISTS recipes_public_updated_idx ON recipes(is_public, updated_at DESC);
CREATE TABLE IF NOT EXISTS recipe_tags (
  recipe_id BIGINT NOT NULL REFERENCES recipes(id) ON DELETE CASCADE,
  tag_id BIGINT NOT NULL REFERENCES tags(id) ON DELETE RESTRICT,
  PRIMARY KEY(recipe_id,tag_id)
);
CREATE INDEX IF NOT EXISTS recipe_tags_tag_idx ON recipe_tags(tag_id,recipe_id);
INSERT INTO recipe_tags(recipe_id,tag_id)
SELECT rt.recipe_id,replacement.id FROM recipe_tags rt JOIN tags old ON old.id=rt.tag_id CROSS JOIN tags replacement WHERE old.name='Baking' AND replacement.name='Baked'
ON CONFLICT DO NOTHING;
DELETE FROM recipe_tags WHERE tag_id IN (SELECT id FROM tags WHERE name='Baking');
DELETE FROM tags WHERE name='Baking';
CREATE TABLE IF NOT EXISTS recipe_photos (
  id BIGSERIAL PRIMARY KEY,
  recipe_id BIGINT NOT NULL REFERENCES recipes(id) ON DELETE CASCADE,
  filename VARCHAR(255) NOT NULL,
  sort_order INT NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE TABLE IF NOT EXISTS user_favorites (
  user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  recipe_id BIGINT NOT NULL REFERENCES recipes(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY(user_id,recipe_id)
);
CREATE INDEX IF NOT EXISTS user_favorites_recipe_idx ON user_favorites(recipe_id);
