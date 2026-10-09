const API_BASE = "/liferecord-api";
const LEGACY_STORAGE_KEY = "liferecord.web.v1";
const UI_DATE_KEY = "liferecord.selected-date";
const symbols = { 早餐: "☀", 午餐: "◐", 晚餐: "☾", 加餐: "◇" };
const defaultSettings = {
  id: "profile", displayName: "", fitnessGoal: "增肌", height: 181, baselineWeight: 64,
  targetWeight: 72, weeklyWeightTarget: .25, calorieGoal: 2600, proteinGoal: 130,
  carbsGoal: 340, fatGoal: 70
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

let state = { meals: [], bodyMetrics: [], settings: null, deletions: [], serverTime: null };
let selectedDate = localStorage.getItem(UI_DATE_KEY) || dateKey(new Date());
let visibleMonth = parseDate(selectedDate);
let connected = false;
let localRevision = 0;
let syncInFlight = false;
let syncAgain = false;

function touchLocalState() { localRevision += 1; }

function cleanSnapshot(snapshot) {
  delete snapshot.waterEntries;
  if (snapshot.settings) delete snapshot.settings.waterGoal;
  return snapshot;
}

function goals() { return state.settings || defaultSettings; }
function selectedMeals() { return state.meals.filter(item => recordDateKey(item) === selectedDate); }
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
    state = cleanSnapshot(await api("/snapshot"));
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
    const inbound = cleanSnapshot(await api("/sync", { method: "POST", body: JSON.stringify(state) }));
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
  if (!raw || state.meals.length || state.bodyMetrics.length) return;
  try {
    const legacy = JSON.parse(raw);
    const timestamp = nowSeconds();
    state.meals = (legacy.meals || []).map((item, index) => ({
      id: String(item.id || newID()).toLowerCase(), date: epochForDateKey(item.date), kind: item.kind || "加餐",
      name: item.name || "迁移餐食", calories: Number(item.calories || 0), protein: Number(item.protein || 0),
      carbs: Number(item.carbs || 0), fat: Number(item.fat || 0), fiber: 0, note: "从旧版网页迁移",
      source: "手动", createdAt: timestamp - index, updatedAt: timestamp - index
    }));
    touchLocalState();
    if (await syncNow("旧版数据已迁移")) localStorage.removeItem(LEGACY_STORAGE_KEY);
  } catch (_) {}
}

function render() {
  const date = parseDate(selectedDate);
  const meals = selectedMeals();
  const nutrition = totals();
  const target = goals();
  $("#dateLabel").textContent = fmtDate(date);
  $("#toolbarDateLabel").textContent = relativeDateLabel(date);
  $("#mealTitle").textContent = selectedDate === dateKey(new Date()) ? "餐食记录" : `${date.getMonth() + 1} 月 ${date.getDate()} 日记录`;
  $("#mealSummary").textContent = `${meals.length} 餐 · ${Math.round(nutrition.calories)} kcal`;
  renderOverview(nutrition, target);
  renderMealPreview(meals);
  renderWeekRings();
  renderDailyRings(nutrition, meals.length, target);
  if (typeof renderAdmin === "function") renderAdmin();
}

function relativeDateLabel(date) {
  const today = parseDate(dateKey(new Date()));
  const days = Math.round((date - today) / 86400000);
  if (days === 0) return "今天";
  if (days === -1) return "昨天";
  if (days === 1) return "明天";
  return `${date.getMonth() + 1} 月 ${date.getDate()} 日`;
}

