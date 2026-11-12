/* Preferences and credentials use separate browser-local stores; neither is synced. */
const API_PREFS_KEY = 'liferecord.api-preferences.v2';
const API_SECRETS_KEY = 'liferecord.api-secrets.v1';
const apiDefaults = {model:'', endpoint:'', authMode:'bearer', authHeader:'', maxTokens:6000, tokenField:'max_tokens', temperature:.1, sendTemperature:true, jsonMode:false, extraParams:{}};
let apiPresets = {};
try { apiPresets = JSON.parse(localStorage.getItem(API_PREFS_KEY) || '{}'); if (!apiPresets || Array.isArray(apiPresets) || typeof apiPresets !== 'object') apiPresets={}; } catch (_) {}
// Convert an old hidden preset to an editable custom configuration.
if (apiPresets.selected==='dots') {
  apiPresets.custom={...apiDefaults,...apiPresets.dots,provider:'custom',endpoint:apiPresets.dots?.endpoint||'',authMode:'api-key',jsonMode:false,extraParams:{chat_template_kwargs:{enable_thinking:false},...(apiPresets.dots?.extraParams||{})}};
  apiPresets.selected=apiPresets.custom.endpoint?'custom':'default';delete apiPresets.dots;
}
let activeProvider = ['default','deepseek','glm','custom'].includes(apiPresets.selected) ? apiPresets.selected : 'default';
let savedAPIProfiles = Array.isArray(apiPresets.saved) ? apiPresets.saved.filter(p=>p && typeof p.id==='string' && typeof p.name==='string' && p.config && typeof p.config==='object') : [];
let apiSecrets = new Map();
try {
  const entries=JSON.parse(localStorage.getItem(API_SECRETS_KEY)||'[]');
  if(Array.isArray(entries)) apiSecrets=new Map(entries.filter(entry=>Array.isArray(entry)&&entry.length===2&&typeof entry[0]==='string'&&typeof entry[1]==='string'&&entry[1]));
} catch (_) {}
let previousAPIIdentity = '';
const configInputs = ['aiModel','aiEndpoint','aiAuthMode','aiAuthHeader','aiMaxTokens','aiTokenField','aiTemperature','aiSendTemperature','aiJSONMode','aiExtraParams'];
const temperatureInput = $('#aiTemperature');
const temperatureSlider = $('#aiTemperatureSlider');

