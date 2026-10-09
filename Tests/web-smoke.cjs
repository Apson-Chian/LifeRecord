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
 let snapshot={meals:[{id:'d0a4f4ee-2222-4444-8888-555555555555',date:timestamp,kind:'午餐',name:'鸡胸肉拌饭',calories:650,protein:42,carbs:78,fat:18,fiber:5,note:'米饭 200g',inputText:'只吃了一半\n<script>throw new Error("unescaped input")</script>',source:'AI 估算',createdAt:timestamp-3600,updatedAt:timestamp,photoIDs:[]}],bodyMetrics:Array.from({length:12},(_,i)=>({id:`body-${i}`,date:timestamp-(11-i)*86400,weight:70-i*.1,bodyFat:i===11?null:19-i*.08,waist:80,note:'晨起空腹',updatedAt:timestamp})),deletions:[],settings:null};
 await page.route('http://liferecord.test/**', async route => {
  const url=new URL(route.request().url());
  if(url.pathname.startsWith('/liferecord-api')) {
   if(url.pathname.endsWith('/sync')) snapshot=JSON.parse(route.request().postData());
   if(url.pathname.endsWith('/admin')) {
    const {actions}=JSON.parse(route.request().postData());
    for(const a of actions) {
     const key={meal:'meals',body:'bodyMetrics'}[a.recordType];
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
 console.log('PASS: original meal input escaped and preserved across edits, meal/body editing, AI preview+apply, nullable body fat, chart selection+range, calendar, search, 4 responsive widths');
 } finally {await browser.close();}
})();
