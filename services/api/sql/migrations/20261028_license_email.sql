-- 卡密邮箱绑定：补齐 licenses.email 与索引（可重复执行）
-- 用法：mysql -u... -p... 数据库名 < 20261028_license_email.sql
-- 说明：只加列/索引，不改动已有卡密；历史卡密 email 为 NULL，首次激活时可绑定。

SET @db_name = DATABASE();

SET @has_email = (
  SELECT COUNT(*) FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = @db_name
    AND TABLE_NAME = 'licenses'
    AND COLUMN_NAME = 'email'
);
SET @sql = IF(
  @has_email = 0,
  'ALTER TABLE licenses ADD COLUMN email VARCHAR(255) NULL AFTER max_devices',
  'SELECT 1'
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @has_index = (
  SELECT COUNT(*) FROM information_schema.STATISTICS
  WHERE TABLE_SCHEMA = @db_name
    AND TABLE_NAME = 'licenses'
    AND INDEX_NAME = 'idx_licenses_email'
);
SET @sql = IF(
  @has_index = 0,
  'ALTER TABLE licenses ADD KEY idx_licenses_email (email)',
  'SELECT 1'
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;
