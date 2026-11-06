import { http } from "@/utils/http";

type Result = {
  code: number;
  message: string;
  data?: any;
};

export const getProducts = () => {
  return http.request<Result>("post", "/product/list");
};

export const createProduct = (data: object) => {
  return http.request<Result>("post", "/product/create", { data });
};

export const updateProduct = (data: object) => {
  return http.request<Result>("post", "/product/update", { data });
};
