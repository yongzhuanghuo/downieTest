-- ============================================================
-- 4KDownle 统一服务端：完整建表 + 种子数据（单文件，幂等可重复跑）
--
-- 包含：9 张表（3 授权 + 6 后台 RBAC）+ 默认角色/菜单/账号
-- 默认账号：admin  /  初始密码：admin123（登录后到后台改）
--
-- 用法（在服务器上，容器外执行）：
--   docker exec -i <容器名> mysql -uroot -p <数据库名> < init_all.sql
-- ============================================================

-- ---------- 授权三张表 ----------
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

-- 默认账号 admin（密码 bcrypt 加密，初始密码 admin123）
INSERT IGNORE INTO sys_users (id, username, password_hash, nickname, status) VALUES
(1, 'admin', '$2b$12$T0ntrhGtjmDmyWtJwB68YeKhZ0QVvXAk6TdYzol77sxLgaPRnaoDa', '管理员', 1);

-- admin -> 超管角色
INSERT IGNORE INTO sys_user_roles (user_id, role_id) VALUES (1, 1);
