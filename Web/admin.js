/* Authenticated administration and inspection. All writes are committed on the server. */
let adminBusy = false;
let bodyEdit = null;
let waterEdit = null;
let profileVersion = null;
let pendingAIPlan = [];
let selectedTrend = { weight: null, bodyFat: null };
let calendarSelection = dateKey(new Date());
const recordKeys = { meal: 'meals', body: 'bodyMetrics', water: 'waterEntries' };
const fieldLabels = { name:'餐食名称',kind:'餐次',date:'时间',weight:'体重 kg',bodyFat:'体脂率 %',waist:'腰围 cm',calories:'热量 kcal',protein:'蛋白质 g',carbs:'碳水 g',fat:'脂肪 g',fiber:'膳食纤维 g',milliliters:'饮水 ml',note:'备注',source:'来源',photoIDs:'照片',displayName:'称呼',fitnessGoal:'健身目标',height:'身高 cm',baselineWeight:'起始体重 kg',targetWeight:'目标体重 kg',weeklyWeightTarget:'每周变化 kg',calorieGoal:'热量目标',proteinGoal:'蛋白质目标',carbsGoal:'碳水目标',fatGoal:'脂肪目标',waterGoal:'饮水目标' };
const profileFields = Object.keys(defaultSettings).filter(key => key !== 'id');
const localDateTime = timestamp => {
  const d = new Date(timestamp * 1000);
  return `${dateKey(d)}T${pad(d.getHours())}:${pad(d.getMinutes())}`;
};
const timestampFromForm = (value, original) => original && localDateTime(original.date) === value ? original.date : new Date(value).getTime() / 1000;

async function saveAdminActions(actions) {
  if (adminBusy) throw new Error('另一项修改正在保存，请稍后重试');
  adminBusy = true;
  // Drain a read/sync already in flight before committing, so its old response
  // cannot replace the committed snapshot in this page.
  try {
    while (syncInFlight) await new Promise(resolve => setTimeout(resolve, 30));
    syncInFlight = true;
    const result = await api('/admin', {method:'POST', body:JSON.stringify({actions})});
    state = result;
    touchLocalState();
    render();
    setSyncStatus(`已同步 · ${fmtSyncTime()}`, 'synced');
    return result;
  } finally {
    syncInFlight = false;
    adminBusy = false;
  }
}

function recordAction(kind, original, fields, operation = original ? 'update' : 'add') {
  return {recordType:kind, operation, recordID:original?.id, expectedUpdatedAt:original?.updatedAt ?? null, fields};
}

function renderAdmin() {
  renderBodyTrends();
  renderAdminRows();
  renderRecordCalendar();
}

