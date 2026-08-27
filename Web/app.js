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
    setSyncStatus("已同步", "synced");
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
    setSyncStatus(message, "synced");
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
  $("#mealTitle").textContent = selectedDate === dateKey(new Date()) ? "今天吃了什么" : `${date.getMonth() + 1} 月 ${date.getDate()} 日记录`;
  $("#mealCount").textContent = meals.length;
  $("#carbsLegend").textContent = `${Math.round(nutrition.carbs)} / ${Math.round(target.carbsGoal)} g`;
  $("#proteinLegend").textContent = `${Math.round(nutrition.protein)} / ${Math.round(target.proteinGoal)} g`;
  $("#waterLegend").textContent = `${Math.round(water)} / ${Math.round(target.waterGoal)} ml`;
  $(".ring-meals").style.setProperty("--progress", progress(meals.length, 4));
  $(".ring-carbs").style.setProperty("--progress", progress(nutrition.carbs, target.carbsGoal));
  $(".ring-protein").style.setProperty("--progress", progress(nutrition.protein, target.proteinGoal));
  $("#rings").setAttribute("aria-label", `蛋白质 ${Math.round(nutrition.protein)} 克，碳水 ${Math.round(nutrition.carbs)} 克，用餐 ${meals.length} 次`);
  const remaining = Math.round(target.calorieGoal - nutrition.calories);
  $("#calorieStatus").textContent = remaining >= 0 ? `还差 ${remaining} 千卡` : `超出 ${Math.abs(remaining)} 千卡`;
  $("#waterTotal").textContent = (water / 1000).toFixed(1);
  $("#waterDetail").textContent = `${Math.round(water)} / ${Math.round(target.waterGoal)} ml`;
  $("#waterProgress").style.width = `${progress(water, target.waterGoal) * 100}%`;
  $("#proteinSummary").textContent = `${Math.round(nutrition.protein)} g`;
  $("#carbsSummary").textContent = `${Math.round(nutrition.carbs)} g`;
  $("#fatSummary").textContent = `${Math.round(nutrition.fat)} g`;
  $("#calorieSummary").textContent = `${Math.round(nutrition.calories)} kcal`;
  $("#goalCalories").textContent = `${Math.round(target.calorieGoal)} kcal`;
  $("#goalProtein").textContent = `${Math.round(target.proteinGoal)} g`;
  $("#goalCarbs").textContent = `${Math.round(target.carbsGoal)} g`;
  $("#goalWater").textContent = `${Math.round(target.waterGoal)} ml`;
  renderMeals(meals);
  renderMetrics();
  renderWeekRings();
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

function renderMeals(meals) {
  const list = $("#mealList");
  if (!meals.length) {
    list.innerHTML = `<div class="empty">这一天还没有餐食记录，点“记一餐”开始。</div>`;
    return;
  }
  list.innerHTML = meals.sort((a, b) => b.date - a.date).map(item => {
    const photoIDs = Array.isArray(item.photoIDs) ? item.photoIDs.filter(id => /^[a-f0-9]{32}$/.test(id)) : [];
    const leading = photoIDs.length
      ? `<button class="meal-photo" type="button" data-show-meal="${item.id}" aria-label="查看 ${escapeHtml(item.name)} 的 ${photoIDs.length} 张照片"><img loading="lazy" src="${API_BASE}/images/${photoIDs[0]}" alt="${escapeHtml(item.name)}"><em>${photoIDs.length}</em></button>`
      : `<span class="meal-symbol" aria-hidden="true">${symbols[item.kind] || "◇"}</span>`;
    return `
    <div class="meal-item">
      ${leading}
      <div class="meal-copy"><strong>${escapeHtml(item.name)}</strong><small>${item.kind} · 蛋白 ${Math.round(item.protein)}g · 碳水 ${Math.round(item.carbs)}g · 脂肪 ${Math.round(item.fat)}g</small></div>
      <div class="meal-kcal"><strong>${Math.round(item.calories)}</strong><span>kcal</span><button class="delete-meal" data-delete-meal="${item.id}" aria-label="删除 ${escapeHtml(item.name)}">×</button></div>
    </div>`;
  }).join("");
}

