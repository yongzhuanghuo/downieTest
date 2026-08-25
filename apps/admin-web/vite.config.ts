import { getPluginsList } from "./build/plugins.ts";
import { include, exclude } from "./build/optimize.ts";
import { type UserConfigExport, type ConfigEnv, loadEnv } from "vite";
import {
  root,
  alias,
  wrapperEnv,
  pathResolve,
  __APP_INFO__
} from "./build/utils.ts";

export default async ({ mode, command }: ConfigEnv): Promise<UserConfigExport> => {
  const { VITE_CDN, VITE_PORT, VITE_COMPRESSION, VITE_PUBLIC_PATH } =
    wrapperEnv(loadEnv(mode, root));
  // 构建时统一挂到 /admin/ 下（由 FastAPI 的 /admin 静态挂载托管）；开发态用空 base
  const base = command === "build" ? "/admin/" : VITE_PUBLIC_PATH;
  // 开发态后端地址（FastAPI 默认 3000 端口）
  const proxyTarget = {
    target: "http://127.0.0.1:3000",
    changeOrigin: true
  };
  return {
    base,
    root,
    resolve: {
      alias
    },
    // 服务端渲染
    server: {
      // 端口号
      port: VITE_PORT,
      host: "0.0.0.0",
      // 本地跨域代理：把后台接口转发到 FastAPI（默认 3000）
      proxy: {
        "/login": proxyTarget,
        "/refresh-token": proxyTarget,
        "/get-async-routes": proxyTarget,
        "/mine": proxyTarget,
        "/mine-logs": proxyTarget,
        "/user": proxyTarget,
        "/role": proxyTarget,
        "/menu": proxyTarget,
        "/dept": proxyTarget,
        "/list-all-role": proxyTarget,
        "/list-role-ids": proxyTarget,
        "/role-menu": proxyTarget,
        "/role-menu-ids": proxyTarget,
        "/card": proxyTarget,
        "/task": proxyTarget
      },
      // 预热文件以提前转换和缓存结果，降低启动期间的初始页面加载时长并防止转换瀑布
      warmup: {
        clientFiles: ["./index.html", "./src/{views,components}/*"]
      }
    },
    plugins: await getPluginsList(VITE_CDN, VITE_COMPRESSION),
    // https://cn.vitejs.dev/config/dep-optimization-options.html#dep-optimization-options
    optimizeDeps: {
      include,
      exclude
    },
    build: {
      // https://cn.vitejs.dev/guide/build.html#browser-compatibility
      target: "es2015",
      sourcemap: false,
      // 消除打包大小超过500kb警告
      chunkSizeWarningLimit: 4000,
      rolldownOptions: {
        input: {
          index: pathResolve("./index.html", import.meta.url)
        },
        // 静态资源分类打包
        output: {
          chunkFileNames: "static/js/[name]-[hash].js",
          entryFileNames: "static/js/[name]-[hash].js",
          assetFileNames: "static/[ext]/[name]-[hash].[ext]"
        },
        checks: {
          pluginTimings: false,
          toleratedTransform: false
        }
      }
    },
    define: {
      __INTLIFY_PROD_DEVTOOLS__: false,
      __APP_INFO__: JSON.stringify(__APP_INFO__)
    }
  };
};
