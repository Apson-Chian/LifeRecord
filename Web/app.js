const API_BASE = "/liferecord-api";
const LEGACY_STORAGE_KEY = "liferecord.web.v1";
const UI_DATE_KEY = "liferecord.selected-date";
const commonWater = [200, 250, 330, 500, 750];
const symbols = { 早餐: "☀", 午餐: "◐", 晚餐: "☾", 加餐: "◇" };
const defaultSettings = {
  id: "profile", displayName: "", fitnessGoal: "增肌", height: 181, baselineWeight: 64,
  targetWeight: 72, weeklyWeightTarget: .25, calorieGoal: 2600, proteinGoal: 130,
  carbsGoal: 340, fatGoal: 70, waterGoal: 2800
};

const $ = selector => document.querySelector(selector);
const pad = value => String(value).padStart(2, "0");
const dateKey = date => `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}`;
const parseDate = value => { const [y, m, d] = value.split("-").map(Number); return new Date(y, m - 1, d, 12); };
const epochForDateKey = value => parseDate(value).getTime() / 1000;
const recordDateKey = item => dateKey(new Date(item.date * 1000));
const nowSeconds = () => Date.now() / 1000;
const newID = () => crypto.randomUUID().toLowerCase();
const fmtDate = date => new Intl.DateTimeFormat("zh-CN", { year: "numeric", month: "long", day: "numeric", weekday: "short" }).format(date);
const fmtShortDate = seconds => new Intl.DateTimeFormat("zh-CN", { month: "short", day: "numeric", hour: "2-digit", minute: "2-digit" }).format(new Date(seconds * 1000));
const fmtMealDate = seconds => new Intl.DateTimeFormat("zh-CN", { year: "numeric", month: "short", day: "numeric" }).format(new Date(seconds * 1000));
const fmtSyncTime = () => new Intl.DateTimeFormat("zh-CN", { hour: "2-digit", minute: "2-digit" }).format(new Date());
const progress = (value, goal) => Math.min(Math.max(value / Math.max(goal, 1), 0), 1);

let state = { meals: [], bodyMetrics: [], waterEntries: [], settings: null, deletions: [], serverTime: null };
let selectedDate = localStorage.getItem(UI_DATE_KEY) || dateKey(new Date());
let visibleMonth = parseDate(selectedDate);
let connected = false;
let localRevision = 0;
let syncInFlight = false;
let syncAgain = false;

function touchLocalState() { localRevision += 1; }

function goals() { return state.settings || defaultSettings; }
function selectedMeals() { return state.meals.filter(item => recordDateKey(item) === selectedDate); }
function selectedWaterEntries() { return state.waterEntries.filter(item => recordDateKey(item) === selectedDate); }
function selectedWater() { return selectedWaterEntries().reduce((sum, item) => sum + item.milliliters, 0); }
function totals() {
  return selectedMeals().reduce((sum, item) => ({ calories: sum.calories + item.calories, protein: sum.protein + item.protein, carbs: sum.carbs + item.carbs, fat: sum.fat + item.fat }), { calories: 0, protein: 0, carbs: 0, fat: 0 });
}

function setSyncStatus(text, kind = "") {
  const node = $("#syncStatus");
  node.className = `sync-pill ${kind}`.trim();
  node.innerHTML = `<i></i>${text}`;
  node.title = kind === "synced" ? `最近同步：${new Date().toLocaleString("zh-CN")}` : text;
}

async function api(path, options = {}) {
  const response = await fetch(`${API_BASE}${path}`, {
    credentials: "same-origin",
    headers: { "Content-Type": "application/json", ...(options.headers || {}) },
    ...options
  });
  if (response.status === 401 && path !== "/auth") {
    connected = false;
    showAuth();
    throw new Error("需要同步密钥");
  }
  if (!response.ok) {
    let message = `服务器错误 ${response.status}`;
    try { message = (await response.json()).error || message; } catch (_) {}
    throw new Error(message);
  }
  return response.status === 204 ? null : response.json();
}

