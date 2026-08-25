import { http } from "@/utils/http";

type Result = {
  code: number;
  message: string;
  data?: any;
};

export const getCardStats = () => {
  return http.request<Result>("post", "/card/stats");
};

export const getCardList = (data?: object) => {
  return http.request<Result>("post", "/card/list", { data });
};

export const generateCards = (data?: object) => {
  return http.request<Result>("post", "/card/generate", { data });
};

export const getCardDetail = (code: string) => {
  return http.request<Result>("get", `/card/${code}`);
};

export const revokeCard = (code: string) => {
  return http.request<Result>("post", `/card/${code}/revoke`);
};

export const restoreCard = (code: string) => {
  return http.request<Result>("post", `/card/${code}/restore`);
};

export const exportCards = (params?: object) => {
  return http.request<any>("get", "/card/export", { params, responseType: "blob" });
};