function renderOverview(nutrition, target) {
  const calorieProgress = progress(nutrition.calories, target.calorieGoal);
  const proteinProgress = progress(nutrition.protein, target.proteinGoal);
  $("#overviewCalories").textContent = `${Math.round(nutrition.calories)} kcal`;
  $("#overviewCaloriesDetail").textContent = `目标 ${Math.round(target.calorieGoal)} kcal`;
  $("#overviewProtein").textContent = `${Math.round(proteinProgress * 100)}%`;
  $("#overviewProteinDetail").textContent = `${Math.round(nutrition.protein)} / ${Math.round(target.proteinGoal)} g`;
  $("#overviewCaloriesBar").style.width = `${calorieProgress * 100}%`;
  $("#overviewProteinBar").style.width = `${proteinProgress * 100}%`;

  const endOfSelectedDay = epochForDateKey(selectedDate) + 86400;
  const metric = [...state.bodyMetrics].filter(item => item.date < endOfSelectedDay).sort((a, b) => b.date - a.date)[0];
  $("#overviewWeight").textContent = metric ? `${Number(metric.weight).toFixed(1)} kg` : "--";
  $("#overviewWeightDetail").textContent = metric ? `${fmtMealDate(metric.date)}${metric.bodyFat ? ` · 体脂 ${Number(metric.bodyFat).toFixed(1)}%` : ""}` : "暂无身体记录";
}

// SVG strokes keep the ring spacing and rounded ends crisp at every size.
function nutritionRings(values) {
  const colors = ["protein", "carbs", "meals"];
  return `<svg viewBox="0 0 200 200" aria-hidden="true">${values.map((value, index) => {
    const radius = 89 - index * 19;
    const fraction = Number.isFinite(value) ? Math.max(0, Math.min(value, 1)) : 0;
    return `<circle class="nutrition-track ${colors[index]}" cx="100" cy="100" r="${radius}"/><circle class="nutrition-progress ${colors[index]}" cx="100" cy="100" r="${radius}" pathLength="100" stroke-dasharray="${fraction * 100} 100" transform="rotate(-90 100 100)" ${fraction === 0 ? 'visibility="hidden"' : ""}/>`;
  }).join("")}</svg>`;
}

function renderDailyRings(nutrition, mealCount, target) {
  const values = [progress(nutrition.protein, target.proteinGoal), progress(nutrition.carbs, target.carbsGoal), progress(mealCount, 4)];
  const percent = Math.round(values.reduce((sum, value) => sum + value, 0) / 3 * 100);
  const ring = $("#dailyRings");
  ring.setAttribute("role", "img");
  ring.setAttribute("aria-label", `营养目标平均完成 ${percent}%，蛋白质 ${Math.round(values[0] * 100)}%，碳水 ${Math.round(values[1] * 100)}%，用餐 ${mealCount} 次`);
  ring.innerHTML = `${nutritionRings(values)}<div class="daily-ring-center"><strong>${percent}<small>%</small></strong><span>平均完成</span></div>`;
  $("#nutritionLegend").innerHTML = [
    ["protein", "蛋白质", Math.round(nutrition.protein), Math.round(target.proteinGoal), "g"],
    ["carbs", "碳水化合物", Math.round(nutrition.carbs), Math.round(target.carbsGoal), "g"],
    ["meals", "用餐次数", mealCount, 4, "次"]
  ].map(([color, label, value, goal, unit]) => `<div><i class="legend-dot ${color}"></i><span>${label}<small><b>${value}</b> / ${goal} ${unit}</small></span><em>${Math.round(values[["protein", "carbs", "meals"].indexOf(color)] * 100)}%</em></div>`).join("");
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
    html.push(`<button class="week-day ${key === selectedDate ? "selected" : ""} ${hasRecord ? "recorded" : ""}" type="button" data-week-date="${key}" aria-pressed="${key === selectedDate}" aria-label="${fmtDate(date)}${hasRecord ? "，已有记录" : ""}">
      <span>${labels[index]}</span>
      <i class="mini-rings" aria-hidden="true">${nutritionRings([progress(protein, target.proteinGoal), progress(carbs, target.carbsGoal), progress(meals.length, 4)])}<b class="mini-day-number">${date.getDate()}</b></i>
      <small>${hasRecord ? "已记录" : "待记录"}</small>
    </button>`);
  }
  $("#weekRings").innerHTML = html.join("");
}

