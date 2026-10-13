// Requires Playwright and Chrome. Uses fixture APIs; never touches live records.
const { chromium } = require('playwright');
const fs = require('fs');
const path = require('path');
const assert = require('assert/strict');
(async () => {
 const browser = await chromium.launch({headless:true,channel:'chrome'});
 try {
 const page = await browser.newPage({viewport:{width:1440,height:1100}});
 const errors=[]; page.on('pageerror', e => errors.push(e.message));
 const timestamp = Date.now()/1000;
 let syncWrites=0, generation=1;
 let snapshot={workoutEntries:[],meals:[{id:'d0a4f4ee-2222-4444-8888-555555555555',date:timestamp,kind:'午餐',name:'鸡胸肉拌饭',calories:650,protein:42,carbs:78,fat:18,fiber:5,note:'米饭 200g',inputText:'只吃了一半\n<script>throw new Error("unescaped input")</script>',source:'AI 估算',createdAt:timestamp-3600,updatedAt:timestamp,photoIDs:[]}],bodyMetrics:Array.from({length:12},(_,i)=>({id:`body-${i}`,date:timestamp-(11-i)*86400,weight:70-i*.1,bodyFat:i===11?null:19-i*.08,waist:80,note:'晨起空腹',updatedAt:timestamp})),deletions:[],settings:null};
 await page.route('http://liferecord.test/**', async route => {
  const url=new URL(route.request().url());
  if(url.pathname.startsWith('/liferecord-api')) {
   if(url.pathname.endsWith('/sync')) {syncWrites++;snapshot=JSON.parse(route.request().postData());}
   if(url.pathname.endsWith('/admin')) {
    const {actions}=JSON.parse(route.request().postData());
    generation++;
    for(const a of actions) {
     const key={meal:'meals',body:'bodyMetrics',workout:'workoutEntries'}[a.recordType];
     if(a.recordType==='settings') {snapshot.settings={...(snapshot.settings||{}),...a.fields,id:'profile',updatedAt:Date.now()/1000};continue;}
     const index=snapshot[key].findIndex(x=>x.id===a.recordID);
     if(a.operation==='delete') snapshot[key].splice(index,1);
     else if(a.operation==='update') snapshot[key][index]={...snapshot[key][index],...a.fields,updatedAt:Date.now()/1000};
     else snapshot[key].push({...a.fields,id:a.recordID||`new-${Date.now()}`,updatedAt:Date.now()/1000});
    }
   }
   if(url.pathname.endsWith('/ai/plan')) {
    const before=snapshot.bodyMetrics[0];
    return route.fulfill({json:{answer:'将这次测量的体脂率调整为 18.5%。',actions:[{operation:'update',recordType:'body',recordID:before.id,expectedUpdatedAt:before.updatedAt,fields:{bodyFat:18.5},before,after:{...before,bodyFat:18.5}}]}});
   }
   if(url.pathname.endsWith('/snapshot')) {const etag='\"fixture-'+generation+'\"'; if(route.request().headers()['if-none-match']===etag)return route.fulfill({status:304});return route.fulfill({json:snapshot,headers:{ETag:etag}});}
   if(url.pathname.endsWith('/ai/config/check')) return route.fulfill({json:{ok:true,message:'地址与参数检查通过'}});
   return route.fulfill({json:snapshot});
  }
  const name=url.pathname==='/'?'index.html':url.pathname.slice(1);
  return route.fulfill({body:fs.readFileSync(path.join(__dirname,'../Web',name)),contentType:name.endsWith('.js')?'text/javascript':name.endsWith('.css')?'text/css':'text/html'});
 });
 await page.goto('http://liferecord.test/');
 await page.locator('#mealPreview [data-show-meal]').click();
 assert.match(await page.locator('#detailDialog').innerText(), /给 AI 的描述.*只吃了一半.*<script>/s);
 assert.equal(await page.locator('#detailDialog script').count(), 0);
 await page.locator('#closeDetail').click();
 await page.locator('#mealPreview [data-edit-meal]').click();
 await page.locator('#mealForm [name=calories]').fill('325');
 await page.locator('#mealForm [name=protein]').fill('0');
 await page.locator('#mealForm [name=note]').fill('只吃了一半');
 await page.getByRole('button',{name:'保存记录',exact:true}).click();
 await page.waitForFunction(()=>!document.querySelector('#mealDialog').open);
 assert.equal(snapshot.meals.length,1); assert.equal(snapshot.meals[0].calories,325); assert.equal(snapshot.meals[0].protein,0);
 assert.equal(snapshot.meals[0].source,'AI 估算'); assert.equal(snapshot.meals[0].createdAt,timestamp-3600); assert.equal(snapshot.meals[0].fiber,5); assert.equal(snapshot.meals[0].date,timestamp);
 assert.equal(snapshot.meals[0].inputText, '只吃了一半\n<script>throw new Error("unescaped input")</script>');
 await page.locator('#mealPreview [data-show-meal]').click();
 assert.match(await page.locator('#detailDialog').innerText(), /给 AI 的描述.*只吃了一半/s);
 await page.locator('#closeDetail').click();
 await page.locator('#mealSearch').fill('不存在'); assert.match(await page.locator('#mealPreview').innerText(),/没有匹配/);
 await page.locator('#mealSearch').fill('');
 await page.locator('[data-trend-key=weight][data-trend-id=body-0]').click();
 assert.match(await page.locator('#webWeightChart .chart-inspector').innerText(),/70.0 kg/);
 await page.locator('#webWeightChart [data-admin-edit]').click();
 await page.locator('#weightForm [name=bodyFat]').fill('17.5');
 await page.getByRole('button',{name:'保存身体数据',exact:true}).click();
 await page.waitForFunction(()=>!document.querySelector('#weightDialog').open);
 assert.equal(snapshot.bodyMetrics[0].bodyFat,17.5);
 assert.equal(snapshot.bodyMetrics.length,12);
 await page.locator('#aiInstruction').fill('把第一条身体测量的体脂率改为 18.5%');
 await page.locator('#aiGenerate').click();
 await page.locator('#aiApply').waitFor({state:'visible'});
 assert.equal(snapshot.bodyMetrics[0].bodyFat,17.5);
 assert.match(await page.locator('#aiPlan').innerText(),/17.5.*18.5/s);
 await page.locator('#aiApply').click();
 await page.waitForFunction(()=>document.querySelector('#aiStatus').textContent.includes('已应用'));
 assert.equal(snapshot.bodyMetrics[0].bodyFat,18.5);
 await page.locator('#adminRecordType').selectOption('body');
 await page.locator('#trendRange').selectOption('7');
 assert.equal(await page.locator('#webWeightChart [data-trend-id]').count(),7);
 await page.locator('#trendRange').selectOption('30');
 await page.locator('#recordCalendar [data-record-day]:not([disabled])').first().click();
 assert.match(await page.locator('#recordDayDetail').innerText(),/餐食.*身体/);
 await page.evaluate(()=>window.scrollTo(0,0));
 await page.screenshot({path:'/tmp/liferecord-desktop.png',fullPage:true});
 for(const width of [390,768,1024,1440]) {
  await page.setViewportSize({width,height:900});
  assert(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),`overflow at ${width}`);
 }
 await page.setViewportSize({width:390,height:844});
 await page.screenshot({path:'/tmp/liferecord-mobile.png',fullPage:true});
 assert.deepEqual(errors,[]);
 // Training editor preserves nested groups and supports custom body parts.
 await page.locator('#newWorkoutRecord').click();
 await page.locator('#workoutForm [name=bodyParts]').fill('自定义部位');
 await page.locator('#addExercise').click();
 await page.locator('[data-exercise="0"][data-field="name"]').fill('弹力带划船');
 await page.locator('[data-exercise="0"][data-field="bodyPart"]').fill('自定义部位');
 await page.locator('[data-add-set="0"]').click();
 await page.locator('[data-set="0"][data-field="reps"]').fill('12');
 await page.locator('[data-set="0"][data-field="weight"]').fill('20');
 await page.getByRole('button',{name:'保存训练',exact:true}).click();
 await page.locator('#workoutDialog').waitFor({state:'hidden'});
 assert.equal(snapshot.workoutEntries[0].exercises[0].sets[0].reps,12);
 snapshot.workoutEntries[0].exercises[0].custom='preserved';snapshot.workoutEntries[0].exercises[0].sets[0].id='set-preserved';
 generation++;await page.locator('#syncButton').click();await page.waitForFunction(()=>document.querySelector('#syncStatus').textContent.includes('已手动同步'));
 await page.locator('#adminRows [data-admin-edit="workout"]').click();
 await page.locator('[data-set="0"][data-field="reps"]').fill('10');
 await page.getByRole('button',{name:'保存训练',exact:true}).click();
 await page.locator('#workoutDialog').waitFor({state:'hidden'});
 assert.equal(snapshot.workoutEntries[0].exercises[0].custom,'preserved');
 assert.equal(snapshot.workoutEntries[0].exercises[0].sets[0].id,'set-preserved');
 page.once('dialog',dialog=>dialog.dismiss());
 await page.locator('#adminRows [data-admin-delete="workout"]').click();
 assert.equal(snapshot.workoutEntries.length,1);
 page.once('dialog',dialog=>dialog.accept());
 await page.locator('#adminRows [data-admin-delete="workout"]').click();
 await page.waitForFunction(()=>document.querySelector('#adminRows').textContent.includes('暂无匹配'));
 assert.equal(snapshot.workoutEntries.length,0);
 // Pagination caps the rendered row count.
 snapshot.bodyMetrics.push(...Array.from({length:35},(_,i)=>({...snapshot.bodyMetrics[0],id:'page-'+i})));
 generation++;
 await page.locator('#syncButton').click();
 await page.waitForFunction(()=>document.querySelector('#syncStatus').textContent.includes('已手动同步'));
 await page.locator('#adminRecordType').selectOption('body');
 assert.equal(await page.locator('#adminRows tr').count(),20);
 await page.locator('#adminNext').click();
 assert.match(await page.locator('#adminPageLabel').innerText(),/2 \/ 3/);
 assert.equal(syncWrites,0,'Web refresh must not upload a full snapshot');
 await page.locator('.topbar [data-open-settings]').click();
 await page.locator('#aiProvider').selectOption('custom');
 await page.locator('#aiEndpoint').fill('https://api.example.com/v1/chat/completions');
 await page.locator('#aiModel').fill('custom-model');
 await page.locator('#aiKey').fill('ephemeral-secret-test');
 await page.locator('#aiMaxTokens').fill('12000');
 await page.locator('#aiMaxTokens').dispatchEvent('change');
 assert(!(await page.evaluate(()=>JSON.stringify(localStorage))).includes('ephemeral-secret-test'));
 await page.locator('#aiEndpoint').fill('https://another.example.com/v1/chat/completions');
 await page.locator('#aiEndpoint').dispatchEvent('change');
 assert.equal(await page.locator('#aiKey').inputValue(),'');
 await page.locator('#aiProvider').selectOption('deepseek');
 await page.locator('#aiProvider').selectOption('custom');
 assert.equal(await page.locator('#aiModel').inputValue(),'custom-model');
 assert.equal(await page.locator('#aiMaxTokens').inputValue(),'12000');
 assert.deepEqual(await page.locator('#aiProvider option').evaluateAll(items=>items.map(x=>x.value)),['deepseek','glm','custom']);
 await page.locator('#aiProfileName').fill('视觉接口 A');await page.locator('#aiSaveProfile').click();
 const profileA=await page.locator('#aiSavedProfile').inputValue();
 await page.locator('#aiEndpoint').fill('https://third.example.com/v1/chat/completions');await page.locator('#aiEndpoint').dispatchEvent('change');
 await page.locator('#aiModel').fill('model-b');await page.locator('#aiProfileName').fill('接口 B');await page.locator('#aiSaveProfile').click();
 const profileB=await page.locator('#aiSavedProfile').inputValue();assert.notEqual(profileA,profileB);
 await page.locator('#aiSavedProfile').selectOption(profileA);
 assert.equal(await page.locator('#aiEndpoint').inputValue(),'https://another.example.com/v1/chat/completions');
 assert.equal(await page.locator('#aiModel').inputValue(),'custom-model');
 await page.locator('#aiModel').fill('updated-model');await page.locator('#aiUpdateProfile').click();
 await page.reload();await page.locator('.topbar [data-open-settings]').click();await page.locator('#aiSavedProfile').selectOption(profileA);
 assert.equal(await page.locator('#aiModel').inputValue(),'updated-model');assert.equal(await page.locator('#aiKey').inputValue(),'');
 assert(!(await page.evaluate(()=>JSON.stringify(localStorage))).includes('ephemeral-secret-test'));
 await page.locator('#aiSavedProfile').selectOption(profileB);page.once('dialog',dialog=>dialog.accept());await page.locator('#aiDeleteProfile').click();
 assert.equal(await page.locator('#aiSavedProfile option').count(),2);
 await page.locator('#webTheme').selectOption('dark');
 assert.equal(await page.locator('.overview-item').first().evaluate(el=>getComputedStyle(el).backgroundColor),'rgb(27, 30, 40)');
 await page.locator('#changeKeyButton').click();
 await page.locator('#authDialog[open]').waitFor();
 await page.locator('[name="token"]').fill('fixture-only-independent-key');
 await page.getByRole('button',{name:'安全连接',exact:true}).click();
 await page.waitForFunction(()=>document.querySelector('#syncStatus').textContent.includes('已同步'));
 assert.equal(await page.locator('[name="token"]').inputValue(),'');
 await page.locator('.topbar [data-open-settings]').click();
 page.once('dialog',dialog=>dialog.accept());
 await page.locator('#deleteAccountButton').click();
 await page.locator('#authDialog[open]').waitFor();
 assert.equal(await page.locator('#aiKey').inputValue(),'');
 assert.equal(errors.length,0,errors.join('\n'));
 console.log('PASS: deletion confirmation, nested workout editing, paginated records, read-only conditional refresh, API presets and endpoint-bound in-memory keys; original meal input escaped and preserved across edits, meal/body editing, AI preview+apply, nullable body fat, chart selection+range, calendar, search, 4 responsive widths');
 } finally {await browser.close();}
})();