function renderMetrics() {
  const list = $("#metricList");
  const items = [...state.bodyMetrics].sort((a, b) => b.date - a.date).slice(0, 8);
  if (!items.length) {
    list.innerHTML = `<div class="empty">还没有身体数据，记录后会与 iPhone 同步。</div>`;
    return;
  }
  list.innerHTML = items.map(item => `
    <div class="metric-item">
      <div><strong>${fmtShortDate(item.date)}</strong><small>${escapeHtml(item.note || "身体记录")}</small></div>
      <span class="metric-value">${Number(item.weight).toFixed(1)} kg${item.bodyFat ? ` · ${Number(item.bodyFat).toFixed(1)}%` : ""}</span>
      <button class="delete-meal" data-delete-body="${item.id}" aria-label="删除身体记录">×</button>
    </div>`).join("");
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

function showMealPhotos(meal) {
  const photoIDs = Array.isArray(meal.photoIDs) ? meal.photoIDs.filter(id => /^[a-f0-9]{32}$/.test(id)) : [];
  if (!photoIDs.length) return;
  $("#photoTitle").textContent = meal.name;
  $("#photoGallery").innerHTML = photoIDs.map((id, index) => `<img src="${API_BASE}/images/${id}" alt="${escapeHtml(meal.name)}照片 ${index + 1}">`).join("");
  $("#photoDialog").showModal();
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

$("#mealList").addEventListener("click", async event => {
  const photoButton = event.target.closest("[data-show-meal]");
  if (photoButton) {
    const meal = state.meals.find(item => item.id === photoButton.dataset.showMeal);
    if (meal) showMealPhotos(meal);
    return;
  }
  const button = event.target.closest("[data-delete-meal]"); if (!button) return;
  addDeletion(button.dataset.deleteMeal, "meal");
  state.meals = state.meals.filter(item => item.id !== button.dataset.deleteMeal);
  render(); await syncNow(); showToast("已删除餐食记录");
});

$("#metricList").addEventListener("click", async event => {
  const button = event.target.closest("[data-delete-body]"); if (!button) return;
  addDeletion(button.dataset.deleteBody, "body");
  state.bodyMetrics = state.bodyMetrics.filter(item => item.id !== button.dataset.deleteBody);
  render(); await syncNow(); showToast("已删除身体记录");
});

$("#dateButton").addEventListener("click", () => { visibleMonth = parseDate(selectedDate); renderCalendar(); $("#calendarDialog").showModal(); });
$("#prevMonth").addEventListener("click", () => { visibleMonth = new Date(visibleMonth.getFullYear(), visibleMonth.getMonth() - 1, 1); renderCalendar(); });
$("#nextMonth").addEventListener("click", () => { visibleMonth = new Date(visibleMonth.getFullYear(), visibleMonth.getMonth() + 1, 1); renderCalendar(); });
$("#calendarGrid").addEventListener("click", event => {
  const button = event.target.closest("[data-date]"); if (!button) return;
  selectedDate = button.dataset.date; localStorage.setItem(UI_DATE_KEY, selectedDate); render(); $("#calendarDialog").close();
});
$("#weekRings").addEventListener("click", event => {
  const button = event.target.closest("[data-week-date]"); if (!button) return;
  selectedDate = button.dataset.weekDate; localStorage.setItem(UI_DATE_KEY, selectedDate); render();
});

$("#addMealButton").addEventListener("click", () => $("#mealDialog").showModal());
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

$("#addWeightButton").addEventListener("click", () => $("#weightDialog").showModal());
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

$("#closePhotos").addEventListener("click", () => $("#photoDialog").close());

setInterval(() => { if (connected && document.visibilityState === "visible") syncNow("已自动同步", true); }, 15000);
document.addEventListener("visibilitychange", () => { if (connected && document.visibilityState === "visible") syncNow("已自动同步", true); });
window.addEventListener("focus", () => { if (connected) syncNow("已自动同步", true); });