function renderBodyTrends() {
  const range = $('#trendRange').value;
  const start = new Date(); start.setHours(0,0,0,0); start.setDate(start.getDate() - Number(range) + 1);
  const all = [...state.bodyMetrics].filter(x => range === 'all' || x.date >= start.getTime()/1000).sort((a,b)=>a.date-b.date);
  for (const [key, title, unit, color, container] of [['weight','体重','kg','#4563db','#webWeightChart'],['bodyFat','体脂率','%','#b45d99','#webFatChart']]) {
    const days = new Map();
    all.filter(x => x[key] != null).forEach(x => days.set(recordDateKey(x), x));
    const points = [...days.values()];
    if (!points.length) { $(container).innerHTML = `<h3>${title}</h3><div class="empty">此范围暂无${title}记录</div>`; continue; }
    const selected = points.find(x=>x.id===selectedTrend[key]) || points.at(-1);
    const values = points.map(x=>Number(x[key]));
    const min = Math.min(...values), max = Math.max(...values), padding = Math.max((max-min)*.25,.8);
    const low = Math.max(0,min-padding), high = max+padding;
    const first = points[0].date-43200, last = points.at(-1).date+43200;
    const x = t => 48 + (t-first)/(last-first)*524;
    const y = v => 184 - (v-low)/(high-low)*152;
    const path = points.map((p,i)=>`${i?'L':'M'}${x(p.date).toFixed(2)},${y(p[key]).toFixed(2)}`).join(' ');
    const ticks = Array.from({length:4},(_,i)=>low+(high-low)*i/3);
    const dateTicks = Array.from({length:Math.min(4,points.length)},(_,i)=>points[Math.round(i*(points.length-1)/Math.max(1,Math.min(4,points.length)-1))]);
    const delta = points.at(-1)[key]-points[0][key];
    $(container).innerHTML = `<div class="trend-heading"><h3>${title}</h3><span>${points.length} 天测量</span></div><div class="trend-stat"><strong>${Number(selected[key]).toFixed(1)} <small>${unit}</small></strong><span>区间 ${delta>=0?'+':''}${delta.toFixed(1)} ${key==='bodyFat'?'个百分点':'kg'}</span></div>
      <svg class="body-chart" viewBox="0 0 600 230" aria-label="${title}趋势，横轴日期，纵轴${unit}">
      <defs><linearGradient id="fill-${key}" x1="0" y1="0" x2="0" y2="1"><stop offset="0%" stop-color="${color}" stop-opacity=".18"/><stop offset="100%" stop-color="${color}" stop-opacity=".01"/></linearGradient></defs>
      ${ticks.map(v=>`<line x1="48" x2="572" y1="${y(v)}" y2="${y(v)}" class="chart-grid"/><text x="38" y="${y(v)+4}" text-anchor="end">${v.toFixed(1)}</text>`).join('')}
      <path d="${path} L${x(points.at(-1).date)},184 L${x(points[0].date)},184 Z" fill="url(#fill-${key})"/>
      <path d="${path}" stroke="${color}" stroke-width="2.5" fill="none" stroke-linejoin="round"/>
      <line x1="${x(selected.date)}" x2="${x(selected.date)}" y1="26" y2="184" stroke="${color}" stroke-opacity=".4" stroke-dasharray="4 4"/>
      ${points.map(p=>`<g role="button" tabindex="0" data-trend-key="${key}" data-trend-id="${p.id}" aria-label="${fmtShortDate(p.date)}，${Number(p[key]).toFixed(1)} ${unit}"><circle cx="${x(p.date)}" cy="${y(p[key])}" r="14" fill="transparent"/><circle cx="${x(p.date)}" cy="${y(p[key])}" r="${p.id===selected.id?5:3}" fill="${color}" stroke="white" stroke-width="2"/></g>`).join('')}
      ${dateTicks.map(p=>`<text x="${x(p.date)}" y="210" text-anchor="middle">${new Date(p.date*1000).getMonth()+1}/${new Date(p.date*1000).getDate()}</text>`).join('')}</svg>
      <div class="chart-inspector"><div><strong>${fmtShortDate(selected.date)}</strong><span>体重 ${Number(selected.weight).toFixed(1)} kg · 体脂 ${selected.bodyFat==null?'未测量':Number(selected.bodyFat).toFixed(1)+'%'}</span>${selected.note?`<small>${escapeHtml(selected.note)}</small>`:''}</div><button class="text-button" data-admin-edit="body" data-record-id="${selected.id}">编辑</button></div>
      <p class="chart-note">每日最后一次${title}测量 · 缺测日期不补零</p>`;
  }
}

function renderAdminRows() {
  const kind = $('#adminRecordType').value;
  const search = $('#adminSearch').value.trim().toLowerCase();
  const records = [...state[recordKeys[kind]]].sort((a,b)=>b.date-a.date).filter(item=>`${fmtShortDate(item.date)} ${new Date(item.date*1000).toLocaleDateString('sv')} ${item.weight??''} ${item.bodyFat??''} ${item.milliliters??''} ${item.note}`.toLowerCase().includes(search));
  $('#adminHead').innerHTML = `<tr><th>测量 / 记录时间</th>${kind==='body'?'<th>体重 kg</th><th>体脂率 %</th><th>腰围 cm</th>':'<th>饮水 ml</th>'}<th>备注</th><th>操作</th></tr>`;
  $('#adminRows').innerHTML = records.map(item=>`<tr><td>${fmtShortDate(item.date)}</td>${kind==='body'?`<td>${Number(item.weight).toFixed(1)}</td><td>${item.bodyFat==null?'未测量':Number(item.bodyFat).toFixed(1)}</td><td>${item.waist==null?'—':Number(item.waist).toFixed(1)}</td>`:`<td>${Math.round(item.milliliters)}</td>`}<td class="record-note">${escapeHtml(item.note||'—')}</td><td><button class="text-button" data-admin-edit="${kind}" data-record-id="${item.id}">编辑</button><button class="delete-record" data-admin-delete="${kind}" data-record-id="${item.id}">删除</button></td></tr>`).join('') || `<tr><td colspan="6"><div class="empty">暂无匹配记录</div></td></tr>`;
  $('#adminCount').textContent = `共 ${records.length} 条 · 时间从新到旧`;
}

