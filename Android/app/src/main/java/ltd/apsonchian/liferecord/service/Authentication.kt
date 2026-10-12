package ltd.apsonchian.liferecord.service

import java.net.URI

object AIAuthentication {
    fun officialDeepSeek(endpoint:String):Boolean = runCatching {
        val url=URI(endpoint.trim())
        url.scheme.equals("https",true) && url.host.equals("api.deepseek.com",true) && url.port in listOf(-1,443)
    }.getOrDefault(false)
    fun normalizedKey(raw:String,bearer:Boolean):String {
        var key=raw.trim()
        if(bearer) {
            if(key.startsWith("Authorization:",true)) key=key.substring("Authorization:".length).trim()
            if(key.startsWith("Bearer ",true)) key=key.substring(7).trim()
            if(key.length>=2 && ((key.first()=='"' && key.last()=='"') || (key.first()=='\'' && key.last()=='\''))) key=key.substring(1,key.length-1)
        }
        require(key.isNotEmpty()) { "API Key 不能为空" }
        require(key.all { it.code in 33..126 }) { "API Key 含空格、换行或不可见字符，请重新粘贴完整密钥" }
        require(!key.contains("***")) { "粘贴的是被隐藏的密钥，请重新复制完整 API Key" }
        return key
    }
    data class Credential(val header:String,val key:String,val bearer:Boolean)
    fun credential(endpoint:String,style:String,customHeader:String,raw:String):Credential {
        val bearer=officialDeepSeek(endpoint) || style=="Bearer"
        val key=normalizedKey(raw,bearer)
        val header=if(bearer) "Authorization" else if(style=="api-key") "api-key" else customHeader.trim()
        require(header.isNotBlank() && header.all { it.code in 33..126 && it !in "()<>@,;:\\\"/[]?={} \t" }) { "自定义认证请求头名称无效" }
        return Credential(header,key,bearer)
    }
    fun deepSeekFailure(status:Int):String? = when(status) {
        401 -> "DeepSeek 鉴权失败（HTTP 401）。已使用官方 Bearer 认证；请在 platform.deepseek.com 创建或重新复制完整 API Key，保存并测试。网页登录凭证、已删除密钥和其他平台的密钥不能用于官方接口。"
        402 -> "DeepSeek 余额不足（HTTP 402）。请在 platform.deepseek.com 核对 API 账户余额。"
        else -> null
    }
}
