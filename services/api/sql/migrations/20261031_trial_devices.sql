-- 补齐 trial_devices 表（早期 init_all.sql 漏建，导致 /api/license/trial/start 500）
-- 用法：mysql -u... -p... 数据库名 < 20261031_trial_devices.sql
-- 说明：幂等，可重复执行。

CREATE TABLE IF NOT EXISTS trial_devices (
  device_fp   VARCHAR(64)  NOT NULL PRIMARY KEY,
  device_name VARCHAR(255) NULL,
  platform    VARCHAR(20)  NULL,
  first_seen  DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  trial_start DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  trial_end   DATETIME     NOT NULL,
  email       VARCHAR(255) NULL,
  status      ENUM('active','expired','converted','revoked') NOT NULL DEFAULT 'active',
  last_seen   DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