function renderMealPreview() {
  const query = $("#mealSearch").value.trim().toLowerCase();
  const kind = $("#mealKindFilter").value;
  const meals = ($("#mealScope").value === "all" ? state.meals : selectedMeals())
    .filter(item => (!kind || item.kind === kind) && `${item.name} ${item.note || ""}`.toLowerCase().includes(query))
    .sort((a, b) => b.date - a.date);
  $("#mealPreview").innerHTML = meals.length ? meals.map(item => `<tr>
    <td><button class="record-name" data-show-meal="${item.id}">${escapeHtml(item.name)}</button><small>${fmtShortDate(item.date)} · ${escapeHtml(recordSource(item, "meal"))}</small></td>
    <td><span class="kind-badge">${escapeHtml(item.kind)}</span></td><td>${Math.round(item.calories)} <small>kcal</small></td><td>${Number(item.protein).toFixed(1)} g</td><td>${Number(item.carbs).toFixed(1)} g</td>
    <td><button class="text-button" data-edit-meal="${item.id}">编辑</button></td></tr>`).join("") : `<tr><td colspan="6"><div class="empty">没有匹配的餐食记录</div></td></tr>`;
  $("#tableSummary").textContent = `共 ${meals.length} 条记录 · 点击名称查看照片与详情`;
}

function escapeHtml(value) { const node = document.createElement("span"); node.textContent = String(value); return node.innerHTML; }
function showToast(message) { const toast = $("#toast"); toast.textContent = message; toast.classList.add("show"); clearTimeout(showToast.timer); showToast.timer = setTimeout(() => toast.classList.remove("show"), 1700); }

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
  } else if (type === "weight") {
    const end = epochForDateKey(selectedDate) + 86400;
    const entries = [...state.bodyMetrics].filter(item => item.date < end).sort((a, b) => b.date - a.date).slice(0, 20);
    const html = entries.length ? `<div class="source-list">${entries.map(item => `
      <div class="source-row">
        <span><strong>${Number(item.weight).toFixed(1)} kg${item.bodyFat ? ` · 体脂 ${Number(item.bodyFat).toFixed(1)}%` : ""}</strong><small>${fmtShortDate(item.date)} · ${escapeHtml(recordSource(item, "body"))}${item.note ? ` · ${escapeHtml(item.note)}` : ""}</small></span>
        <b><button class="text-button" type="button" data-admin-edit="body" data-record-id="${item.id}">编辑</button><button class="delete-record" type="button" data-delete-body="${item.id}" aria-label="删除这条身体记录">删除</button></b>
      </div>`).join("")}</div>` : emptyDetail("这一天之前还没有身体记录。");
    openDetail({ title: "体重记录", subtitle: `截至 ${date} 的最近记录`, html });
  } else if (type === "meals") {
    openDetail({ title: "饮食记录", subtitle: `${date} · ${meals.length} 餐`, html: mealSourceRows(meals, "calories", "kcal") });
  }
}

function showMealDetail(meal) {
  const photoIDs = Array.isArray(meal.photoIDs) ? meal.photoIDs.filter(id => /^[a-f0-9]{32}$/.test(id)) : [];
  const photos = photoIDs.length ? `<section class="detail-photos"><h3>餐食照片 <small>${photoIDs.length} 张</small></h3><div class="photo-gallery">${photoIDs.map((id, index) => `<img loading="lazy" src="${API_BASE}/images/${id}" alt="${escapeHtml(meal.name)}照片 ${index + 1}">`).join("")}</div></section>` : "";
  const input = meal.inputText ? `<section class="detail-note"><h3>${meal.source === "AI 估算" ? "给 AI 的描述" : "原始描述"}</h3><p>${escapeHtml(meal.inputText).replace(/\n/g, "<br>")}</p></section>` : (meal.source === "AI 估算" ? `<section class="detail-note"><h3>给 AI 的描述</h3><p>这条历史记录未保存原始描述，无法还原当时输入的内容。</p></section>` : "");
  openDetail({
    eyebrow: `${meal.kind} · ${recordSource(meal, "meal")}`,
    title: meal.name,
    subtitle: fmtShortDate(meal.date),
    html: `${input}<div class="detail-kpis"><div><span>热量</span><strong>${Math.round(meal.calories)} kcal</strong></div><div><span>蛋白质</span><strong>${Math.round(meal.protein)} g</strong></div><div><span>碳水</span><strong>${Math.round(meal.carbs)} g</strong></div><div><span>脂肪</span><strong>${Math.round(meal.fat)} g</strong></div></div>${meal.note ? `<section class="detail-note"><h3>记录说明</h3><p>${escapeHtml(meal.note)}</p></section>` : ""}<div class="detail-actions"><button class="primary-button" type="button" data-edit-meal="${meal.id}">编辑记录</button><button class="delete-record" type="button" data-delete-meal="${meal.id}">删除这条记录</button></div>${photos}`
  });
}

