-- 多产品授权：products / product_id / trials / releases
-- 幂等，可重复执行。执行前请先 mysqldump 备份。
-- 用法：mysql -u... -p... 数据库名 < 20261106_multi_product.sql

SET @db := DATABASE();

-- ---------- products ----------
CREATE TABLE IF NOT EXISTS products (
  id                  BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
  code                VARCHAR(32)  NOT NULL,
  name                VARCHAR(64)  NOT NULL,
  trial_days          INT          NOT NULL DEFAULT 14,
  default_max_devices INT          NOT NULL DEFAULT 1,
  purchase_url        VARCHAR(512) NOT NULL DEFAULT '',
  support_email       VARCHAR(255) NOT NULL DEFAULT '',
  status              TINYINT      NOT NULL DEFAULT 1,
  created_at          DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE KEY uq_products_code (code)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

INSERT IGNORE INTO products
  (id, code, name, trial_days, default_max_devices, purchase_url, support_email, status)
VALUES
  (1, 'downie6', 'Downie6', 14, 4, '', 'huoyongzhuang@qq.com', 1),
  (2, 'launch',  'launch',  14, 1, '', 'huoyongzhuang@qq.com', 1);

-- ---------- licenses.product_id ----------
SET @has_col := (
  SELECT COUNT(*) FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA=@db AND TABLE_NAME='licenses' AND COLUMN_NAME='product_id'
);
SET @sql := IF(
  @has_col = 0,
  'ALTER TABLE licenses ADD COLUMN product_id BIGINT UNSIGNED NOT NULL DEFAULT 1 AFTER code',
  'SELECT 1'
);
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @has_idx := (
  SELECT COUNT(*) FROM information_schema.STATISTICS
  WHERE TABLE_SCHEMA=@db AND TABLE_NAME='licenses' AND INDEX_NAME='idx_licenses_product_status'
);
SET @sql := IF(
  @has_idx = 0,
  'ALTER TABLE licenses ADD KEY idx_licenses_product_status (product_id, status)',
  'SELECT 1'
);
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

-- ---------- device_bindings.product_id ----------
SET @has_col := (
  SELECT COUNT(*) FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA=@db AND TABLE_NAME='device_bindings' AND COLUMN_NAME='product_id'
);
SET @sql := IF(
  @has_col = 0,
  'ALTER TABLE device_bindings ADD COLUMN product_id BIGINT UNSIGNED NOT NULL DEFAULT 1 AFTER code',
  'SELECT 1'
);
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @has_idx := (
  SELECT COUNT(*) FROM information_schema.STATISTICS
  WHERE TABLE_SCHEMA=@db AND TABLE_NAME='device_bindings' AND INDEX_NAME='idx_dev_product_fp'
);
SET @sql := IF(
  @has_idx = 0,
  'ALTER TABLE device_bindings ADD KEY idx_dev_product_fp (product_id, device_fp)',
  'SELECT 1'
);
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

-- ---------- trials ----------
CREATE TABLE IF NOT EXISTS trials (
  id          BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
  product_id  BIGINT UNSIGNED NOT NULL,
  device_fp   VARCHAR(64)  NOT NULL,
  device_name VARCHAR(255) NULL,
  platform    VARCHAR(20)  NULL,
  first_seen  DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  trial_start DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  trial_end   DATETIME     NOT NULL,
  email       VARCHAR(255) NULL,
  status      ENUM('active','expired','converted','revoked') NOT NULL DEFAULT 'active',
  last_seen   DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE KEY uq_trial_product_device (product_id, device_fp),
  KEY idx_trial_product_status_end (product_id, status, trial_end)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- 把旧 trial_devices 归到 Downie6；旧表保留作回滚备份
SET @has_old := (
  SELECT COUNT(*) FROM information_schema.TABLES
  WHERE TABLE_SCHEMA=@db AND TABLE_NAME='trial_devices'
);
SET @sql := IF(
  @has_old = 1,
  'INSERT IGNORE INTO trials (product_id, device_fp, device_name, platform, first_seen, trial_start, trial_end, email, status, last_seen) SELECT 1, device_fp, device_name, platform, first_seen, trial_start, trial_end, email, status, last_seen FROM trial_devices',
  'SELECT 1'
);
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

-- ---------- releases ----------
CREATE TABLE IF NOT EXISTS releases (
  id              BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
  product_id      BIGINT UNSIGNED NOT NULL,
  platform        VARCHAR(20)  NOT NULL DEFAULT 'macos',
  version         VARCHAR(32)  NOT NULL,
  build           INT          NOT NULL,
  artifact_url    VARCHAR(1024) NOT NULL,
  artifact_sha256 CHAR(64)     NOT NULL DEFAULT '',
  artifact_size   BIGINT       NOT NULL DEFAULT 0,
  dmg_url         VARCHAR(1024) NULL,
  changelog       TEXT         NULL,
  force_update    TINYINT      NOT NULL DEFAULT 0,
  status          ENUM('draft','published','revoked') NOT NULL DEFAULT 'published',
  published_at    DATETIME     NULL,
  created_at      DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE KEY uq_release_build (product_id, platform, build),
  KEY idx_release_latest (product_id, platform, status, build)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------- 回填 ----------
UPDATE licenses SET product_id = 1 WHERE product_id IS NULL OR product_id = 0;

UPDATE device_bindings db
JOIN licenses l ON l.code = db.code
SET db.product_id = l.product_id
WHERE db.product_id <> l.product_id;

-- ---------- 产品管理菜单 ----------
INSERT IGNORE INTO sys_menus
  (id, parent_id, menu_type, title, name, path, component, `rank`, icon)
VALUES
  (9, 0, 0, '产品管理', 'Product', '/product', 'product/index', 2, 'ri:apps-2-line');

INSERT IGNORE INTO sys_role_menus (role_id, menu_id) VALUES (1, 9);