function renderRecordCalendar() {
  const today = new Date(); today.setHours(0,0,0,0);
  const first = new Date(today); first.setDate(first.getDate()-29);
  const start = new Date(first); start.setDate(start.getDate()-(start.getDay()+6)%7);
  const days=[]; const cursor = new Date(start);
  while(cursor <= today || days.length%7) { days.push(new Date(cursor)); cursor.setDate(cursor.getDate()+1); }
  const counts = d => [state.meals,state.bodyMetrics,state.waterEntries].map(items=>items.filter(x=>recordDateKey(x)===dateKey(d)).length);
  $('#recordCalendar').innerHTML = `<div class="record-calendar"><div class="calendar-range">${first.getMonth()+1}/${first.getDate()} — ${today.getMonth()+1}/${today.getDate()}</div>${['一','二','三','四','五','六','日'].map(x=>`<span class="weekday-label">周${x}</span>`).join('')}${days.map(d=>{const c=counts(d),total=c.filter(Boolean).length;return `<button class="record-day level-${total} ${dateKey(d)===calendarSelection?'selected':''}" data-record-day="${dateKey(d)}" ${d>today||d<first?'disabled':''} aria-label="${dateKey(d)}，餐食${c[0]}条，身体${c[1]}条，饮水${c[2]}条">${d.getDate()}</button>`;}).join('')}</div><div class="calendar-legend">${[0,1,2,3].map(i=>`<span><i class="level-${i}"></i>${i} 类</span>`).join('')}</div><p class="chart-note">颜色表示餐食、身体、饮水中有记录的类型数，非达标评分。</p>`;
  const c=counts(parseDate(calendarSelection));
  $('#recordDayDetail').textContent = `${calendarSelection} · 餐食 ${c[0]} 条 · 身体 ${c[1]} 条 · 饮水 ${c[2]} 条`;
}

function editBodyRecord(original = null) {
  bodyEdit = original ? structuredClone(original) : null;
  const form = $('#weightForm'); form.reset();
  $('#weightFormTitle').textContent = original ? '编辑身体数据' : '记录身体数据';
  form.elements.date.value=localDateTime(original?.date ?? epochForDateKey(selectedDate));
  for (const key of ['weight','bodyFat','waist','note']) form.elements[key].value=original?.[key]??'';
  $('#weightDialog').showModal();
}
function editWaterRecord(original = null) {
  waterEdit = original ? structuredClone(original) : null;
  const form=$('#waterEditForm'); form.reset();
  form.elements.date.value=localDateTime(original?.date??epochForDateKey(selectedDate));
  form.elements.milliliters.value=original?.milliliters??250;
  form.elements.note.value=original?.note??'';
  $('#waterEditError').textContent=''; $('#waterEditDialog').showModal();
}

async function deleteAdminRecord(kind, id) {
  const original=state[recordKeys[kind]].find(x=>x.id===id);
  if(!original) return;
  try { await saveAdminActions([recordAction(kind,original,{},'delete')]); $('#detailDialog').close(); showToast('记录已删除并同步'); }
  catch(error) { showToast(error.message); }
}

