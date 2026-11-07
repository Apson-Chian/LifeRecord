'use strict';

const byId = id => document.getElementById(id);
const login = byId('login');
const workspace = byId('workspace');
const activity = byId('activity');
const logout = byId('logout');
const notice = byId('notice');
const confirmation = byId('confirm');
const dateFormat = new Intl.DateTimeFormat('zh-CN', {
  timeZone:'Asia/Shanghai', year:'numeric', month:'2-digit', day:'2-digit', hour:'2-digit', minute:'2-digit',
});
let page = 1;
let filters = {q:'', status:'all'};
let loadVersion = 0;
let activityVersion = 0;
let activityButton;

function notify(message='', error=false){
  notice.textContent = message;
  notice.dataset.error = String(error);
}

function showSession(authenticated){
  login.hidden = authenticated;
  logout.hidden = !authenticated;
  workspace.hidden = !authenticated;
  if(!authenticated){
    loadVersion++;
    activityVersion++;
    activity.hidden = true;
    byId('activity-summary').replaceChildren();
    byId('activity-events').replaceChildren();
    byId('activity-account').textContent = '';
    byId('users').replaceChildren();
    byId('count').textContent = '';
    page = 1;
  }
}

async function request(path, body){
  const options = body === undefined ? {} : {
    method:'POST', headers:{'Content-Type':'application/json'}, body:JSON.stringify(body),
  };
  const response = await fetch('./api/'+path, {cache:'no-store', credentials:'same-origin', ...options});
  const data = await response.json().catch(()=>({}));
  if(response.status===401 && path!=='login')showSession(false);
  if(!response.ok)throw new Error(data.error || '服务暂时不可用，请重试。');
  return data;
}

const actions = {
  suspend:['停用账号','停用后会撤销现有登录会话并阻止同步，已保存的记录会保留。'],
  restore:['恢复账号','恢复后用户可重新登录或使用原有同步密钥，已撤销的会话不会恢复。'],
  'revoke-sessions':['撤销会话','撤销后，现有登录会话需要重新登录。独立同步密钥仍可使用。'],
};

function actionButton(user, action){
  const button = document.createElement('button');
  button.type = 'button';
  button.textContent = actions[action][0];
  button.addEventListener('click',()=>{
    byId('confirm-title').textContent = actions[action][0];
    byId('confirm-message').textContent = (user.username || user.label)+'。'+actions[action][1];
    confirmation.returnValue = '';
    confirmation.showModal();
    confirmation.addEventListener('close', async ()=>{
      if(confirmation.returnValue!=='confirm')return;
      button.disabled = true;
      try{
        await request('users/change', {id:user.id, action});
        await loadUsers(page);
        notify(actions[action][0]+'成功。');
      }catch(error){
        notify(error.message, true);
      }finally{
        button.disabled = false;
      }
    }, {once:true});
  });
  return button;
}

const activityLabels = {
  login:'登录', register:'注册', sync:'同步', upload:'图片上传', ai_chat:'AI 对话', ai_plan:'AI 规划',
};
const platformLabels = {ios:'iOS', android:'Android', web:'Web', unknown:'未知'};

function activityTime(value){
  return value === null ? '暂无记录' : dateFormat.format(new Date(value*1000));
}

function renderActivity(result){
  const recordCount = type => result.records.find(record=>record.record_type===type)?.total ?? 0;
  const recordTimes = result.records.map(record=>record.last_update);
  const summary = [
    ['最近登录',activityTime(result.last_login)],
    ['最近记录更新',activityTime(recordTimes.length ? Math.max(...recordTimes) : null)],
    ['最近图片上传',activityTime(result.images.last_upload)],
    ['默认 AI 近 7 个 UTC 日用量',result.ai_usage ?? '暂无统计'],
    ['饮食记录',recordCount('meal')],
    ['身体记录',recordCount('body')],
    ['训练记录',recordCount('workout')],
    ['已存图片',result.images.total],
  ];
  const summaryNodes = summary.map(([label,value])=>{
    const group = document.createElement('div');
    const term = document.createElement('dt');
    const detail = document.createElement('dd');
    term.textContent = label;
    detail.textContent = value;
    group.append(term,detail);
    return group;
  });
  byId('activity-summary').replaceChildren(...summaryNodes);
  const rows = result.events.map(event=>{
    const row = document.createElement('tr');
    const outcome = event.status >= 200 && event.status < 300 ? '成功' : '未成功';
    for(const value of [activityTime(event.ts),activityLabels[event.action],platformLabels[event.platform],outcome+' · '+event.status]){
      row.insertCell().textContent = value;
    }
    return row;
  });
  if(!rows.length){
    const row = document.createElement('tr');
    const cell = row.insertCell();
    cell.colSpan = 4;
    cell.textContent = '近期暂无活动。';
    rows.push(row);
  }
  byId('activity-events').replaceChildren(...rows);
  byId('activity-data').hidden = false;
}

