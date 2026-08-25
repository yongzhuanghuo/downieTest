import { http } from "@/utils/http";

type Result = {
  code: number;
  message: string;
  data?: Array<any>;
};

type ResultTable = {
  code: number;
  message: string;
  data?: {
    /** 列表数据 */
    list: Array<any>;
    /** 总条目数 */
    total?: number;
    /** 每页显示条目个数 */
    pageSize?: number;
    /** 当前页数 */
    currentPage?: number;
  };
};

/** 获取系统管理-用户管理列表 */
export const getUserList = (data?: object) => {
  return http.request<ResultTable>("post", "/user", { data });
};

/** 系统管理-用户管理-获取所有角色列表 */
export const getAllRoleList = () => {
  return http.request<Result>("get", "/list-all-role");
};

/** 系统管理-用户管理-根据userId，获取对应角色id列表（userId：用户id） */
export const getRoleIds = (data?: object) => {
  return http.request<Result>("post", "/list-role-ids", { data });
};

/** 获取系统管理-角色管理列表 */
export const getRoleList = (data?: object) => {
  return http.request<ResultTable>("post", "/role", { data });
};

/** 获取系统管理-菜单管理列表 */
export const getMenuList = (data?: object) => {
  return http.request<Result>("post", "/menu", { data });
};

/** 获取系统管理-部门管理列表 */
export const getDeptList = (data?: object) => {
  return http.request<Result>("post", "/dept", { data });
};

/** 获取系统监控-在线用户列表 */
export const getOnlineLogsList = (data?: object) => {
  return http.request<ResultTable>("post", "/online-logs", { data });
};

/** 获取系统监控-登录日志列表 */
export const getLoginLogsList = (data?: object) => {
  return http.request<ResultTable>("post", "/login-logs", { data });
};

/** 获取系统监控-操作日志列表 */
export const getOperationLogsList = (data?: object) => {
  return http.request<ResultTable>("post", "/operation-logs", { data });
};

/** 获取系统监控-系统日志列表 */
export const getSystemLogsList = (data?: object) => {
  return http.request<ResultTable>("post", "/system-logs", { data });
};

/** 获取系统监控-系统日志-根据 id 查日志详情 */
export const getSystemLogsDetail = (data?: object) => {
  return http.request<Result>("post", "/system-logs-detail", { data });
};

/** 获取角色管理-权限-菜单权限 */
export const getRoleMenu = (data?: object) => {
  return http.request<Result>("post", "/role-menu", { data });
};

/** 获取角色管理-权限-菜单权限-根据角色 id 查对应菜单 */
export const getRoleMenuIds = (data?: object) => {
  return http.request<Result>("post", "/role-menu-ids", { data });
};

// ---------- 以下为对接自建后端新增的写接口 ----------

/** 用户：新增 */
export const createUser = (data?: object) => {
  return http.request<Result>("post", "/user/create", { data });
};
/** 用户：修改 */
export const updateUser = (id: number, data?: object) => {
  return http.request<Result>("put", `/user/${id}`, { data });
};
/** 用户：删除 */
export const deleteUser = (id: number) => {
  return http.request<Result>("delete", `/user/${id}`);
};
/** 用户：状态切换 */
export const toggleUserStatus = (id: number, data?: object) => {
  return http.request<Result>("put", `/user/${id}/status`, { data });
};
/** 用户：重置密码 */
export const resetUserPassword = (data?: object) => {
  return http.request<Result>("post", "/user/reset-password", { data });
};
/** 用户：分配角色 */
export const assignUserRole = (data?: object) => {
  return http.request<Result>("post", "/user/assign-role", { data });
};

/** 角色：新增 */
export const createRole = (data?: object) => {
  return http.request<Result>("post", "/role/create", { data });
};
/** 角色：修改 */
export const updateRole = (id: number, data?: object) => {
  return http.request<Result>("put", `/role/${id}`, { data });
};
/** 角色：删除 */
export const deleteRole = (id: number) => {
  return http.request<Result>("delete", `/role/${id}`);
};
/** 角色：分配菜单 */
export const assignRoleMenu = (data?: object) => {
  return http.request<Result>("post", "/role/assign-menu", { data });
};

/** 菜单：新增 */
export const createMenu = (data?: object) => {
  return http.request<Result>("post", "/menu/create", { data });
};
/** 菜单：修改 */
export const updateMenu = (id: number, data?: object) => {
  return http.request<Result>("put", `/menu/${id}`, { data });
};
/** 菜单：删除 */
export const deleteMenu = (id: number) => {
  return http.request<Result>("delete", `/menu/${id}`);
};

/** 部门：新增 */
export const createDept = (data?: object) => {
  return http.request<Result>("post", "/dept/create", { data });
};
/** 部门：修改 */
export const updateDept = (id: number, data?: object) => {
  return http.request<Result>("put", `/dept/${id}`, { data });
};
/** 部门：删除 */
export const deleteDept = (id: number) => {
  return http.request<Result>("delete", `/dept/${id}`);
};
