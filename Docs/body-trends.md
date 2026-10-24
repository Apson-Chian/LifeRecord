# 身体趋势统计口径

本文件描述 iOS 客户端的统计实现；安卓当前差异见 [Android/README.md](../Android/README.md)。

每次测量按原时间完整保存；趋势不会覆盖、合并或删除原始记录。

- 以设备本地日历分日，体重、体脂分别取当日所有有效值的中位数。偶数条取中间两条均值；缺失体脂不补零。中位数是本项目针对日内多次测量的选择，不能消除测量时间、水分或设备误差。
- 每日代表值只进入趋势一次，避免测量频繁的一天被重复加权。
- 指数平滑：`trend = previous + (1 - 0.9^days) * (median - previous)`；第一天以中位数初始化。连续日的新值权重为 10%，间隔以日历天数计算。缺测不制造新数据点，图表连线不代表期间实际测量。
- 先用全部历史计算趋势，再截取 7 天、30 天或全部，所以切换范围不会改变相同日期的趋势值。
- 体重和体脂使用独立序列；趋势首页展示每日中位数；每个项目有独立详情入口。体重、体脂详情支持全部、早上（05–12 时）、下午（12–18 时）、晚上（18–24 时）、凌晨（00–05 时），筛选原始测量后重新计算每日中位数，也可切换平滑趋势。明细保留筛选时段内的全部原始测量。
- iOS 与 Android：点击或横向拖动体重、体脂图表选中日期后，图表下方按时间从早到晚显示当日每次测量的时间与原始数值；也可点「查看当日每次测量」展开最近一天，点「收起详情」关闭。详情页的当日明细遵循所选测量时段，平滑开关不会改动原始数值；同一时间的多条记录也全部保留。
- AI 周报独立使用最近 7 个日历日（含今天）的数据，不受图表范围影响。身体组成的脂肪量、瘦体重仍使用同一次原始测量中的体重与体脂，避免混配不同时间的数值。

## 参考

- [The Hacker’s Diet：Exponentially smoothed moving averages](https://www.fourmilab.ch/hackdiet/www/subsubsection1_4_1_0_8_3.html)：递推公式与 10% 新值权重。
- [Libra：What is a trend?](https://libra-app.eu/support/trend/)：根据记录时间间隔调整指数平滑的思路。该页面显示的指数公式缺少负号，本项目没有照抄，采用上面的有界权重公式。
- [openScale](https://github.com/oliexdev/openScale)：保留带时间的身体测量、图表展示与按需展示指标的产品参考；本项目未复制其源码。

## 验证

`swiftc iOS/LifeRecord/Services/BodyTrend.swift iOS/Tests/body-trend.swift -o /tmp/body-trend-tests && /tmp/body-trend-tests`

覆盖乱序输入、同日多次测量、异常值中位数、偶数中位数、单点初始化、缺测、跨日间隔和本地时区分组。

当日测量回归还覆盖本地午夜边界、同一时间的多条测量、按时间排序，以及筛选时段后保留每次原始测量。Android `AnalysisTest` 验证相同的分日规则；`AppFlowTest.selectingWeightDayShowsEveryMeasurementOnOverviewAndFilteredDetail` 验证趋势首页点击、三次测量可见、收起与重新展开，以及详情页早上筛选和平滑趋势下的原始值。