document.addEventListener('click', event => {
  const edit=event.target.closest('[data-admin-edit]');
  if(edit) { const kind=edit.dataset.adminEdit, item=state[recordKeys[kind]].find(x=>x.id===edit.dataset.recordId); if(item) (kind==='body'?editBodyRecord:editWaterRecord)(item); }
  const del=event.target.closest('[data-admin-delete]'); if(del) deleteAdminRecord(del.dataset.adminDelete,del.dataset.recordId);
  const point=event.target.closest('[data-trend-id]'); if(point) { selectedTrend[point.dataset.trendKey]=point.dataset.trendId; renderBodyTrends(); }
  const day=event.target.closest('[data-record-day]'); if(day) { calendarSelection=day.dataset.recordDay; renderRecordCalendar(); }
  const close=event.target.closest('[data-close]'); if(close) $('#'+close.dataset.close).close();
});
document.addEventListener('keydown', event=>{const point=event.target.closest('[data-trend-id]'); if(point && ['Enter',' '].includes(event.key)) {event.preventDefault(); selectedTrend[point.dataset.trendKey]=point.dataset.trendId; renderBodyTrends(); document.querySelector(`[data-trend-key="${point.dataset.trendKey}"][data-trend-id="${point.dataset.trendId}"]`)?.focus();}});
$('#trendRange').addEventListener('change',renderBodyTrends);
$('#adminSearch').addEventListener('input',renderAdminRows);
$('#adminRecordType').addEventListener('change',renderAdminRows);
$('#newBodyRecord').addEventListener('click',()=>editBodyRecord());
$('#newWaterRecord').addEventListener('click',()=>editWaterRecord());
$('#waterEditForm').addEventListener('submit',async event=>{
  event.preventDefault(); const form=event.currentTarget, button=form.querySelector('[type=submit]')||form.querySelector('.submit-button'); button.disabled=true;
  try {const data=new FormData(form); await saveAdminActions([recordAction('water',waterEdit,{date:timestampFromForm(data.get('date'),waterEdit),milliliters:Number(data.get('milliliters')),note:data.get('note').trim()})]); $('#waterEditDialog').close(); showToast('饮水记录已保存');}
  catch(error) {$('#waterEditError').textContent=error.message;} finally {button.disabled=false;}
});

function displayField(key,value) {
  if(value==null) return '未填写';
  if(key==='date') return fmtShortDate(value);
  if(key==='photoIDs') return `${value.length} 张`;
  return String(value);
}
$('#aiForm').addEventListener('submit',async event=>{
  event.preventDefault(); const button=$('#aiGenerate'); button.disabled=true; button.textContent='正在生成…';
  pendingAIPlan=[]; $('#aiApply').hidden=true; $('#aiPlan').innerHTML=''; $('#aiStatus').classList.remove('success'); $('#aiStatus').textContent='正在分析记录，通常需要几十秒…';
  try {
    const result=await api('/ai/plan',{method:'POST',body:JSON.stringify({instruction:$('#aiInstruction').value,provider:$('#aiProvider').value,model:$('#aiModel').value,apiKey:$('#aiKey').value,timezone:Intl.DateTimeFormat().resolvedOptions().timeZone})});
    pendingAIPlan=result.actions||[]; $('#aiStatus').textContent='';
    $('#aiPlan').innerHTML=`<p class="ai-answer">${escapeHtml(result.answer)}</p>${pendingAIPlan.map(action=>`<article class="change-preview"><h4>${{add:'新增',update:'修改',delete:'删除'}[action.operation]} · ${{meal:'餐食',body:'身体测量',water:'饮水',settings:'个人档案与目标'}[action.recordType]}</h4><p>${escapeHtml(action.before?.name|| (action.before?.date?fmtShortDate(action.before.date):''))}</p>${action.operation==='delete'?'<p class="form-error">这条记录将被删除。</p>':`<dl>${Object.entries(action.fields).map(([key,value])=>`<div><dt>${escapeHtml(fieldLabels[key]||key)}</dt><dd><span>${escapeHtml(displayField(key,action.before?.[key]))}</span> → <strong>${escapeHtml(displayField(key,value))}</strong></dd></div>`).join('')}</dl>`}</article>`).join('')}`;
    $('#aiApply').hidden=!pendingAIPlan.length;
  } catch(error) {$('#aiStatus').textContent=error.message;} finally {button.disabled=false; button.textContent='生成修改预览';}
});
$('#aiApply').addEventListener('click',async()=>{
  const button=$('#aiApply'); button.disabled=true;
  try { await saveAdminActions(pendingAIPlan.map(({operation,recordType,recordID,expectedUpdatedAt,fields})=>({operation,recordType,recordID,expectedUpdatedAt,fields}))); const count=pendingAIPlan.length; pendingAIPlan=[]; button.hidden=true; $('#aiStatus').classList.add('success'); $('#aiStatus').textContent=`已应用 ${count} 项修改并同步`; $('#aiPlan').innerHTML=''; }
  catch(error) {$('#aiStatus').textContent=error.message;} finally {button.disabled=false;}
});
// Editing a prompt invalidates its old preview, preventing an accidental apply.
$('#aiInstruction').addEventListener('input',()=>{pendingAIPlan=[];$('#aiApply').hidden=true;$('#aiPlan').innerHTML='';});
$('#aiProvider').addEventListener('change',()=>{$('#aiKey').value='';$('#aiModel').value='';});
renderAdmin();