function syncTemperatureSlider() {
  if (Number.isFinite(temperatureInput.valueAsNumber)) temperatureSlider.value = temperatureInput.value;
  const progress = temperatureSlider.valueAsNumber / Number(temperatureSlider.max);
  temperatureSlider.parentElement.style.setProperty('--slider-progress', `${progress * 100}%`);
}
function currentAPIIdentity(provider=activeProvider) { return JSON.stringify([provider,$('#aiEndpoint').value.trim()||provider,$('#aiAuthMode').value,$('#aiAuthMode').value==='custom'?$('#aiAuthHeader').value.trim():'']); }
function profileSecretIdentity(id,identity=previousAPIIdentity) {return JSON.stringify(['profile',id,identity]);}
function setAPISecret(identity,key) {if(key) apiSecrets.set(identity,key);else apiSecrets.delete(identity);}
function storeAPISecrets() {
  try {
    if(apiSecrets.size) localStorage.setItem(API_SECRETS_KEY,JSON.stringify([...apiSecrets]));
    else localStorage.removeItem(API_SECRETS_KEY);
  } catch (_) {throw new Error('浏览器无法保存 API Key，请检查存储空间或隐私设置；当前页面仍可使用。');}
}
function readAPIConfig() {
  if(activeProvider==='default') return {provider:'default',maxTokens:6000};
  let extraParams;
  try { extraParams=JSON.parse($('#aiExtraParams').value||'{}'); } catch (_) { throw new Error('额外参数必须是有效 JSON，例如 {"top_p":0.9}'); }
  if (!extraParams || Array.isArray(extraParams) || typeof extraParams !== 'object') throw new Error('额外参数必须为 JSON 对象');
  const blocked=['model','messages','stream','temperature','max_tokens','max_completion_tokens','response_format'];
  if(Object.keys(extraParams).some(key=>blocked.includes(key))) throw new Error('额外参数不能覆盖模型、消息和生成设置');
  return {provider:activeProvider,model:$('#aiModel').value.trim(),endpoint:$('#aiEndpoint').value.trim(),authMode:$('#aiAuthMode').value,authHeader:$('#aiAuthHeader').value.trim(),apiKey:$('#aiKey').value,maxTokens:Number($('#aiMaxTokens').value),tokenField:$('#aiTokenField').value,temperature:Number($('#aiTemperature').value),sendTemperature:$('#aiSendTemperature').checked,jsonMode:$('#aiJSONMode').checked,extraParams};
}
function persistAPIConfig() {
  try {
    if(activeProvider!=='default') setAPISecret(previousAPIIdentity,$('#aiKey').value);
    const identity=currentAPIIdentity();
    if(identity!==previousAPIIdentity) {$('#aiKey').value=apiSecrets.get(identity)||'';previousAPIIdentity=identity;}
    storeAPISecrets();
    const {apiKey,...config}=readAPIConfig();
    apiPresets[activeProvider]={...config,provider:activeProvider};apiPresets.selected=activeProvider;
    localStorage.setItem(API_PREFS_KEY,JSON.stringify(apiPresets));
    $('#aiConfigStatus').textContent='';
  } catch (error) {$('#aiConfigStatus').textContent=error.message;updateAPIVisibility();return false;}
  updateAPIVisibility();
  return true;
}
function loadAPIPreset() {
  const config={...apiDefaults,...apiPresets[activeProvider]};
  $('#aiProvider').value=activeProvider;
  for(const [id,key] of [['aiModel','model'],['aiEndpoint','endpoint'],['aiAuthMode','authMode'],['aiAuthHeader','authHeader'],['aiMaxTokens','maxTokens'],['aiTokenField','tokenField'],['aiTemperature','temperature']]) $('#'+id).value=config[key];
  $('#aiSendTemperature').checked=config.sendTemperature;$('#aiJSONMode').checked=config.jsonMode;$('#aiExtraParams').value=JSON.stringify(config.extraParams||{},null,2);
  previousAPIIdentity=currentAPIIdentity();$('#aiKey').value=apiSecrets.get(previousAPIIdentity)||'';updateAPIVisibility();
}
function updateAPIVisibility() {
  const builtin=activeProvider==='default';
  $('#aiDefaultNotice').hidden=!builtin;$('#aiCustomIntro').hidden=builtin;$('#aiCustomHint').hidden=builtin;
  $('#aiProfileName').closest('label').hidden=builtin;$('#aiSaveProfile').parentElement.hidden=builtin;
  for(const id of ['aiModel','aiKey','aiAuthMode','aiAuthHeader','aiMaxTokens','aiTokenField','aiSendTemperature','aiJSONMode','aiExtraParams']) {
    const label=$('#'+id).closest('label');if(label) label.hidden=builtin;
  }
  temperatureInput.closest('.temperature-control').hidden = builtin;
  $('#aiCheckConfig').textContent=builtin?'检查默认服务':'检查地址与参数';
  $('#aiEndpointLabel').hidden=activeProvider!=='custom';$('#aiHeaderLabel').hidden=builtin||$('#aiAuthMode').value!=='custom';
  temperatureInput.disabled = temperatureSlider.disabled = builtin || !$('#aiSendTemperature').checked;
  syncTemperatureSlider();
  const name=$('#aiProvider').selectedOptions[0]?.textContent||'';
  if(builtin) {$('#aiConfigSummary').textContent='默认 AI 服务 · 无需 API Key';return;}
  $('#aiConfigSummary').textContent=`${name} · ${$('#aiModel').value.trim()||'请在设置中填写模型'} · ${$('#aiKey').value?'已填写 API Key':'未设置 API Key'}`;
}
function clearAPISecrets() {
  apiSecrets.clear();$('#aiKey').value='';updateAPIVisibility();
  try {storeAPISecrets();$('#aiConfigStatus').textContent='';return true;}
  catch(error) {$('#aiConfigStatus').textContent=error.message;return false;}
}
$('#aiProvider').addEventListener('change',()=>{
  const next=$('#aiProvider').value;
  persistAPIConfig();activeProvider=next;loadAPIPreset();persistAPIConfig();
  $('#aiProfileName').value='';renderSavedAPIProfiles();storeSavedAPIProfiles();
  pendingAIPlan=[];$('#aiApply').hidden=true;$('#aiPlan').replaceChildren();
});
for(const id of configInputs) $('#'+id).addEventListener('change',persistAPIConfig);
temperatureInput.addEventListener('input', syncTemperatureSlider);
temperatureSlider.addEventListener('input', () => {
  temperatureInput.value = Number(temperatureSlider.valueAsNumber.toFixed(2));
  syncTemperatureSlider();
});
temperatureSlider.addEventListener('change', persistAPIConfig);
$('#aiKey').addEventListener('input',()=>{
  setAPISecret(previousAPIIdentity,$('#aiKey').value);
  try {storeAPISecrets();$('#aiConfigStatus').textContent=$('#aiKey').value?'API Key 已保存在本浏览器；命名配置请点击保存或更新。':'当前接口的 API Key 已清除；更新所选配置可同时清除其已保存的 Key。';}
  catch(error) {$('#aiConfigStatus').textContent=error.message;}
  updateAPIVisibility();
});
$('#aiClearKeys').addEventListener('click',()=>{
  if(!confirm('清除本浏览器保存的全部 API Key？接口配置和健康记录会保留。')) return;
  if(clearAPISecrets()) $('#aiConfigStatus').textContent='本浏览器保存的全部 API Key 已清除。';
});
$('#aiCheckConfig').addEventListener('click',async()=>{
  const generation=identityGeneration,button=$('#aiCheckConfig');button.disabled=true;$('#aiConfigStatus').textContent='正在检查…';
  try {const result=await api('/ai/config/check',{method:'POST',body:JSON.stringify(readAPIConfig())});if(generation===identityGeneration) $('#aiConfigStatus').textContent=result.message;}
  catch(error) {if(generation===identityGeneration) $('#aiConfigStatus').textContent=error.message;}
  finally {button.disabled=false;}
});
document.querySelectorAll('[data-open-settings]').forEach(button=>button.addEventListener('click',()=>{if(!connected)return showAuth();$('#settingsDialog').showModal();}));
loadAPIPreset();

