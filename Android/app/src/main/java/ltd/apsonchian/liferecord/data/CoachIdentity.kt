package ltd.apsonchian.liferecord.data

data class CoachIdentity(val name: String = "AI 助手", val avatar: ByteArray? = null) {
    companion object {
        fun validated(name: String, avatar: ByteArray?): CoachIdentity {
            val trimmed = name.trim()
            require(trimmed.isNotEmpty() && trimmed.codePointCount(0, trimmed.length) <= 30 && trimmed.none { Character.isISOControl(it) }) { "请填写 1–30 个字的教练名称，不包含换行。" }
            require((avatar?.size ?: 0) <= 512_000) { "头像过大，请重新选择照片。" }
            return CoachIdentity(trimmed, avatar)
        }
    }
}
