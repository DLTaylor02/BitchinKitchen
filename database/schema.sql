CREATE TABLE IF NOT EXISTS settings (
  key VARCHAR(80) PRIMARY KEY, value TEXT NOT NULL
);
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
CREATE TABLE IF NOT EXISTS recipes (
  id BIGSERIAL PRIMARY KEY,
  user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  forked_from_id BIGINT REFERENCES recipes(id) ON DELETE SET NULL,
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
CREATE INDEX IF NOT EXISTS recipes_search_idx ON recipes USING GIN(search_vector);
CREATE INDEX IF NOT EXISTS recipes_public_updated_idx ON recipes(is_public, updated_at DESC);
CREATE TABLE IF NOT EXISTS recipe_photos (
  id BIGSERIAL PRIMARY KEY,
  recipe_id BIGINT NOT NULL REFERENCES recipes(id) ON DELETE CASCADE,
  filename VARCHAR(255) NOT NULL,
  sort_order INT NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
