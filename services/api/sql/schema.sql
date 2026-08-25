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

-- ============================================================
-- 管理后台 RBAC（Pure-Admin 对接）
-- ============================================================

CREATE TABLE IF NOT EXISTS sys_depts (
  id          BIGINT       NOT NULL AUTO_INCREMENT PRIMARY KEY,
  parent_id   BIGINT       NOT NULL DEFAULT 0,
  name        VARCHAR(50)  NOT NULL,
  sort        INT          NOT NULL DEFAULT 0,
  phone       VARCHAR(20)  NULL,
  principal   VARCHAR(50)  NULL,
  email       VARCHAR(100) NULL,
  status      TINYINT      NOT NULL DEFAULT 1,
  `type`      TINYINT      NOT NULL DEFAULT 3 COMMENT '1公司 2分公司 3部门',
  create_time BIGINT       NOT NULL DEFAULT 0,
  remark      VARCHAR(255) NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS sys_roles (
  id          BIGINT       NOT NULL AUTO_INCREMENT PRIMARY KEY,
  name        VARCHAR(50)  NOT NULL,
  code        VARCHAR(50)  NOT NULL,
  status      TINYINT      NOT NULL DEFAULT 1,
  remark      VARCHAR(255) NULL,
  create_time BIGINT       NOT NULL DEFAULT 0,
  update_time BIGINT       NOT NULL DEFAULT 0,
  UNIQUE KEY uq_role_code (code)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS sys_users (
  id            BIGINT       NOT NULL AUTO_INCREMENT PRIMARY KEY,
  username      VARCHAR(50)  NOT NULL,
  password_hash VARCHAR(255) NOT NULL,
  nickname      VARCHAR(50)  NULL,
  avatar        VARCHAR(255) NULL,
  sex           TINYINT      NOT NULL DEFAULT 0 COMMENT '0男 1女',
  phone         VARCHAR(20)  NULL,
  email         VARCHAR(100) NULL,
  status        TINYINT      NOT NULL DEFAULT 1 COMMENT '1启用 0停用',
  dept_id       BIGINT       NULL,
  remark        VARCHAR(255) NULL,
  create_time   BIGINT       NOT NULL DEFAULT 0,
  update_time   BIGINT       NOT NULL DEFAULT 0,
  UNIQUE KEY uq_user_username (username)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS sys_menus (
  id               BIGINT       NOT NULL AUTO_INCREMENT PRIMARY KEY,
  parent_id        BIGINT       NOT NULL DEFAULT 0,
  menu_type        TINYINT      NOT NULL DEFAULT 0 COMMENT '0菜单 1iframe 2外链 3按钮',
  title            VARCHAR(50)  NOT NULL,
  name             VARCHAR(50)  NULL,
  path             VARCHAR(255) NULL,
  component        VARCHAR(255) NULL,
  `rank`           INT          NOT NULL DEFAULT 99,
  redirect         VARCHAR(255) NULL,
  icon             VARCHAR(50)  NULL,
  extra_icon       VARCHAR(50)  NULL,
  enter_transition VARCHAR(50)  NULL,
  leave_transition VARCHAR(50)  NULL,
  active_path      VARCHAR(255) NULL,
  auths            VARCHAR(100) NULL,
  frame_src        VARCHAR(255) NULL,
  frame_loading    TINYINT      NOT NULL DEFAULT 1,
  keep_alive       TINYINT      NOT NULL DEFAULT 0,
  hidden_tag       TINYINT      NOT NULL DEFAULT 0,
  fixed_tag        TINYINT      NOT NULL DEFAULT 0,
  show_link        TINYINT      NOT NULL DEFAULT 1,
  show_parent      TINYINT      NOT NULL DEFAULT 0
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS sys_role_menus (
  role_id BIGINT NOT NULL,
  menu_id BIGINT NOT NULL,
  PRIMARY KEY (role_id, menu_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS sys_user_roles (
  user_id BIGINT NOT NULL,
  role_id BIGINT NOT NULL,
  PRIMARY KEY (user_id, role_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
