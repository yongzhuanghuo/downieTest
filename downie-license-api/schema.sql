CREATE TABLE IF NOT EXISTS licenses (
  code        TEXT PRIMARY KEY,
  type        TEXT NOT NULL DEFAULT 'perpetual',
  max_devices INTEGER NOT NULL DEFAULT 4,
  nonce       INTEGER NOT NULL,
  expire_at   INTEGER,
  created_at  TEXT NOT NULL DEFAULT (datetime('now')),
  status      TEXT NOT NULL DEFAULT 'unused'
);

CREATE TABLE IF NOT EXISTS device_bindings (
  id          TEXT PRIMARY KEY,
  code        TEXT NOT NULL,
  device_fp   TEXT NOT NULL,
  device_name TEXT,
  bound_at    TEXT NOT NULL DEFAULT (datetime('now')),
  last_seen   TEXT NOT NULL DEFAULT (datetime('now')),
  status      TEXT NOT NULL DEFAULT 'active',
  UNIQUE(code, device_fp)
);

CREATE TABLE IF NOT EXISTS unbind_log (
  id          TEXT PRIMARY KEY,
  code        TEXT NOT NULL,
  device_fp   TEXT NOT NULL,
  device_name TEXT,
  unbound_at  TEXT NOT NULL DEFAULT (datetime('now')),
  reason      TEXT DEFAULT 'user_manual'
);

CREATE INDEX IF NOT EXISTS idx_bindings_code ON device_bindings(code, status);
CREATE INDEX IF NOT EXISTS idx_unbind_month ON unbind_log(code, unbound_at);