async function boot() {
  setSyncStatus("正在连接");
  try {
    state = await api("/snapshot");
    connected = true;
    await migrateLegacyIfNeeded();
    render();
    setSyncStatus(`已同步 · ${fmtSyncTime()}`, "synced");
  } catch (error) {
    if (error.message !== "需要同步密钥") setSyncStatus("连接失败", "error");
  }
}

function showAuth() {
  const dialog = $("#authDialog");
  if (!dialog.open) dialog.showModal();
}

async function syncNow(message = "已同步", silent = false) {
  if (!connected) return showAuth();
  if (syncInFlight) { syncAgain = true; return false; }
  syncInFlight = true;
  const revisionAtStart = localRevision;
  setSyncStatus("正在同步");
  try {
    const inbound = await api("/sync", { method: "POST", body: JSON.stringify(state) });
    if (revisionAtStart === localRevision) {
      state = inbound;
      render();
    } else {
      syncAgain = true;
    }
    setSyncStatus(`${message} · ${fmtSyncTime()}`, "synced");
    return true;
  } catch (error) {
    setSyncStatus("同步失败", "error");
    if (!silent) showToast(error.message);
    return false;
  } finally {
    syncInFlight = false;
    if (syncAgain) {
      syncAgain = false;
      setTimeout(() => syncNow("已自动同步", true), 0);
    }
  }
}

async function migrateLegacyIfNeeded() {
  const raw = localStorage.getItem(LEGACY_STORAGE_KEY);
  if (!raw || state.meals.length || state.waterEntries.length || state.bodyMetrics.length) return;
  try {
    const legacy = JSON.parse(raw);
    const timestamp = nowSeconds();
    state.meals = (legacy.meals || []).map((item, index) => ({
      id: String(item.id || newID()).toLowerCase(), date: epochForDateKey(item.date), kind: item.kind || "加餐",
      name: item.name || "迁移餐食", calories: Number(item.calories || 0), protein: Number(item.protein || 0),
      carbs: Number(item.carbs || 0), fat: Number(item.fat || 0), fiber: 0, note: "从旧版网页迁移",
      source: "手动", createdAt: timestamp - index, updatedAt: timestamp - index
    }));
    state.waterEntries = (legacy.water || []).map((item, index) => ({
      id: String(item.id || newID()).toLowerCase(), date: epochForDateKey(item.date), milliliters: Number(item.amount || 0),
      note: "从旧版网页迁移", updatedAt: timestamp - index
    })).filter(item => item.milliliters > 0);
    touchLocalState();
    if (await syncNow("旧版数据已迁移")) localStorage.removeItem(LEGACY_STORAGE_KEY);
  } catch (_) {}
}

function render() {
  const date = parseDate(selectedDate);
  const meals = selectedMeals();
  const nutrition = totals();
  const water = selectedWater();
  const target = goals();
  $("#dateLabel").textContent = fmtDate(date);
  $("#toolbarDateLabel").textContent = relativeDateLabel(date);
  $("#mealTitle").textContent = selectedDate === dateKey(new Date()) ? "今天吃了什么" : `${date.getMonth() + 1} 月 ${date.getDate()} 日记录`;
  $("#mealSummary").textContent = `${meals.length} 餐 · ${Math.round(nutrition.calories)} kcal`;
  $("#waterTotal").textContent = (water / 1000).toFixed(1);
  renderOverview(nutrition, water, target);
  renderMealPreview(meals);
  renderWeekRings();
}

function relativeDateLabel(date) {
  const today = parseDate(dateKey(new Date()));
  const days = Math.round((date - today) / 86400000);
  if (days === 0) return "今天";
  if (days === -1) return "昨天";
  if (days === 1) return "明天";
  return `${date.getMonth() + 1} 月 ${date.getDate()} 日`;
}

