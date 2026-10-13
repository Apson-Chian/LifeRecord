/* Non-secret API preferences persist locally; all keys stay in page memory. */
const API_PREFS_KEY = 'liferecord.api-preferences.v2';
const apiDefaults = {model:'', endpoint:'', authMode:'bearer', authHeader:'', maxTokens:6000, tokenField:'max_tokens', temperature:.1, sendTemperature:true, jsonMode:false, extraParams:{}};
let apiPresets = {};
try { apiPresets = JSON.parse(localStorage.getItem(API_PREFS_KEY) || '{}'); if (!apiPresets || Array.isArray(apiPresets) || typeof apiPresets !== 'object') apiPresets={}; } catch (_) {}
let activeProvider = ['deepseek','glm','dots','custom'].includes(apiPresets.selected) ? apiPresets.selected : 'deepseek';
let apiSecrets = new Map();
let previousAPIIdentity = '';
const configInputs = ['aiModel','aiEndpoint','aiAuthMode','aiAuthHeader','aiMaxTokens','aiTokenField','aiTemperature','aiSendTemperature','aiJSONMode','aiExtraParams'];
function currentAPIIdentity(provider=activeProvider) { return JSON.stringify([provider, provider==='custom'?$('#aiEndpoint').value.trim():provider,$('#aiAuthMode').value,$('#aiAuthHeader').value.trim()]); }
function readAPIConfig() {
  let extraParams;
  try { extraParams=JSON.parse($('#aiExtraParams').value||'{}'); } catch (_) { throw new Error('额外参数必须是有效 JSON，例如 {"top_p":0.9}'); }
  if (!extraParams || Array.isArray(extraParams) || typeof extraParams !== 'object') throw new Error('额外参数必须为 JSON 对象');
  const blocked=['model','messages','stream','temperature','max_tokens','max_completion_tokens','response_format'];
  if(Object.keys(extraParams).some(key=>blocked.includes(key))) throw new Error('额外参数不能覆盖模型、消息和生成设置');
  return {provider:$('#aiProvider').value,model:$('#aiModel').value.trim(),endpoint:$('#aiEndpoint').value.trim(),authMode:$('#aiAuthMode').value,authHeader:$('#aiAuthHeader').value.trim(),apiKey:$('#aiKey').value,maxTokens:Number($('#aiMaxTokens').value),tokenField:$('#aiTokenField').value,temperature:Number($('#aiTemperature').value),sendTemperature:$('#aiSendTemperature').checked,jsonMode:$('#aiJSONMode').checked,extraParams};
}
function persistAPIConfig() {
  try {
    const {apiKey,...config}=readAPIConfig();
    apiSecrets.set(previousAPIIdentity,apiKey);
    const identity=currentAPIIdentity();
    if(identity!==previousAPIIdentity) {$('#aiKey').value=apiSecrets.get(identity)||'';previousAPIIdentity=identity;}
    apiPresets[activeProvider]={...config,provider:activeProvider};apiPresets.selected=activeProvider;
    localStorage.setItem(API_PREFS_KEY,JSON.stringify(apiPresets));
    $('#aiConfigStatus').textContent='';
  } catch (error) {$('#aiConfigStatus').textContent=error.message;}
  updateAPIVisibility();
}
function loadAPIPreset() {
  const config={...apiDefaults,...apiPresets[activeProvider]};
  if(!apiPresets[activeProvider] && activeProvider==='dots') config.authMode='api-key';
  $('#aiProvider').value=activeProvider;
  for(const [id,key] of [['aiModel','model'],['aiEndpoint','endpoint'],['aiAuthMode','authMode'],['aiAuthHeader','authHeader'],['aiMaxTokens','maxTokens'],['aiTokenField','tokenField'],['aiTemperature','temperature']]) $('#'+id).value=config[key];
  $('#aiSendTemperature').checked=config.sendTemperature;$('#aiJSONMode').checked=config.jsonMode;$('#aiExtraParams').value=JSON.stringify(config.extraParams||{},null,2);
  previousAPIIdentity=currentAPIIdentity();$('#aiKey').value=apiSecrets.get(previousAPIIdentity)||'';updateAPIVisibility();
}
function updateAPIVisibility() {
  $('#aiEndpointLabel').hidden=activeProvider!=='custom';$('#aiHeaderLabel').hidden=$('#aiAuthMode').value!=='custom';
  $('#aiTemperature').disabled=!$('#aiSendTemperature').checked;
  const name=$('#aiProvider').selectedOptions[0]?.textContent||'';
  $('#aiConfigSummary').textContent=`${name} · ${$('#aiModel').value.trim()||'请在设置中填写模型'} · 密钥仅本页使用`;
}
function clearAPISecrets() {apiSecrets.clear();$('#aiKey').value='';$('#aiConfigStatus').textContent='';}
$('#aiProvider').addEventListener('change',()=>{
  const next=$('#aiProvider').value;
  persistAPIConfig();activeProvider=next;loadAPIPreset();persistAPIConfig();
  pendingAIPlan=[];$('#aiApply').hidden=true;$('#aiPlan').replaceChildren();
});
for(const id of configInputs) $('#'+id).addEventListener('change',persistAPIConfig);
$('#aiKey').addEventListener('input',()=>apiSecrets.set(previousAPIIdentity,$('#aiKey').value));
$('#aiCheckConfig').addEventListener('click',async()=>{
  const generation=identityGeneration,button=$('#aiCheckConfig');button.disabled=true;$('#aiConfigStatus').textContent='正在检查…';
  try {const result=await api('/ai/config/check',{method:'POST',body:JSON.stringify(readAPIConfig())});if(generation===identityGeneration) $('#aiConfigStatus').textContent=result.message;}
  catch(error) {if(generation===identityGeneration) $('#aiConfigStatus').textContent=error.message;}
  finally {button.disabled=false;}
});
document.querySelectorAll('[data-open-settings]').forEach(button=>button.addEventListener('click',()=>{if(!connected)return showAuth();$('#settingsDialog').showModal();}));
loadAPIPreset();
