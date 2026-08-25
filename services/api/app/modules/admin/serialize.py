"""管理后台序列化工具：DB(snake_case) → JSON(camelCase)，以及菜单树组装。"""
import time

from .models import SysMenu


def ok(data=None, message: str = "操作成功") -> dict:
    return {"code": 0, "message": message, "data": data}


def now_ms() -> int:
    return int(time.time() * 1000)


def _b(v: int) -> bool:
    return bool(v)


def menu_to_dict(m: SysMenu) -> dict:
    """菜单管理页（/menu）用的扁平结构，字段对齐 Pure-Admin FormItemProps。"""
    return {
        "id": m.id,
        "parentId": m.parent_id,
        "menuType": m.menu_type,
        "title": m.title,
        "name": m.name or "",
        "path": m.path or "",
        "component": m.component or "",
        "rank": m.rank,
        "redirect": m.redirect or "",
        "icon": m.icon or "",
        "extraIcon": m.extra_icon or "",
        "enterTransition": m.enter_transition or "",
        "leaveTransition": m.leave_transition or "",
        "activePath": m.active_path or "",
        "auths": m.auths or "",
        "frameSrc": m.frame_src or "",
        "frameLoading": _b(m.frame_loading),
        "keepAlive": _b(m.keep_alive),
        "hiddenTag": _b(m.hidden_tag),
        "fixedTag": _b(m.fixed_tag),
        "showLink": _b(m.show_link),
        "showParent": _b(m.show_parent),
    }


def menu_to_route(m: SysMenu) -> dict:
    """动态菜单（/get-async-routes）用的路由节点。component 为相对 /src/views 的路径。"""
    node: dict = {"path": m.path or "", "meta": {}}
    if m.name:
        node["name"] = m.name
    if m.redirect:
        node["redirect"] = m.redirect
    if m.menu_type == 0 and m.component:
        node["component"] = m.component

    meta = node["meta"]
    meta["title"] = m.title
    if m.icon:
        meta["icon"] = m.icon
    if m.menu_type != 3 and m.rank is not None:
        meta["rank"] = m.rank
    meta["showLink"] = _b(m.show_link)
    if m.keep_alive:
        meta["keepAlive"] = True
    if m.frame_src:
        meta["frameSrc"] = m.frame_src
    if m.auths:
        meta["auths"] = [a for a in m.auths.split(",") if a]
    return node


def build_route_tree(menus: list[SysMenu]) -> list[dict]:
    """把扁平菜单(仅 menu_type != 3) 组装成嵌套路由树。"""
    by_id = {m.id: m for m in menus}
    nodes: dict[int, dict] = {m.id: menu_to_route(m) for m in menus}

    roots = []
    for m in menus:
        node = nodes[m.id]
        if m.parent_id and m.parent_id in by_id:
            nodes[m.parent_id].setdefault("children", []).append(node)
        else:
            roots.append(node)

    def sort_tree(items):
        items.sort(key=lambda n: n.get("meta", {}).get("rank", 99))
        for it in items:
            if "children" in it:
                sort_tree(it["children"])

    sort_tree(roots)
    return roots


def role_menu_tree(menus: list[SysMenu]) -> list[dict]:
    """角色权限面板用的精简树（parentId/id/menuType/title + children）。"""
    by_id = {m.id: m for m in menus}
    nodes: dict[int, dict] = {
        m.id: {"id": m.id, "parentId": m.parent_id, "menuType": m.menu_type, "title": m.title}
        for m in menus
    }
    roots = []
    for m in menus:
        node = nodes[m.id]
        if m.parent_id and m.parent_id in by_id:
            nodes[m.parent_id].setdefault("children", []).append(node)
        else:
            roots.append(node)
    return roots