function renderOverview(nutrition, water, target) {
  const calorieProgress = progress(nutrition.calories, target.calorieGoal);
  const proteinProgress = progress(nutrition.protein, target.proteinGoal);
  const waterProgress = progress(water, target.waterGoal);
  $("#overviewCalories").textContent = `${Math.round(nutrition.calories)} kcal`;
  $("#overviewCaloriesDetail").textContent = `目标 ${Math.round(target.calorieGoal)} kcal`;
  $("#overviewProtein").textContent = `${Math.round(proteinProgress * 100)}%`;
  $("#overviewProteinDetail").textContent = `${Math.round(nutrition.protein)} / ${Math.round(target.proteinGoal)} g`;
  $("#overviewWater").textContent = `${Math.round(waterProgress * 100)}%`;
  $("#overviewWaterDetail").textContent = `${Math.round(water)} / ${Math.round(target.waterGoal)} ml`;
  $("#overviewCaloriesBar").style.width = `${calorieProgress * 100}%`;
  $("#overviewProteinBar").style.width = `${proteinProgress * 100}%`;
  $("#overviewWaterBar").style.width = `${waterProgress * 100}%`;

  const endOfSelectedDay = epochForDateKey(selectedDate) + 86400;
  const metric = [...state.bodyMetrics].filter(item => item.date < endOfSelectedDay).sort((a, b) => b.date - a.date)[0];
  $("#overviewWeight").textContent = metric ? `${Number(metric.weight).toFixed(1)} kg` : "--";
  $("#overviewWeightDetail").textContent = metric ? `${fmtMealDate(metric.date)}${metric.bodyFat ? ` · 体脂 ${Number(metric.bodyFat).toFixed(1)}%` : ""}` : "暂无身体记录";
}

function renderWeekRings() {
  const selected = parseDate(selectedDate);
  const mondayOffset = (selected.getDay() + 6) % 7;
  const monday = new Date(selected);
  monday.setDate(selected.getDate() - mondayOffset);
  const target = goals();
  const labels = ["一", "二", "三", "四", "五", "六", "日"];
  const html = [];
  for (let index = 0; index < 7; index++) {
    const date = new Date(monday); date.setDate(monday.getDate() + index);
    const key = dateKey(date);
    const meals = state.meals.filter(item => recordDateKey(item) === key);
    const protein = meals.reduce((sum, item) => sum + Number(item.protein || 0), 0);
    const carbs = meals.reduce((sum, item) => sum + Number(item.carbs || 0), 0);
    const hasRecord = recordedDates().has(key);
    html.push(`<button class="week-day ${key === selectedDate ? "selected" : ""} ${hasRecord ? "recorded" : ""}" type="button" data-week-date="${key}" aria-label="${fmtDate(date)}${hasRecord ? "，已有记录" : ""}">
      <span>${labels[index]}</span>
      <i class="mini-rings" aria-hidden="true">
        <i class="mini-ring mini-protein" style="--progress:${progress(protein, target.proteinGoal)}"></i>
        <i class="mini-ring mini-carbs" style="--progress:${progress(carbs, target.carbsGoal)}"></i>
        <i class="mini-ring mini-meals" style="--progress:${progress(meals.length, 4)}"></i>
        <b class="mini-day-number">${date.getDate()}</b>
      </i>
    </button>`);
  }
  $("#weekRings").innerHTML = html.join("");
}

