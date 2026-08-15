-- Downie 授权后端 MySQL 建表语句
-- 字符集统一 utf8mb4，存储引擎 InnoDB

CREATE TABLE IF NOT EXISTS licenses (
  code        VARCHAR(20)  NOT NULL PRIMARY KEY,
  type        ENUM('free','perpetual') NOT NULL DEFAULT 'perpetual',
  max_devices INT          NOT NULL DEFAULT 4,
  expire_at   BIGINT       NULL,
  status      ENUM('unused','activated','revoked') NOT NULL DEFAULT 'unused',
  created_at  DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS device_bindings (
  id          CHAR(36)     NOT NULL PRIMARY KEY,
  code        VARCHAR(20)  NOT NULL,
  device_fp   VARCHAR(64)  NOT NULL,
  device_name VARCHAR(255) NULL,
  bound_at    DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  last_seen   DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  status      ENUM('active','unbound') NOT NULL DEFAULT 'active',
  UNIQUE KEY uq_code_fp (code, device_fp),
  KEY idx_code_status (code, status)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS unbind_log (
  id          CHAR(36)     NOT NULL PRIMARY KEY,
  code        VARCHAR(20)  NOT NULL,
  device_fp   VARCHAR(64)  NOT NULL,
  device_name VARCHAR(255) NULL,
  unbound_at  DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  reason      VARCHAR(50)  NOT NULL DEFAULT 'user_manual',
  KEY idx_code_time (code, unbound_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
