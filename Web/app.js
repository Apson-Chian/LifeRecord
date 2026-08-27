const STORAGE_KEY = "liferecord.web.v1";
const goals = { calories: 2600, protein: 130, carbs: 340, fat: 70, water: 2800 };
const commonWater = [200, 250, 330, 500, 750];
const symbols = { 早餐: "☀", 午餐: "◐", 晚餐: "☾", 加餐: "◇" };

const pad = value => String(value).padStart(2, "0");
const dateKey = date => `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}`;
const parseDate = value => { const [y, m, d] = value.split("-").map(Number); return new Date(y, m - 1, d); };
const fmtDate = date => new Intl.DateTimeFormat("zh-CN", { year: "numeric", month: "long", day: "numeric", weekday: "short" }).format(date);

function sampleState() {
  const now = new Date();
  const today = dateKey(now);
  const yesterday = new Date(now); yesterday.setDate(now.getDate() - 1);
  const threeDaysAgo = new Date(now); threeDaysAgo.setDate(now.getDate() - 3);
  return {
    selectedDate: today,
    meals: [
      { id: crypto.randomUUID(), date: today, kind: "早餐", name: "燕麦、牛奶和香蕉", calories: 510, protein: 25, carbs: 77, fat: 12 },
      { id: crypto.randomUUID(), date: today, kind: "午餐", name: "鸡胸肉糙米饭", calories: 720, protein: 52, carbs: 89, fat: 16 },
      { id: crypto.randomUUID(), date: dateKey(yesterday), kind: "晚餐", name: "番茄牛肉意面", calories: 680, protein: 41, carbs: 82, fat: 19 },
      { id: crypto.randomUUID(), date: dateKey(threeDaysAgo), kind: "午餐", name: "三文鱼饭", calories: 740, protein: 43, carbs: 73, fat: 26 }
    ],
    water: [
      { id: crypto.randomUUID(), date: today, amount: 500 },
      { id: crypto.randomUUID(), date: today, amount: 330 },
      { id: crypto.randomUUID(), date: dateKey(yesterday), amount: 750 }
    ]
  };
}

function loadState() {
  try {
    const saved = JSON.parse(localStorage.getItem(STORAGE_KEY));
    if (saved?.meals && saved?.water) return saved;
  } catch (_) {}
  const initial = sampleState();
  localStorage.setItem(STORAGE_KEY, JSON.stringify(initial));
  return initial;
}

let state = loadState();
let visibleMonth = parseDate(state.selectedDate);
const $ = selector => document.querySelector(selector);

function saveState() { localStorage.setItem(STORAGE_KEY, JSON.stringify(state)); }
function selectedMeals() { return state.meals.filter(item => item.date === state.selectedDate); }
function selectedWater() { return state.water.filter(item => item.date === state.selectedDate).reduce((sum, item) => sum + item.amount, 0); }
function totals() { return selectedMeals().reduce((sum, item) => ({ calories: sum.calories + item.calories, protein: sum.protein + item.protein, carbs: sum.carbs + item.carbs, fat: sum.fat + item.fat }), { calories: 0, protein: 0, carbs: 0, fat: 0 }); }
function progress(value, goal) { return Math.min(Math.max(value / goal, 0), 1); }

function render() {
  const date = parseDate(state.selectedDate);
  const meals = selectedMeals();
  const nutrition = totals();
  const water = selectedWater();
  $("#dateLabel").textContent = fmtDate(date);
  $("#mealTitle").textContent = state.selectedDate === dateKey(new Date()) ? "今天吃了什么" : `${date.getMonth() + 1} 月 ${date.getDate()} 日记录`;
  $("#mealCount").textContent = meals.length;
  $("#mealLegend").textContent = `${meals.length} / 4 次`;
  $("#carbsLegend").textContent = `${nutrition.carbs} / ${goals.carbs} g`;
  $("#proteinLegend").textContent = `${nutrition.protein} / ${goals.protein} g`;
  $(".ring-meals").style.setProperty("--progress", progress(meals.length, 4));
  $(".ring-carbs").style.setProperty("--progress", progress(nutrition.carbs, goals.carbs));
  $(".ring-protein").style.setProperty("--progress", progress(nutrition.protein, goals.protein));
  $("#rings").setAttribute("aria-label", `用餐 ${meals.length} 次，碳水 ${nutrition.carbs} 克，蛋白质 ${nutrition.protein} 克`);
  const remaining = goals.calories - nutrition.calories;
  $("#calorieStatus").textContent = remaining >= 0 ? `还差 ${remaining} 千卡` : `超出 ${Math.abs(remaining)} 千卡`;
  $("#waterTotal").textContent = (water / 1000).toFixed(1);
  $("#waterDetail").textContent = `${water} / ${goals.water} ml`;
  $("#waterProgress").style.width = `${progress(water, goals.water) * 100}%`;
  $("#proteinSummary").textContent = `${nutrition.protein} g`;
  $("#carbsSummary").textContent = `${nutrition.carbs} g`;
  $("#fatSummary").textContent = `${nutrition.fat} g`;
  $("#calorieSummary").textContent = `${nutrition.calories} kcal`;
  renderMeals(meals);
}