function renderMealPreview(meals) {
  const list = $("#mealPreview");
  if (!meals.length) {
    list.innerHTML = `<div class="empty">这一天还没有餐食记录，点“记一餐”开始。</div>`;
    return;
  }
  list.innerHTML = [...meals].sort((a, b) => b.date - a.date).slice(0, 4).map(item => {
    const photoIDs = Array.isArray(item.photoIDs) ? item.photoIDs.filter(id => /^[a-f0-9]{32}$/.test(id)) : [];
    return `
    <button class="meal-item" type="button" data-show-meal="${item.id}">
      <span class="meal-symbol" aria-hidden="true">${symbols[item.kind] || "◇"}</span>
      <span class="meal-copy"><strong>${escapeHtml(item.name)}</strong><small>${item.kind} · 蛋白 ${Math.round(item.protein)}g · 碳水 ${Math.round(item.carbs)}g${photoIDs.length ? ` · ${photoIDs.length} 张照片` : ""}</small></span>
      <span class="meal-kcal"><strong>${Math.round(item.calories)}</strong><span>kcal · 详情 ›</span></span>
    </button>`;
  }).join("");
}

function escapeHtml(value) { const node = document.createElement("span"); node.textContent = String(value); return node.innerHTML; }
function showToast(message) { const toast = $("#toast"); toast.textContent = message; toast.classList.add("show"); clearTimeout(showToast.timer); showToast.timer = setTimeout(() => toast.classList.remove("show"), 1700); }
function renderWaterOptions() { $("#waterOptions").innerHTML = commonWater.map(amount => `<button type="button" data-water="${amount}">+${amount} ml</button>`).join(""); }

function blobBase64(blob) {
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = () => resolve(String(reader.result).split(",")[1]);
    reader.onerror = () => reject(new Error("照片读取失败"));
    reader.readAsDataURL(blob);
  });
}

async function preparedImageBase64(file) {
  try {
    const bitmap = await createImageBitmap(file);
    const scale = Math.min(1, 1600 / Math.max(bitmap.width, bitmap.height));
    const canvas = document.createElement("canvas");
    canvas.width = Math.max(1, Math.round(bitmap.width * scale));
    canvas.height = Math.max(1, Math.round(bitmap.height * scale));
    canvas.getContext("2d", { alpha: false }).drawImage(bitmap, 0, 0, canvas.width, canvas.height);
    bitmap.close();
    const blob = await new Promise(resolve => canvas.toBlob(resolve, "image/jpeg", .82));
    if (!blob) throw new Error("照片压缩失败");
    return blobBase64(blob);
  } catch (error) {
    if (file.size <= 4 * 1024 * 1024 && ["image/jpeg", "image/png", "image/webp"].includes(file.type)) return blobBase64(file);
    throw error;
  }
}

async function uploadMealPhotos(mealId, files) {
  const imageIDs = [];
  for (const file of files.slice(0, 6)) {
    const base64 = await preparedImageBase64(file);
    const result = await api("/images", { method: "POST", body: JSON.stringify({ mealId, base64 }) });
    imageIDs.push(result.id);
  }
  return imageIDs;
}

function recordSource(item, kind) {
  if (kind === "meal") return item.source === "AI 估算" ? "AI 估算并记录" : "手动记录";
  const note = String(item.note || "");
  if (note.includes("AI")) return "AI 自动记录";
  if (note.includes("网页")) return "网页版记录";
  return "手动记录";
}

function openDetail({ eyebrow = "数据明细", title, subtitle = "", html }) {
  $("#detailEyebrow").textContent = eyebrow;
  $("#detailTitle").textContent = title;
  $("#detailSubtitle").textContent = subtitle;
  $("#detailContent").innerHTML = html;
  const dialog = $("#detailDialog");
  if (!dialog.open) dialog.showModal();
}

function emptyDetail(message) {
  return `<div class="empty">${escapeHtml(message)}</div>`;
}

function mealSourceRows(meals, key, unit) {
  if (!meals.length) return emptyDetail("所选日期没有相关餐食来源。");
  return `<div class="source-list">${[...meals].sort((a, b) => b.date - a.date).map(item => `
    <button class="source-row" type="button" data-show-meal="${item.id}">
      <span><strong>${escapeHtml(item.name)}</strong><small>${fmtShortDate(item.date)} · ${escapeHtml(recordSource(item, "meal"))}</small></span>
      <b>${Math.round(Number(item[key] || 0))} ${unit}<small>查看餐食 ›</small></b>
    </button>`).join("")}</div>`;
}

