-- ============================================================
-- 4KDownle 统一服务端：完整建表 + 种子数据（单文件，幂等可重复跑）
--
-- 包含：10 张表（4 授权 + 6 后台 RBAC）+ 默认角色/菜单
-- 管理员账号由 scripts/init_db.py 创建（随机密码或 ADMIN_PASSWORD），不在本文件里写死
--
-- 用法（在服务器上，容器外执行）：
--   docker exec -i <容器名> mysql -uroot -p <数据库名> < init_all.sql
-- ============================================================

-- ---------- 授权四张表 ----------
CREATE TABLE IF NOT EXISTS licenses (
  code        VARCHAR(20)  NOT NULL PRIMARY KEY,
  type        ENUM('free','perpetual') NOT NULL DEFAULT 'perpetual',
  max_devices INT          NOT NULL DEFAULT 4,
  email       VARCHAR(255) NULL,
  expire_at   BIGINT       NULL,
  status      ENUM('unused','activated','revoked') NOT NULL DEFAULT 'unused',
  created_at  DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  KEY idx_licenses_email (email)
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

-- ---------- 后台 RBAC 六张表 ----------
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

-- ============================================================
-- 种子数据（INSERT IGNORE 幂等，重复跑不报错、不覆盖已有改动）
-- ============================================================

-- 超级管理员角色
INSERT IGNORE INTO sys_roles (id, name, code, status, remark) VALUES
(1, '超级管理员', 'admin', 1, '内置超管角色');

-- 菜单树（显式 id，方便角色-菜单关联）
INSERT IGNORE INTO sys_menus (id, parent_id, menu_type, title, name, path, component, `rank`, icon) VALUES
(1, 0, 0, '系统管理', '', '/system', '', 1, 'ri:settings-3-line'),
(2, 1, 0, '用户管理', 'SystemUser', '/system/user', 'system/user/index', 1, 'ri:admin-line'),
(3, 1, 0, '角色管理', 'SystemRole', '/system/role', 'system/role/index', 2, 'ri:admin-fill'),
(4, 1, 0, '菜单管理', 'SystemMenu', '/system/menu', 'system/menu/index', 3, 'ep:menu'),
(5, 1, 0, '部门管理', 'SystemDept', '/system/dept', 'system/dept/index', 4, 'ri:git-branch-line'),
(6, 0, 0, '卡密管理', 'Card', '/card', 'card/index', 2, 'ri:coupon-3-line'),
(7, 0, 0, '任务管理', 'Task', '/task', 'task/index', 3, 'ri:list-check-2'),
(8, 0, 0, '会员管理', 'Member', '/member', 'member/index', 4, 'ri:vip-crown-line');

-- 超管角色授权全部菜单
INSERT IGNORE INTO sys_role_menus (role_id, menu_id) VALUES
(1,1),(1,2),(1,3),(1,4),(1,5),(1,6),(1,7),(1,8);

-- 默认账号不在这里创建：避免仓库里出现固定密码。
-- 建表后执行 `python scripts/init_db.py`：
--   - 配置了 ADMIN_PASSWORD 就用它；
--   - 未配置则随机生成并打印一次。
-- 已有 admin 账号时该脚本不会覆盖密码。
