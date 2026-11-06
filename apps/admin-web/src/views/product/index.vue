<script setup lang="ts">
import { onMounted, reactive, ref } from "vue";
import { ElMessage } from "element-plus";
import { createProduct, getProducts, updateProduct } from "@/api/product";

const loading = ref(false);
const saving = ref(false);
const list = ref<any[]>([]);
const visible = ref(false);
const isEdit = ref(false);

const emptyForm = () => ({
  id: undefined as number | undefined,
  code: "",
  name: "",
  trial_days: 14,
  default_max_devices: 1,
  purchase_url: "",
  support_email: "huoyongzhuang@qq.com",
  status: 1,
  card_count: 0
});

const form = reactive(emptyForm());

async function load() {
  loading.value = true;
  try {
    const res: any = await getProducts();
    list.value = res.data.list || [];
  } finally {
    loading.value = false;
  }
}

function openCreate() {
  Object.assign(form, emptyForm());
  isEdit.value = false;
  visible.value = true;
}

function openEdit(row: any) {
  Object.assign(form, emptyForm(), row);
  isEdit.value = true;
  visible.value = true;
}

async function save() {
  if (!form.name.trim()) {
    ElMessage.warning("请填写产品名称");
    return;
  }
  if (!/^[a-z0-9][a-z0-9_-]{1,31}$/.test(form.code.trim())) {
    ElMessage.warning("产品编码只能是小写字母/数字/-/_，长度 2-32");
    return;
  }
  saving.value = true;
  try {
    const payload = {
      id: form.id,
      code: form.code.trim(),
      name: form.name.trim(),
      trial_days: form.trial_days,
      default_max_devices: form.default_max_devices,
      purchase_url: form.purchase_url.trim(),
      support_email: form.support_email.trim(),
      status: form.status
    };
    if (isEdit.value) {
      await updateProduct(payload);
      ElMessage.success("已保存");
    } else {
      await createProduct(payload);
      ElMessage.success("已新增");
    }
    visible.value = false;
    await load();
  } finally {
    saving.value = false;
  }
}

onMounted(load);
</script>

<template>
  <div>
    <div class="mb-4 flex items-center justify-between">
      <div class="text-lg font-bold">产品管理</div>
      <el-button type="primary" @click="openCreate">新增产品</el-button>
    </div>

    <el-table v-loading="loading" :data="list" border>
      <el-table-column prop="name" label="产品名" width="140" />
      <el-table-column prop="code" label="产品编码" width="140" />
      <el-table-column prop="trial_days" label="试用天数" width="100" />
      <el-table-column prop="default_max_devices" label="默认设备数" width="110" />
      <el-table-column prop="support_email" label="支持邮箱" min-width="200" show-overflow-tooltip />
      <el-table-column prop="purchase_url" label="购买链接" min-width="220" show-overflow-tooltip />
      <el-table-column prop="card_count" label="卡密数" width="90" />
      <el-table-column label="状态" width="90">
        <template #default="{ row }">
          <el-tag :type="row.status ? 'success' : 'info'">
            {{ row.status ? "启用" : "停用" }}
          </el-tag>
        </template>
      </el-table-column>
      <el-table-column label="操作" width="100" fixed="right">
        <template #default="{ row }">
          <el-button size="small" @click="openEdit(row)">编辑</el-button>
        </template>
      </el-table-column>
    </el-table>

    <el-dialog v-model="visible" :title="isEdit ? '编辑产品' : '新增产品'" width="520">
      <el-form label-width="110px">
        <el-form-item label="产品名称">
          <el-input v-model="form.name" placeholder="如 Downie6 / launch" />
        </el-form-item>
        <el-form-item label="产品编码">
          <el-input
            v-model="form.code"
            placeholder="小写字母/数字/-/_，如 launch"
            :disabled="isEdit && form.card_count > 0"
          />
          <div v-if="isEdit && form.card_count > 0" class="text-xs text-gray-400">
            已有卡密，编码不可修改
          </div>
        </el-form-item>
        <el-form-item label="试用天数">
          <el-input-number v-model="form.trial_days" :min="1" :max="365" />
        </el-form-item>
        <el-form-item label="默认设备数">
          <el-input-number v-model="form.default_max_devices" :min="1" :max="100" />
        </el-form-item>
        <el-form-item label="支持邮箱">
          <el-input v-model="form.support_email" placeholder="huoyongzhuang@qq.com" />
        </el-form-item>
        <el-form-item label="购买链接">
          <el-input v-model="form.purchase_url" placeholder="可留空" />
        </el-form-item>
        <el-form-item label="状态">
          <el-switch v-model="form.status" :active-value="1" :inactive-value="0" />
        </el-form-item>
      </el-form>
      <template #footer>
        <el-button @click="visible = false">取消</el-button>
        <el-button type="primary" :loading="saving" @click="save">保存</el-button>
      </template>
    </el-dialog>
  </div>
</template>