function showColumnDetail(type) {
  const meals = selectedMeals();
  const target = goals();
  const nutrition = totals();
  const date = fmtDate(parseDate(selectedDate));
  if (type === "calories") {
    openDetail({ title: "热量来源", subtitle: `${date} · 共 ${Math.round(nutrition.calories)} / ${Math.round(target.calorieGoal)} kcal`, html: mealSourceRows(meals, "calories", "kcal") });
  } else if (type === "protein") {
    openDetail({ title: "蛋白质来源", subtitle: `${date} · 共 ${Math.round(nutrition.protein)} / ${Math.round(target.proteinGoal)} g`, html: mealSourceRows(meals, "protein", "g") });
  } else if (type === "water") {
    const entries = [...selectedWaterEntries()].sort((a, b) => b.date - a.date);
    const total = entries.reduce((sum, item) => sum + Number(item.milliliters || 0), 0);
    const html = entries.length ? `<div class="source-list">${entries.map(item => `
      <div class="source-row">
        <span><strong>${escapeHtml(item.note || "饮水记录")}</strong><small>${fmtShortDate(item.date)} · ${escapeHtml(recordSource(item, "water"))}</small></span>
        <b>${Math.round(item.milliliters)} ml<button class="delete-record" type="button" data-delete-water="${item.id}" aria-label="删除这条饮水记录">删除</button></b>
      </div>`).join("")}</div>` : emptyDetail("所选日期还没有饮水记录。");
    openDetail({ title: "饮水来源", subtitle: `${date} · ${Math.round(total)} / ${Math.round(target.waterGoal)} ml`, html: `<p class="calculation-note">计算方式：当天所有饮水记录的毫升数直接相加。AI 只会为明确饮用的饮料新增来源，不计算菜肴、米饭、蔬果本身的水分。</p>${html}` });
  } else if (type === "weight") {
    const end = epochForDateKey(selectedDate) + 86400;
    const entries = [...state.bodyMetrics].filter(item => item.date < end).sort((a, b) => b.date - a.date).slice(0, 20);
    const html = entries.length ? `<div class="source-list">${entries.map(item => `
      <div class="source-row">
        <span><strong>${Number(item.weight).toFixed(1)} kg${item.bodyFat ? ` · 体脂 ${Number(item.bodyFat).toFixed(1)}%` : ""}</strong><small>${fmtShortDate(item.date)} · ${escapeHtml(recordSource(item, "body"))}${item.note ? ` · ${escapeHtml(item.note)}` : ""}</small></span>
        <b><button class="delete-record" type="button" data-delete-body="${item.id}" aria-label="删除这条身体记录">删除</button></b>
      </div>`).join("")}</div>` : emptyDetail("这一天之前还没有身体记录。");
    openDetail({ title: "体重记录", subtitle: `截至 ${date} 的最近记录`, html });
  } else if (type === "meals") {
    openDetail({ title: "饮食记录", subtitle: `${date} · ${meals.length} 餐`, html: mealSourceRows(meals, "calories", "kcal") });
  }
}

function showMealDetail(meal) {
  const photoIDs = Array.isArray(meal.photoIDs) ? meal.photoIDs.filter(id => /^[a-f0-9]{32}$/.test(id)) : [];
  const photos = photoIDs.length ? `<section class="detail-photos"><h3>餐食照片 <small>${photoIDs.length} 张</small></h3><div class="photo-gallery">${photoIDs.map((id, index) => `<img loading="lazy" src="${API_BASE}/images/${id}" alt="${escapeHtml(meal.name)}照片 ${index + 1}">`).join("")}</div></section>` : "";
  openDetail({
    eyebrow: `${meal.kind} · ${recordSource(meal, "meal")}`,
    title: meal.name,
    subtitle: fmtShortDate(meal.date),
    html: `<div class="detail-kpis"><div><span>热量</span><strong>${Math.round(meal.calories)} kcal</strong></div><div><span>蛋白质</span><strong>${Math.round(meal.protein)} g</strong></div><div><span>碳水</span><strong>${Math.round(meal.carbs)} g</strong></div><div><span>脂肪</span><strong>${Math.round(meal.fat)} g</strong></div></div>${meal.note ? `<section class="detail-note"><h3>记录说明</h3><p>${escapeHtml(meal.note)}</p></section>` : ""}<div class="detail-actions"><button class="delete-record" type="button" data-delete-meal="${meal.id}">删除这条记录</button></div>${photos}`
  });
}

