package ltd.apsonchian.liferecord.data

/** Same user intents and uncertainty rules as the iOS meal entry flow. */
enum class MealScanMode(val title: String, val instruction: String) {
    MEAL("餐盘识别", "多张图片可能是同一餐的不同角度。合并判断，不要重复计算同一食物；结合实际食用量估算整餐份量。"),
    NUTRITION_LABEL("营养成分表", "优先读取包装上的每份或每100g含量、每包装份数和用户实际食用量，正确换算，不能把每100g直接当整份。看不清的数字不要编造；实际食用量未知时说明按什么份量估算。"),
    INGREDIENTS("配料表", "图片是配料表或外包装。识别配料、过敏原及高糖高钠信息；缺少营养成分表或份量时只能给出宽范围估算并说明不确定性，不编造精确营养值。"),
}
