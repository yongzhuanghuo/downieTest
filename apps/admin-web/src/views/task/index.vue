<script setup lang="ts">
import { onMounted, ref } from "vue";
import { getTaskList } from "@/api/task";

const list = ref<any[]>([]);
const loading = ref(false);
const statusMap: Record<string, string> = { pending: "排队中", running: "进行中", done: "已完成", error: "失败" };
const statusTag: Record<string, any> = { pending: "info", running: "primary", done: "success", error: "danger" };

async function load() {
  loading.value = true;
  try {
    const res: any = await getTaskList();
    list.value = res.data.list || [];
  } finally {
    loading.value = false;
  }
}

onMounted(load);
</script>

<template>
  <div>
    <el-button class="mb-4" @click="load">刷新</el-button>
    <el-table v-loading="loading" :data="list" border>
      <el-table-column prop="task_id" label="任务 ID" width="120" />
      <el-table-column prop="type" label="类型" width="100" />
      <el-table-column label="状态" width="100">
        <template #default="{ row }"><el-tag :type="statusTag[row.status]">{{ statusMap[row.status] }}</el-tag></template>
      </el-table-column>
      <el-table-column prop="progress" label="进度" width="100">
        <template #default="{ row }">{{ row.progress }}%</template>
      </el-table-column>
      <el-table-column prop="result_url" label="结果地址" show-overflow-tooltip />
      <el-table-column prop="error" label="错误" show-overflow-tooltip />
    </el-table>
    <el-empty v-if="!loading && list.length === 0" description="暂无任务" />
  </div>
</template>