function addDeletion(id, recordType) {
  state.deletions = state.deletions.filter(item => !(item.id === id && item.recordType === recordType));
  state.deletions.push({ id, recordType, deletedAt: nowSeconds() });
  touchLocalState();
}

function recordedDates() {
  return new Set([...state.meals, ...state.waterEntries, ...state.bodyMetrics].map(recordDateKey));
}

function renderCalendar() {
  const year = visibleMonth.getFullYear();
  const month = visibleMonth.getMonth();
  $("#monthLabel").textContent = `${year} 年 ${month + 1} 月`;
  const first = new Date(year, month, 1);
  const leading = (first.getDay() + 6) % 7;
  const count = new Date(year, month + 1, 0).getDate();
  const recorded = recordedDates();
  const cells = Array.from({ length: leading }, () => `<span></span>`);
  for (let day = 1; day <= count; day++) {
    const date = new Date(year, month, day);
    const key = dateKey(date);
    const classes = ["calendar-day", key === selectedDate ? "selected" : "", key === dateKey(new Date()) ? "today" : "", recorded.has(key) ? "recorded" : ""].filter(Boolean).join(" ");
    cells.push(`<button type="button" class="${classes}" data-date="${key}" aria-label="${fmtDate(date)}${recorded.has(key) ? "，已有记录" : ""}">${day}</button>`);
  }
  $("#calendarGrid").innerHTML = cells.join("");
}

function selectDate(value) {
  selectedDate = value;
  localStorage.setItem(UI_DATE_KEY, selectedDate);
  render();
}

function moveSelectedDate(days) {
  const date = parseDate(selectedDate);
  date.setDate(date.getDate() + days);
  selectDate(dateKey(date));
}

function openMealDialog() { $("#mealDialog").showModal(); }
function openWeightDialog() { $("#weightDialog").showModal(); }

renderWaterOptions();
boot();

$("#authForm").addEventListener("submit", async event => {
  event.preventDefault();
  const token = new FormData(event.currentTarget).get("token").trim();
  $("#authError").textContent = "";
  try {
    await api("/auth", { method: "POST", body: JSON.stringify({ token }) });
    connected = true;
    $("#authDialog").close();
    event.currentTarget.reset();
    await boot();
  } catch (error) {
    $("#authError").textContent = error.message;
  }
});

$("#waterOptions").addEventListener("click", async event => {
  const button = event.target.closest("[data-water]"); if (!button) return;
  const amount = Number(button.dataset.water);
  state.waterEntries.push({ id: newID(), date: epochForDateKey(selectedDate), milliliters: amount, note: "网页版快速记录", updatedAt: nowSeconds() });
  touchLocalState();
  render(); await syncNow(); showToast(`已记录 ${amount} ml 饮水`);
});

$("#mealPreview").addEventListener("click", event => {
  const button = event.target.closest("[data-show-meal]"); if (!button) return;
  const meal = state.meals.find(item => item.id === button.dataset.showMeal);
  if (meal) showMealDetail(meal);
});

document.addEventListener("click", event => {
  const button = event.target.closest("[data-open-detail]");
  if (button) showColumnDetail(button.dataset.openDetail);
});