function renderMeals(meals) {
  const list = $("#mealList");
  if (!meals.length) {
    list.innerHTML = `<div class="empty">这一天还没有餐食记录，点“记一餐”开始。</div>`;
    return;
  }
  list.innerHTML = meals.map(item => `
    <div class="meal-item">
      <span class="meal-symbol" aria-hidden="true">${symbols[item.kind] || "◇"}</span>
      <div class="meal-copy"><strong>${escapeHtml(item.name)}</strong><small>${item.kind} · 蛋白 ${item.protein}g · 碳水 ${item.carbs}g · 脂肪 ${item.fat}g</small></div>
      <div class="meal-kcal"><strong>${item.calories}</strong><span>kcal</span><button class="delete-meal" data-delete="${item.id}" aria-label="删除 ${escapeHtml(item.name)}">×</button></div>
    </div>`).join("");
}

function escapeHtml(value) { const node = document.createElement("span"); node.textContent = value; return node.innerHTML; }
function showToast(message) { const toast = $("#toast"); toast.textContent = message; toast.classList.add("show"); clearTimeout(showToast.timer); showToast.timer = setTimeout(() => toast.classList.remove("show"), 1600); }

function renderWaterOptions() {
  $("#waterOptions").innerHTML = commonWater.map(amount => `<button type="button" data-water="${amount}">+${amount} ml</button>`).join("");
}

function recordedDates() { return new Set([...state.meals.map(item => item.date), ...state.water.map(item => item.date)]); }
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
    const classes = ["calendar-day", key === state.selectedDate ? "selected" : "", key === dateKey(new Date()) ? "today" : "", recorded.has(key) ? "recorded" : ""].filter(Boolean).join(" ");
    cells.push(`<button type="button" class="${classes}" data-date="${key}" aria-label="${fmtDate(date)}${recorded.has(key) ? "，已有记录" : ""}">${day}</button>`);
  }
  $("#calendarGrid").innerHTML = cells.join("");
}

renderWaterOptions();
render();

$("#waterOptions").addEventListener("click", event => {
  const button = event.target.closest("[data-water]"); if (!button) return;
  const amount = Number(button.dataset.water);
  state.water.push({ id: crypto.randomUUID(), date: state.selectedDate, amount }); saveState(); render(); showToast(`已记录 ${amount} ml 饮水`);
});

$("#mealList").addEventListener("click", event => {
  const button = event.target.closest("[data-delete]"); if (!button) return;
  state.meals = state.meals.filter(item => item.id !== button.dataset.delete); saveState(); render(); showToast("已删除餐食记录");
});

$("#dateButton").addEventListener("click", () => { visibleMonth = parseDate(state.selectedDate); renderCalendar(); $("#calendarDialog").showModal(); });
$("#prevMonth").addEventListener("click", () => { visibleMonth = new Date(visibleMonth.getFullYear(), visibleMonth.getMonth() - 1, 1); renderCalendar(); });
$("#nextMonth").addEventListener("click", () => { visibleMonth = new Date(visibleMonth.getFullYear(), visibleMonth.getMonth() + 1, 1); renderCalendar(); });
$("#calendarGrid").addEventListener("click", event => {
  const button = event.target.closest("[data-date]"); if (!button) return;
  state.selectedDate = button.dataset.date; saveState(); render(); $("#calendarDialog").close();
});

$("#addMealButton").addEventListener("click", () => $("#mealDialog").showModal());
$("#closeMeal").addEventListener("click", () => $("#mealDialog").close());
$("#mealForm").addEventListener("submit", event => {
  event.preventDefault(); const data = new FormData(event.currentTarget);
  state.meals.push({ id: crypto.randomUUID(), date: state.selectedDate, kind: data.get("kind"), name: data.get("name").trim(), calories: Number(data.get("calories")), protein: Number(data.get("protein")), carbs: Number(data.get("carbs")), fat: Number(data.get("fat")) });
  saveState(); render(); event.currentTarget.reset(); $("#mealDialog").close(); showToast("餐食已保存");
});
