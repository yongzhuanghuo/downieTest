<script setup lang="ts">
import { computed, onMounted, reactive, ref } from "vue";
import { ElMessage, ElMessageBox } from "element-plus";
import {
  exportCards,
  generateCards,
  getCardDetail,
  getCardList,
  getCardStats,
  restoreCard,
  revokeCard
} from "@/api/card";

const typeMap: Record<string, string> = { free: "免费版", perpetual: "永久版" };
const statusMap: Record<string, string> = { unused: "未激活", activated: "已激活", revoked: "已吊销" };
const statusTag: Record<string, any> = { unused: "info", activated: "success", revoked: "danger" };

const stats = ref<any>({});
const list = ref<any[]>([]);
const total = ref(0);
const loading = ref(false);
const query = reactive({ search: "", status: "", type: "", page: 1, pageSize: 20 });

const genVisible = ref(false);
const gen = reactive({ type: "perpetual", count: 10, devices: 4, expire_days: 0 });
const genLoading = ref(false);

const resultVisible = ref(false);
const resultCodes = ref<string[]>([]);

const detailVisible = ref(false);
const detail = ref<any>(null);

const statCards = computed(() => [
  { label: "总激活码", value: stats.value.total ?? "-" },
  { label: "未激活", value: stats.value.unused ?? "-" },
  { label: "已激活", value: stats.value.activated ?? "-" },
  { label: "已吊销", value: stats.value.revoked ?? "-" },
  { label: "免费版", value: stats.value.free ?? "-" },
  { label: "永久版", value: stats.value.perpetual ?? "-" },
  { label: "已绑定设备", value: stats.value.bound_devices ?? "-" }
]);

async function load() {
  loading.value = true;
  try {
    const params: Record<string, any> = { page: query.page, pageSize: query.pageSize };
    if (query.search) params.search = query.search;
    if (query.status) params.status = query.status;
    if (query.type) params.type = query.type;
    const res: any = await getCardList(params);
    list.value = res.data.list;
    total.value = res.data.total;
  } finally {
    loading.value = false;
  }
}

async function loadStats() {
  const res: any = await getCardStats();
  stats.value = res.data;
}

async function onGenerate() {
  genLoading.value = true;
  try {
    const res: any = await generateCards(gen);
    resultCodes.value = res.data.codes;
    genVisible.value = false;
    resultVisible.value = true;
    load();
    loadStats();
  } finally {
    genLoading.value = false;
  }
}

function onCopy() {
  navigator.clipboard.writeText(resultCodes.value.join("\n"));
  ElMessage.success("已复制");
}

async function onDetail(code: string) {
  const res: any = await getCardDetail(code);
  detail.value = res.data;
  detailVisible.value = true;
}

async function onRevoke(row: any) {
  await ElMessageBox.confirm(`确认吊销 ${row.formatted}？`, "提示", { type: "warning" });
  await revokeCard(row.code);
  ElMessage.success("已吊销");
  load();
  loadStats();
}

async function onRestore(row: any) {
  await restoreCard(row.code);
  ElMessage.success("已恢复");
  load();
  loadStats();
}

async function onExport(scope: string) {
  const params: Record<string, any> = {};
  if (scope === "filter") {
    if (query.search) params.search = query.search;
    if (query.status) params.status = query.status;
    if (query.type) params.type = query.type;
  }
  if (scope === "page") Object.assign(params, { page: query.page, pageSize: query.pageSize });
  const res = await exportCards(params);
  const url = URL.createObjectURL(new Blob([res]));
  const a = document.createElement("a");
  a.href = url;
  a.download = "licenses.csv";
  a.click();
  URL.revokeObjectURL(url);
}

onMounted(() => {
  load();
  loadStats();
});
</script>

