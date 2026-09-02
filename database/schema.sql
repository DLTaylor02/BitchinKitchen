CREATE TABLE IF NOT EXISTS settings (
  key VARCHAR(80) PRIMARY KEY, value TEXT NOT NULL
);
INSERT INTO settings (key,value) VALUES ('session_timeout_minutes','24') ON CONFLICT (key) DO NOTHING;
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
CREATE TABLE IF NOT EXISTS cuisines (
  id BIGSERIAL PRIMARY KEY, name VARCHAR(80) NOT NULL UNIQUE, is_active BOOLEAN NOT NULL DEFAULT TRUE
);
CREATE TABLE IF NOT EXISTS tags (
  id BIGSERIAL PRIMARY KEY, name VARCHAR(80) NOT NULL UNIQUE, is_active BOOLEAN NOT NULL DEFAULT TRUE
);
INSERT INTO cuisines(name) VALUES ('American'),('Caribbean'),('Chinese'),('French'),('Greek'),('Indian'),('Italian'),('Japanese'),('Korean'),('Mediterranean'),('Mexican'),('Middle Eastern'),('Thai'),('Vietnamese'),('Other') ON CONFLICT(name) DO NOTHING;
INSERT INTO tags(name) VALUES ('Baking'),('Dairy-free'),('Gluten-free'),('High protein'),('Kid-friendly'),('Low carb'),('Meal prep'),('One-pot'),('Quick'),('Spicy'),('Vegan'),('Vegetarian') ON CONFLICT(name) DO NOTHING;
CREATE TABLE IF NOT EXISTS recipes (
  id BIGSERIAL PRIMARY KEY,
  user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  forked_from_id BIGINT REFERENCES recipes(id) ON DELETE SET NULL,
  cuisine_id BIGINT REFERENCES cuisines(id) ON DELETE SET NULL,
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
CREATE INDEX IF NOT EXISTS recipes_search_idx ON recipes USING GIN(search_vector);
CREATE INDEX IF NOT EXISTS recipes_public_updated_idx ON recipes(is_public, updated_at DESC);
CREATE TABLE IF NOT EXISTS recipe_tags (
  recipe_id BIGINT NOT NULL REFERENCES recipes(id) ON DELETE CASCADE,
  tag_id BIGINT NOT NULL REFERENCES tags(id) ON DELETE RESTRICT,
  PRIMARY KEY(recipe_id,tag_id)
);
CREATE INDEX IF NOT EXISTS recipe_tags_tag_idx ON recipe_tags(tag_id,recipe_id);
CREATE TABLE IF NOT EXISTS recipe_photos (
  id BIGSERIAL PRIMARY KEY,
  recipe_id BIGINT NOT NULL REFERENCES recipes(id) ON DELETE CASCADE,
  filename VARCHAR(255) NOT NULL,
  sort_order INT NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