$("#detailContent").addEventListener("click", async event => {
  const mealLink = event.target.closest("[data-show-meal]");
  if (mealLink) {
    const meal = state.meals.find(item => item.id === mealLink.dataset.showMeal);
    if (meal) showMealDetail(meal);
    return;
  }
  const mealButton = event.target.closest("[data-delete-meal]");
  const bodyButton = event.target.closest("[data-delete-body]");
  const waterButton = event.target.closest("[data-delete-water]");
  if (mealButton) {
    addDeletion(mealButton.dataset.deleteMeal, "meal");
    state.meals = state.meals.filter(item => item.id !== mealButton.dataset.deleteMeal);
    showToast("已删除餐食记录");
  } else if (bodyButton) {
    addDeletion(bodyButton.dataset.deleteBody, "body");
    state.bodyMetrics = state.bodyMetrics.filter(item => item.id !== bodyButton.dataset.deleteBody);
    showToast("已删除身体记录");
  } else if (waterButton) {
    addDeletion(waterButton.dataset.deleteWater, "water");
    state.waterEntries = state.waterEntries.filter(item => item.id !== waterButton.dataset.deleteWater);
    showToast("已删除饮水记录");
  } else {
    return;
  }
  $("#detailDialog").close();
  render();
  await syncNow();
});

$("#dateButton").addEventListener("click", () => { visibleMonth = parseDate(selectedDate); renderCalendar(); $("#calendarDialog").showModal(); });
$("#prevMonth").addEventListener("click", () => { visibleMonth = new Date(visibleMonth.getFullYear(), visibleMonth.getMonth() - 1, 1); renderCalendar(); });
$("#nextMonth").addEventListener("click", () => { visibleMonth = new Date(visibleMonth.getFullYear(), visibleMonth.getMonth() + 1, 1); renderCalendar(); });
$("#calendarGrid").addEventListener("click", event => {
  const button = event.target.closest("[data-date]"); if (!button) return;
  selectDate(button.dataset.date); $("#calendarDialog").close();
});
$("#weekRings").addEventListener("click", event => {
  const button = event.target.closest("[data-week-date]"); if (!button) return;
  selectDate(button.dataset.weekDate);
});

$("#previousDayButton").addEventListener("click", () => moveSelectedDate(-1));
$("#nextDayButton").addEventListener("click", () => moveSelectedDate(1));
$("#todayButton").addEventListener("click", () => selectDate(dateKey(new Date())));
$("#syncButton").addEventListener("click", async () => {
  if (await syncNow("已手动同步")) showToast("手机与电脑数据已同步");
});
$("#searchMealButton").addEventListener("click", () => showColumnDetail("meals"));
$("#showMealsButton").addEventListener("click", () => showColumnDetail("meals"));

$("#addMealButton").addEventListener("click", openMealDialog);
$("#quickMealButton").addEventListener("click", openMealDialog);
$("#closeMeal").addEventListener("click", () => $("#mealDialog").close());
$("#mealForm").addEventListener("submit", async event => {
  event.preventDefault();
  const form = event.currentTarget; const data = new FormData(form); const timestamp = nowSeconds(); const id = newID();
  const submit = form.querySelector('[type="submit"]'); const originalLabel = submit.textContent;
  submit.disabled = true; submit.textContent = "正在保存照片…";
  try {
    const files = Array.from(form.elements.photos.files || []);
    if (files.length > 6) throw new Error("一次最多保存 6 张照片");
    const photoIDs = await uploadMealPhotos(id, files);
    state.meals.push({
      id, date: epochForDateKey(selectedDate), kind: data.get("kind"), name: data.get("name").trim(),
      calories: Number(data.get("calories")), protein: Number(data.get("protein")), carbs: Number(data.get("carbs")),
      fat: Number(data.get("fat")), fiber: 0, note: "网页版记录", source: "手动", createdAt: timestamp, updatedAt: timestamp, photoIDs
    });
    touchLocalState();
    render(); form.reset(); $("#mealDialog").close(); await syncNow(); showToast("餐食与照片已保存");
  } catch (error) {
    showToast(error.message || "照片保存失败");
  } finally {
    submit.disabled = false; submit.textContent = originalLabel;
  }
});