function renderSavedAPIProfiles(selected='') {
  $('#aiSavedProfile').replaceChildren(new Option('选择配置',''),...savedAPIProfiles.map(p=>new Option(p.name,p.id)));
  $('#aiSavedProfile').value=selected;
  $('#aiUpdateProfile').disabled=!selected;$('#aiDeleteProfile').disabled=!selected;
  apiPresets.selectedProfile=selected;
}
function storeSavedAPIProfiles() {
  apiPresets.saved=savedAPIProfiles;
  localStorage.setItem(API_PREFS_KEY,JSON.stringify(apiPresets));
}
function saveNamedAPIProfile(update) {
  try {
    const name=$('#aiProfileName').value.trim();if(!name) throw new Error('请填写配置名称');
    if(!update && savedAPIProfiles.length>=30) throw new Error('最多保存 30 个接口配置');
    if(!persistAPIConfig()) return;
    const {apiKey,...config}=readAPIConfig();
    const id=update?$('#aiSavedProfile').value:Array.from(crypto.getRandomValues(new Uint8Array(16)),b=>b.toString(16).padStart(2,'0')).join('');
    if(update && !savedAPIProfiles.some(p=>p.id===id)) throw new Error('请先选择已保存配置');
    const profile={id,name,config};
    // A named profile owns a credential snapshot, including when two profiles share an endpoint.
    removeProfileSecrets(id);setAPISecret(profileSecretIdentity(id),apiKey);storeAPISecrets();
    savedAPIProfiles=update?savedAPIProfiles.map(p=>p.id===id?profile:p):[...savedAPIProfiles,profile];
    renderSavedAPIProfiles(id);storeSavedAPIProfiles();$('#aiConfigStatus').textContent='配置与 API Key 已保存在本浏览器，刷新后可继续使用。';
  } catch(error) {$('#aiConfigStatus').textContent=error.message;}
}
$('#aiSaveProfile').addEventListener('click',()=>saveNamedAPIProfile(false));
$('#aiUpdateProfile').addEventListener('click',()=>saveNamedAPIProfile(true));
$('#aiSavedProfile').addEventListener('change',()=>{
  const profile=savedAPIProfiles.find(p=>p.id===$('#aiSavedProfile').value);
  if(!profile) {renderSavedAPIProfiles();storeSavedAPIProfiles();return;}
  persistAPIConfig();activeProvider=['default','deepseek','glm','custom'].includes(profile.config.provider)?profile.config.provider:'custom';
  const {apiKey,...safeConfig}=profile.config;apiPresets[activeProvider]=safeConfig;
  loadAPIPreset();$('#aiKey').value=apiSecrets.get(profileSecretIdentity(profile.id))||'';
  persistAPIConfig();$('#aiProfileName').value=profile.name;renderSavedAPIProfiles(profile.id);storeSavedAPIProfiles();
});
function removeProfileSecrets(id) {
  for(const identity of apiSecrets.keys()) {
    try {const parts=JSON.parse(identity);if(parts[0]==='profile'&&parts[1]===id) apiSecrets.delete(identity);} catch (_) {}
  }
}
$('#aiDeleteProfile').addEventListener('click',()=>{
  const id=$('#aiSavedProfile').value,profile=savedAPIProfiles.find(p=>p.id===id);
  if(profile && confirm(`删除接口配置“${profile.name}”及其 API Key？不会删除健康记录。`)) {
    try {
      removeProfileSecrets(id);apiSecrets.delete(previousAPIIdentity);$('#aiKey').value='';storeAPISecrets();
      savedAPIProfiles=savedAPIProfiles.filter(p=>p.id!==id);renderSavedAPIProfiles();storeSavedAPIProfiles();$('#aiProfileName').value='';updateAPIVisibility();
      $('#aiConfigStatus').textContent='接口配置及其 API Key 已删除。';
    } catch(error) {$('#aiConfigStatus').textContent=error.message;}
  }
});
const selectedAPIProfile=savedAPIProfiles.find(p=>p.id===apiPresets.selectedProfile);
renderSavedAPIProfiles(selectedAPIProfile?.id||'');
if(selectedAPIProfile) $('#aiProfileName').value=selectedAPIProfile.name;