<template>
  <div>
    <el-row :gutter="16">
      <el-col v-for="c in statCards" :key="c.label" :span="6">
        <el-card class="mb-4 text-center">
          <div class="text-sm text-gray-500">{{ c.label }}</div>
          <div class="mt-2 text-2xl font-bold">{{ c.value }}</div>
        </el-card>
      </el-col>
    </el-row>

    <div class="mb-4 flex flex-wrap gap-3">
      <el-input v-model="query.search" placeholder="搜索激活码" clearable class="w-56" @input="query.page = 1; load()" />
      <el-select v-model="query.status" placeholder="状态" clearable class="w-36" @change="query.page = 1; load()">
        <el-option label="未激活" value="unused" />
        <el-option label="已激活" value="activated" />
        <el-option label="已吊销" value="revoked" />
      </el-select>
      <el-select v-model="query.type" placeholder="类型" clearable class="w-36" @change="query.page = 1; load()">
        <el-option label="免费版" value="free" />
        <el-option label="永久版" value="perpetual" />
      </el-select>
      <el-button type="primary" @click="genVisible = true">生成卡密</el-button>
      <el-dropdown @command="onExport">
        <el-button>导出 CSV</el-button>
        <template #dropdown>
          <el-dropdown-menu>
            <el-dropdown-item command="all">全部</el-dropdown-item>
            <el-dropdown-item command="filter">当前筛选</el-dropdown-item>
            <el-dropdown-item command="page">当前页</el-dropdown-item>
          </el-dropdown-menu>
        </template>
      </el-dropdown>
    </div>

    <el-table v-loading="loading" :data="list" border>
      <el-table-column prop="formatted" label="激活码" width="220" />
      <el-table-column label="类型" width="90">
        <template #default="{ row }">{{ typeMap[row.type] }}</template>
      </el-table-column>
      <el-table-column prop="max_devices" label="设备数" width="80" />
      <el-table-column label="状态" width="90">
        <template #default="{ row }"><el-tag :type="statusTag[row.status]">{{ statusMap[row.status] }}</el-tag></template>
      </el-table-column>
      <el-table-column prop="bound_count" label="已绑设备" width="90" />
      <el-table-column prop="created_at" label="创建时间" width="170" />
      <el-table-column label="操作" fixed="right" width="180">
        <template #default="{ row }">
          <el-button size="small" @click="onDetail(row.code)">详情</el-button>
          <el-button v-if="row.status !== 'revoked'" size="small" type="danger" @click="onRevoke(row)">吊销</el-button>
          <el-button v-else size="small" type="success" @click="onRestore(row)">恢复</el-button>
        </template>
      </el-table-column>
    </el-table>

    <el-pagination
      class="mt-4 justify-end"
      :current-page="query.page"
      :page-size="query.pageSize"
      :total="total"
      :page-sizes="[5, 10, 20, 50]"
      layout="total, sizes, prev, pager, next"
      @current-change="p => { query.page = p; load(); }"
      @size-change="s => { query.pageSize = s; query.page = 1; load(); }"
    />

    <el-dialog v-model="genVisible" title="生成卡密" width="480">
      <el-form label-width="90px">
        <el-form-item label="类型">
          <el-radio-group v-model="gen.type">
            <el-radio value="perpetual">永久版</el-radio>
            <el-radio value="free">免费版</el-radio>
          </el-radio-group>
        </el-form-item>
        <el-form-item label="数量"><el-input-number v-model="gen.count" :min="1" :max="1000" /></el-form-item>
        <el-form-item label="设备数"><el-input-number v-model="gen.devices" :min="1" :max="100" /></el-form-item>
        <el-form-item label="过期天数"><el-input-number v-model="gen.expire_days" :min="0" :max="3650" /></el-form-item>
      </el-form>
      <template #footer>
        <el-button @click="genVisible = false">取消</el-button>
        <el-button type="primary" :loading="genLoading" @click="onGenerate">生成</el-button>
      </template>
    </el-dialog>

    <el-dialog v-model="resultVisible" title="生成的激活码" width="480">
      <el-input :model-value="resultCodes.join('\n')" type="textarea" :rows="10" readonly />
      <template #footer>
        <el-button @click="onCopy">复制全部</el-button>
        <el-button type="primary" @click="resultVisible = false">关闭</el-button>
      </template>
    </el-dialog>

    <el-dialog v-model="detailVisible" title="卡密详情" width="600">
      <el-descriptions v-if="detail" :column="2" border>
        <el-descriptions-item label="激活码">{{ detail.license.formatted }}</el-descriptions-item>
        <el-descriptions-item label="类型">{{ typeMap[detail.license.type] }}</el-descriptions-item>
        <el-descriptions-item label="设备数">{{ detail.license.max_devices }}</el-descriptions-item>
        <el-descriptions-item label="状态">{{ statusMap[detail.license.status] }}</el-descriptions-item>
      </el-descriptions>
      <h4 class="mt-4 mb-2">绑定设备</h4>
      <el-table :data="detail.devices" size="small" border>
        <el-table-column prop="device_name" label="设备名" />
        <el-table-column prop="device_fp" label="设备指纹" width="180" show-overflow-tooltip />
        <el-table-column prop="last_seen" label="最近在线" width="170" />
      </el-table>
    </el-dialog>
  </div>
</template>