async function showActivity(user, button){
  const version = ++activityVersion;
  activityButton = button;
  notify();
  workspace.hidden = true;
  activity.hidden = false;
  byId('activity-account').textContent = user.username || user.label;
  byId('activity-data').hidden = true;
  byId('activity-status').textContent = '正在读取用户活动…';
  byId('activity-title').focus();
  try{
    const result = await request('users/activity?'+new URLSearchParams({id:user.id}));
    if(version!==activityVersion)return;
    renderActivity(result);
    byId('activity-status').textContent = '';
  }catch(error){
    if(version===activityVersion)byId('activity-status').textContent = error.message;
    else if(!login.hidden)notify(error.message,true);
  }
}

byId('activity-back').addEventListener('click',()=>{
  activityVersion++;
  activity.hidden = true;
  workspace.hidden = false;
  activityButton?.focus();
});

function renderUsers(result){
  page = result.page;
  const rows = result.users.map(user=>{
    const row = document.createElement('tr');
    const account = row.insertCell();
    const label = document.createElement('strong');
    label.textContent = user.username || user.label;
    const identifier = document.createElement('small');
    identifier.textContent = user.id;
    account.append(label,identifier);
    row.insertCell().textContent = dateFormat.format(new Date(user.created_at*1000));
    row.insertCell().textContent = user.disabled ? '已停用' : '正常';
    const controls = row.insertCell();
    const view = document.createElement('button');
    view.type = 'button';
    view.textContent = '活动';
    view.setAttribute('aria-label', '查看 '+(user.username || user.label)+' 的活动');
    view.addEventListener('click',()=>showActivity(user,view));
    controls.append(view);
    if(user.id==='legacy-owner')controls.append(' 私人档案 · 受保护');
    else if(user.disabled && user.restorable)controls.append(actionButton(user,'restore'));
    else if(user.disabled)controls.append(' 不可恢复');
    else controls.append(actionButton(user,'suspend'), actionButton(user,'revoke-sessions'));
    return row;
  });
  if(!rows.length){
    const row = document.createElement('tr');
    const cell = row.insertCell();
    cell.colSpan = 4;
    cell.textContent = '没有符合条件的账号。';
    rows.push(row);
  }
  byId('users').replaceChildren(...rows);
  byId('count').textContent = `共 ${result.total} 个账号 · 第 ${page} 页`;
  byId('previous').disabled = page<=1;
  byId('next').disabled = page*result.page_size>=result.total;
}

async function loadUsers(targetPage){
  const version = ++loadVersion;
  const result = await request('users?'+new URLSearchParams({...filters,page:targetPage}));
  if(version===loadVersion)renderUsers(result);
}

function browse(targetPage){
  notify();
  return loadUsers(targetPage).catch(error=>notify(error.message,true));
}

byId('login-form').addEventListener('submit',async event=>{
  event.preventDefault();
  const button = event.target.querySelector('button');
  const password = byId('password');
  notify();
  button.disabled = true;
  try{
    await request('login', {password:password.value});
    password.value = '';
    showSession(true);
    await browse(1);
  }catch(error){
    notify(error.message,true);
  }finally{
    button.disabled = false;
  }
});

byId('filters').addEventListener('submit',event=>{
  event.preventDefault();
  filters = {q:byId('query').value,status:byId('status').value};
  browse(1);
});
byId('previous').addEventListener('click',()=>browse(page-1));
byId('next').addEventListener('click',()=>browse(page+1));
logout.addEventListener('click',async ()=>{
  try{
    await request('logout',{});
    showSession(false);
    notify('已退出登录。');
  }catch(error){
    notify(error.message,true);
  }
});

request('session').then(result=>{
  showSession(result.authenticated);
  if(result.authenticated)return browse(1);
}).catch(error=>notify(error.message,true));
