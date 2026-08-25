import { http } from "@/utils/http";

type Result = {
  code: number;
  message: string;
  data?: any;
};

export const getTaskList = (data?: object) => {
  return http.request<Result>("post", "/task/list", { data });
};