function addDeletion(id, recordType) {
  state.deletions = state.deletions.filter(item => !(item.id === id && item.recordType === recordType));
  state.deletions.push({ id, recordType, deletedAt: nowSeconds() });
  touchLocalState();
}

function recordedDates() {
  return new Set([...state.meals, ...state.bodyMetrics].map(recordDateKey));
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

let editingMealID = null;
let editingMealVersion = null;
let editingDateInput = null;
let retainedPhotoIDs = [];
function openMealDialog(meal = null) {
  // Click handlers pass an Event; only a stored record can be edited.
  if (!meal || !state.meals.includes(meal)) meal = null;
  editingMealID = meal?.id || null;
  editingMealVersion = meal?.updatedAt ?? null;
  const form = $("#mealForm"); form.reset();
  $("#mealFormTitle").textContent = meal ? "编辑餐食" : "记一餐";
  $("#mealFormEyebrow").textContent = meal ? "修改原记录 · 保留已有照片" : "新增记录";
  const date = meal ? new Date(meal.date * 1000) : parseDate(selectedDate);
  form.elements.date.value = `${dateKey(date)}T${pad(date.getHours())}:${pad(date.getMinutes())}`;
  editingDateInput = form.elements.date.value;
  retainedPhotoIDs = [...(meal?.photoIDs || [])];
  $("#mealEditError").textContent = "";
  renderEditablePhotos();
  if (meal) for (const key of ["kind", "name", "calories", "protein", "carbs", "fat", "fiber", "note", "source"]) form.elements[key].value = meal[key] ?? "";
  $("#mealDialog").showModal();
}
function openWeightDialog() { editBodyRecord(); }

render();
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

$("#mealPreview").addEventListener("click", event => {
  const button = event.target.closest("[data-show-meal]"); if (!button) return;
  const meal = state.meals.find(item => item.id === button.dataset.showMeal);
  if (meal) showMealDetail(meal);
});

document.addEventListener("click", event => {
  const edit = event.target.closest("[data-edit-meal]");
  if (edit) { const meal = state.meals.find(item => item.id === edit.dataset.editMeal); if (meal) openMealDialog(meal); return; }
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
  if (mealButton) await deleteAdminRecord("meal", mealButton.dataset.deleteMeal);
  else if (bodyButton) await deleteAdminRecord("body", bodyButton.dataset.deleteBody);
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
$("#searchMealButton").addEventListener("click", () => { $("#records").scrollIntoView(); $("#mealSearch").focus(); });
$("#showMealsButton").addEventListener("click", () => showColumnDetail("meals"));

$("#addMealButton").addEventListener("click", openMealDialog);
$("#quickMealButton").addEventListener("click", openMealDialog);
$("#closeMeal").addEventListener("click", () => $("#mealDialog").close());
$("#mealForm").addEventListener("submit", async event => {
  event.preventDefault();
  const form = event.currentTarget; const data = new FormData(form); const timestamp = nowSeconds(); const id = editingMealID || newID();
  const submit = form.querySelector('[type="submit"]'); const originalLabel = submit.textContent;
  submit.disabled = true; submit.textContent = "正在保存照片…";
  try {
    const files = Array.from(form.elements.photos.files || []);
    const existing = editingMealID ? state.meals.find(item => item.id === editingMealID) : null;
    if (editingMealID && !existing) throw new Error("该记录已被删除，请关闭后重试");
    if (files.length + retainedPhotoIDs.length > 6) throw new Error("每餐合计最多保存 6 张照片");
    if (existing && existing.updatedAt !== editingMealVersion) throw new Error("该记录已在其他设备更新，请关闭后重新编辑");
    const date = existing && data.get("date") === editingDateInput ? existing.date : new Date(data.get("date")).getTime() / 1000;
    if (!Number.isFinite(date) || !data.get("name").trim()) throw new Error("请填写有效的名称和时间");
    for (const key of ["calories", "protein", "carbs", "fat", "fiber"]) if (!Number.isFinite(Number(data.get(key))) || Number(data.get(key)) < 0) throw new Error("营养数据必须为非负数字");
    const photoIDs = await uploadMealPhotos(id, files);
    const record = {
      ...(existing || {}), id, date, kind: data.get("kind"), name: data.get("name").trim(),
      calories: Number(data.get("calories")), protein: Number(data.get("protein")), carbs: Number(data.get("carbs")),
      fat: Number(data.get("fat")), fiber: Number(data.get("fiber")), note: data.get("note").trim(),
      source: data.get("source"), createdAt: existing?.createdAt || timestamp, updatedAt: timestamp,
      photoIDs: [...retainedPhotoIDs, ...photoIDs]
    };
    const {id: recordID, updatedAt, createdAt, ...fields} = record;
    await saveAdminActions([{...recordAction("meal", existing, fields), recordID}]);
    form.reset(); $("#mealDialog").close(); $("#detailDialog").close(); showToast("餐食已保存并同步");
  } catch (error) {
    $("#mealEditError").textContent = error.message || "保存失败";
  } finally {
    submit.disabled = false; submit.textContent = originalLabel;
  }
});

$("#addWeightButton").addEventListener("click", openWeightDialog);
$("#quickWeightButton").addEventListener("click", openWeightDialog);
$("#closeWeight").addEventListener("click", () => $("#weightDialog").close());
$("#weightForm").addEventListener("submit", async event => {
  event.preventDefault(); const form=event.currentTarget, data=new FormData(form), button=form.querySelector('[type="submit"]'); button.disabled=true;
  try {
    await saveAdminActions([recordAction("body", bodyEdit, {date:timestampFromForm(data.get("date"),bodyEdit), weight:Number(data.get("weight")), bodyFat:data.get("bodyFat")===""?null:Number(data.get("bodyFat")), waist:data.get("waist")===""?null:Number(data.get("waist")), note:data.get("note").trim()})]);
    form.reset(); $("#weightDialog").close(); showToast("身体数据已保存并同步");
  } catch(error) { showToast(error.message); } finally {button.disabled=false;}
});

$("#editGoalsButton").addEventListener("click", () => {
  const target = goals(), form = $("#goalsForm"); profileVersion=state.settings?.updatedAt??null;
  for (const key of profileFields) form.elements[key].value = target[key];
  $("#goalsDialog").showModal();
});
$("#closeGoals").addEventListener("click", () => $("#goalsDialog").close());
$("#goalsForm").addEventListener("submit", async event => {
  event.preventDefault(); const form=event.currentTarget, data=new FormData(form), button=form.querySelector('[type="submit"]'); button.disabled=true;
  try {
    const fields={};
    for(const key of profileFields) fields[key] = ["displayName","fitnessGoal"].includes(key)?data.get(key):Number(data.get(key));
    await saveAdminActions([{recordType:"settings",operation:"update",recordID:"profile",expectedUpdatedAt:profileVersion,fields}]);
    $("#goalsDialog").close(); showToast("档案与目标已同步到 App");
  } catch(error) {showToast(error.message);} finally {button.disabled=false;}
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
    $("#records").scrollIntoView(); $("#mealSearch").focus();
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

for (const id of ["mealSearch", "mealScope", "mealKindFilter"]) $("#" + id).addEventListener("input", renderMealPreview);
$("#sidebarGoals").addEventListener("click", () => $("#editGoalsButton").click());

function renderEditablePhotos() {
  $("#editablePhotos").innerHTML = retainedPhotoIDs.length ? `<p class="upload-hint">已有照片（保存后移除选中的照片）</p><div class="editable-photos">${retainedPhotoIDs.map(id=>`<div><img src="${API_BASE}/images/${id}" alt="已有餐食照片"><button type="button" class="text-button" data-remove-photo="${id}">移除</button></div>`).join("")}</div>` : "";
}
$("#editablePhotos").addEventListener("click",event=>{const button=event.target.closest("[data-remove-photo]"); if(button){retainedPhotoIDs=retainedPhotoIDs.filter(id=>id!==button.dataset.removePhoto);renderEditablePhotos();}});