$("#addWeightButton").addEventListener("click", openWeightDialog);
$("#quickWeightButton").addEventListener("click", openWeightDialog);
$("#closeWeight").addEventListener("click", () => $("#weightDialog").close());
$("#weightForm").addEventListener("submit", async event => {
  event.preventDefault(); const data = new FormData(event.currentTarget); const bodyFat = Number(data.get("bodyFat"));
  state.bodyMetrics.push({ id: newID(), date: epochForDateKey(selectedDate), weight: Number(data.get("weight")), bodyFat: bodyFat || null, waist: null, note: data.get("note").trim(), updatedAt: nowSeconds() });
  touchLocalState();
  render(); event.currentTarget.reset(); $("#weightDialog").close(); await syncNow(); showToast("身体数据已保存");
});

$("#editGoalsButton").addEventListener("click", () => {
  const target = goals(); const form = $("#goalsForm");
  for (const key of ["calorieGoal", "proteinGoal", "carbsGoal", "fatGoal", "waterGoal", "targetWeight"]) form.elements[key].value = target[key];
  $("#goalsDialog").showModal();
});
$("#closeGoals").addEventListener("click", () => $("#goalsDialog").close());
$("#goalsForm").addEventListener("submit", async event => {
  event.preventDefault(); const data = new FormData(event.currentTarget); const base = goals();
  state.settings = { ...base, id: "profile", updatedAt: nowSeconds() };
  for (const key of ["calorieGoal", "proteinGoal", "carbsGoal", "fatGoal", "waterGoal", "targetWeight"]) state.settings[key] = Number(data.get(key));
  touchLocalState();
  render(); $("#goalsDialog").close(); await syncNow(); showToast("目标已同步到 App");
});

$("#exportButton").addEventListener("click", () => {
  const blob = new Blob([JSON.stringify({ exportedAt: new Date().toISOString(), ...state }, null, 2)], { type: "application/json" });
  const url = URL.createObjectURL(blob); const link = document.createElement("a");
  link.href = url; link.download = `LifeRecord-${dateKey(new Date())}.json`; link.click(); URL.revokeObjectURL(url);
});

$("#changeKeyButton").addEventListener("click", async () => {
  try { await api("/logout", { method: "POST", body: JSON.stringify({ action: "logout" }) }); } catch (_) {}
  connected = false;
  setSyncStatus("等待连接");
  showAuth();
});

$("#closeDetail").addEventListener("click", () => $("#detailDialog").close());

document.addEventListener("keydown", event => {
  if (event.metaKey || event.ctrlKey || event.altKey || document.querySelector("dialog[open]")) return;
  const tag = event.target.tagName;
  const isEditing = tag === "INPUT" || tag === "TEXTAREA" || tag === "SELECT" || event.target.isContentEditable;
  if (event.key === "/" && !isEditing) {
    event.preventDefault();
    showColumnDetail("meals");
  } else if (!isEditing && event.key.toLowerCase() === "n") {
    event.preventDefault(); openMealDialog();
  } else if (!isEditing && event.key.toLowerCase() === "w") {
    event.preventDefault(); openWeightDialog();
  } else if (!isEditing && event.key === "ArrowLeft") {
    moveSelectedDate(-1);
  } else if (!isEditing && event.key === "ArrowRight") {
    moveSelectedDate(1);
  }
});

setInterval(() => { if (connected && document.visibilityState === "visible") syncNow("已自动同步", true); }, 15000);
document.addEventListener("visibilitychange", () => { if (connected && document.visibilityState === "visible") syncNow("已自动同步", true); });
window.addEventListener("focus", () => { if (connected) syncNow("已自动同步", true); });
