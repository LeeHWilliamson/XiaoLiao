import SwiftUI
import Charts

struct StatisticsDashboardView: View {
    let conversation: ConversationViewModel
    let onBack: () -> Void
    @State private var dashboard: StatisticsDashboardModel
    @Environment(\.scenePhase) private var scenePhase
    @ScaledMetric(relativeTo: .largeTitle) private var titleSize: CGFloat = 34
    @ScaledMetric(relativeTo: .body) private var chartHeight: CGFloat = 235

    init(conversation: ConversationViewModel, onBack: @escaping () -> Void) {
        self.conversation = conversation
        self.onBack = onBack
        _dashboard = State(initialValue: StatisticsDashboardModel())
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                ArtworkButton(label: "返回", glyph: .backGlyph, ring: .backRing, action: onBack)
                    .accessibilityIdentifier("stats.back")
                VStack(alignment: .leading, spacing: 4) {
                    Text("学习统计")
                        .font(.system(size: titleSize, weight: .bold))
                        .accessibilityAddTraits(.isHeader)
                    Text("全部对话 · 累计学习记录").font(.subheadline)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    switch dashboard.state {
                    case .loading:
                        ProgressView("正在整理学习记录…")
                            .frame(maxWidth: .infinity, minHeight: 200)
                            .accessibilityIdentifier("stats.loading")
                    case .failed:
                        StatisticsCard(title: "暂时无法读取统计") {
                            Text("已有学习记录仍被保留，请稍后重试。")
                            Button("重试") {
                                Task {
                                    conversation.retryLoadingHistory()
                                    await load()
                                }
                            }
                            .buttonStyle(.bordered)
                            .tint(XiaoLiaoTheme.ink)
                            .frame(minHeight: 44)
                            .accessibilityIdentifier("stats.retry")
                        }
                    case let .loaded(snapshot):
                        dashboardContent(snapshot)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 36)
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
            }
        }
        .background { PaperBackground() }
        .foregroundStyle(XiaoLiaoTheme.ink)
        .toolbar(.hidden, for: .navigationBar)
        .accessibilityIdentifier("stats.screen")
        .task { await load() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await load() } }
        }
        .onChange(of: conversation.grammarStatisticsRevision) { _, _ in
            Task { await load() }
        }
    }

    private func load() async {
        await dashboard.load {
            try await conversation.statisticsSnapshot()
        }
    }

    @ViewBuilder
    private func dashboardContent(_ snapshot: StatisticsSnapshot) -> some View {
        if snapshot.overall.textAnalyzedAttempts == 0 && snapshot.overall.grammarEvaluatedAttempts == 0 {
            Text("暂时还没有学习分析数据。这里会展示全部对话的学习记录。")
                .font(.callout)
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(XiaoLiaoTheme.prompt.opacity(0.65), in: RoundedRectangle(cornerRadius: 16))
                .accessibilityIdentifier("stats.empty")
        }

        StatisticsCard(title: "语法", subtitle: "点击横条，查看该项的每日准确率") {
            GrammarProficiencyChart(metrics: dashboard.grammarMetrics, selection: $dashboard.selectedCategory)
            Text("已评估 \(snapshot.overall.grammarEvaluatedAttempts) / \(snapshot.overall.practiceAttempts) 次练习；不确定的机会不计入准确率。")
                .font(.caption)
            Text("AI 语法分析 · 根据本条消息的上下文判断")
                .font(.caption)
            if conversation.pendingGrammarCount > 0 || conversation.failedGrammarCount > 0 {
                Text("待分析 \(conversation.pendingGrammarCount) 条 · 未完成 \(conversation.failedGrammarCount) 条")
                    .font(.caption)
                    .accessibilityIdentifier("stats.grammar.queue")
            }
            if let issue = conversation.grammarQueueIssue {
                Text(issue).font(.callout)
            } else if let failure = conversation.grammarFailureMessage {
                Text(failure).font(.callout)
            }
            if conversation.failedGrammarCount > 0 || conversation.grammarQueueIssue != nil {
                Text("分析失败不会影响聊天，也不会计为语法错误。")
                    .font(.caption)
                Button("重试语法分析") { conversation.retryFailedGrammarEvaluations() }
                    .buttonStyle(.bordered)
                    .tint(XiaoLiaoTheme.ink)
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("stats.grammar.retry")
            }
        }

        StatisticsCard(title: "\(dashboard.selectedCategory.title) · 趋势", subtitle: "每日正确机会 ÷ 当日已确定结果的机会") {
            Text(dashboard.selectedMetric?.accuracy.map { "累计准确率 \($0.formatted(.percent.precision(.fractionLength(0))))" } ?? "尚无可用的评估结果")
                .font(.subheadline.weight(.semibold))
            StatisticsLineChart(points: dashboard.grammarTrend, dates: dashboard.dateDomain, format: .accuracy,
                                emptyMessage: "暂无该项的趋势数据", identifier: "stats.grammar.trend")
                .accessibilityLabel("\(dashboard.selectedCategory.title)，每日准确率")
            Text("\(dashboard.selectedCategory.title)每日准确率")
                .font(.caption)
                .accessibilityIdentifier("stats.grammar.selected")
        }

        StatisticsCard(title: "词汇多样性", subtitle: "MATTR · 每日记录") {
            Text(snapshot.overall.mattr.map { "累计 MATTR \($0.formatted(.number.precision(.fractionLength(2))))" } ?? "累计 MATTR —")
                .font(.subheadline.weight(.semibold))
            StatisticsLineChart(points: dashboard.vocabularyTrend, dates: dashboard.dateDomain, format: .diversity,
                                emptyMessage: "词数足够时显示多样性趋势", identifier: "stats.vocabulary.diversity")
            Text("每个窗口 \(snapshot.configuration.mattrWindowSize) 个词。当天已分析词数不足时不显示分数；重复使用的词仍计入。")
                .font(.caption)
        }

        StatisticsCard(title: "新观察到的词汇", subtitle: "首次在你的练习中出现的词形 · 按日统计") {
            vocabularyChart
            Text("按首次使用时间记录，不代表刚刚学会。run、runs、running 分别统计。")
                .font(.caption)
        }

        StatisticsCard(title: "练习量", subtitle: "已有分析的累计结果") {
            activityTable(snapshot.overall)
            Text("句子已分析 \(snapshot.overall.textAnalyzedAttempts) / \(snapshot.overall.practiceAttempts) 次练习；分句已分析 \(snapshot.overall.clauseAnalyzedAttempts) / \(snapshot.overall.practiceAttempts) 次。平均值仅使用有分句分析的句子。")
                .font(.caption)
            Text("— 表示尚无分析结果。每次发送和编辑都计为一次练习。")
                .font(.caption)
        }
    }

    private var vocabularyChart: some View {
        Chart(dashboard.newVocabulary) { point in
            BarMark(x: .value("日期", point.date, unit: .day), y: .value("新词数", point.count))
                .foregroundStyle(XiaoLiaoTheme.green)
                .cornerRadius(4)
                .accessibilityLabel(Text(point.date, format: .dateTime.year().month().day()))
                .accessibilityValue(Text("\(point.count) 个新词"))
        }
        .chartXScale(domain: dashboard.dateDomain)
        .chartYScale(domain: 0...(dashboard.wordAxisTicks.last ?? 1))
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine().foregroundStyle(XiaoLiaoTheme.ink.opacity(0.12))
                AxisValueLabel(format: .dateTime.year(.twoDigits).month(.defaultDigits).day())
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: dashboard.wordAxisTicks) { _ in
                AxisGridLine().foregroundStyle(XiaoLiaoTheme.ink.opacity(0.15))
                AxisValueLabel()
            }
        }
        .chartXAxisLabel("日期")
        .chartYAxisLabel("词数")
        .frame(height: chartHeight)
        .overlay {
            if dashboard.newVocabulary.isEmpty { chartEmptyMessage("暂无新词记录") }
        }
        .accessibilityLabel("每日新观察到的词汇数量")
        .accessibilityIdentifier("stats.vocabulary.new")
    }

    private func activityTable(_ statistics: PracticeStatistics) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 14) {
            GridRow {
                Text("指标").frame(maxWidth: .infinity, alignment: .leading)
                Text("数值")
            }
            .font(.subheadline.bold())
            Divider().overlay(XiaoLiaoTheme.ink.opacity(0.3)).gridCellColumns(2)
            activityRow("句子数", value: statistics.sentenceCount.map { $0.formatted() } ?? "—", id: "sentences")
            activityRow("分句数", value: statistics.clauseCount.map { $0.formatted() } ?? "—", id: "clauses")
            activityRow("平均每句分句数", value: statistics.clausesPerSentence.map {
                $0.formatted(.number.precision(.fractionLength(2)))
            } ?? "—", id: "clausesPerSentence")
        }
        .accessibilityIdentifier("stats.activity")
    }

    private func activityRow(_ title: String, value: String, id: String) -> some View {
        GridRow {
            Text(title)
            Text(value).monospacedDigit().gridColumnAlignment(.trailing)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("stats.activity.\(id)")
    }
}

/// Aligned native button rows form the horizontal chart. The whole bar row is a
/// 44+ point target, including zero/missing values, with equivalent VoiceOver actions.
private struct GrammarProficiencyChart: View {
    let metrics: [GrammarMetricSummary]
    @Binding var selection: GrammarObservation.TrackedCategory
    @ScaledMetric(relativeTo: .subheadline) private var labelWidth: CGFloat = 84
    @ScaledMetric(relativeTo: .subheadline) private var valueWidth: CGFloat = 48
    @ScaledMetric(relativeTo: .subheadline) private var rowHeight: CGFloat = 58
    @ScaledMetric(relativeTo: .caption) private var axisHeight: CGFloat = 54
    @ScaledMetric(relativeTo: .caption2) private var minimumPlotWidth: CGFloat = 100

    var body: some View {
        GeometryReader { geometry in
            ScrollView(.horizontal) {
                VStack(spacing: 0) {
                    ForEach(metrics, id: \.category.rawValue) { metric in
                        Button { selection = metric.category } label: {
                            HStack(spacing: 10) {
                                Text(metric.category.title)
                                    .font(.subheadline.weight(selection == metric.category ? .bold : .regular))
                                    .frame(width: labelWidth, alignment: .leading)
                                GeometryReader { plot in
                                    ZStack(alignment: .leading) {
                                        Capsule().fill(XiaoLiaoTheme.prompt)
                                        if let accuracy = metric.accuracy {
                                            Capsule().fill(XiaoLiaoTheme.green.opacity(selection == metric.category ? 1 : 0.55))
                                                .frame(width: plot.size.width * accuracy)
                                        }
                                    }
                                }
                                .frame(height: 22)
                                Text(metric.accuracy.map { $0.formatted(.percent.precision(.fractionLength(0))) } ?? "—")
                                    .font(.subheadline.weight(.semibold)).monospacedDigit()
                                    .frame(width: valueWidth, alignment: .trailing)
                            }
                            .frame(minHeight: max(44, rowHeight))
                            .contentShape(Rectangle())
                            .padding(.horizontal, 4)
                            .background(selection == metric.category ? XiaoLiaoTheme.green.opacity(0.09) : .clear,
                                        in: RoundedRectangle(cornerRadius: 10))
                            .overlay {
                                RoundedRectangle(cornerRadius: 10)
                                    .strokeBorder(selection == metric.category ? XiaoLiaoTheme.ink : .clear, lineWidth: 1)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(metric.category.title)
                        .accessibilityValue(metric.accuracy.map {
                            "准确率 \($0.formatted(.percent.precision(.fractionLength(0))))，\(metric.scoredOpportunities) 次机会"
                        } ?? "暂无确定结果")
                        .accessibilityHint("轻点查看这一项的准确率趋势")
                        .accessibilityAddTraits(selection == metric.category ? .isSelected : [])
                        .accessibilityIdentifier("stats.grammar.category.\(metric.category.rawValue)")
                    }
                    HStack(spacing: 10) {
                        Color.clear.frame(width: labelWidth, height: 1)
                        ZStack {
                            HStack {
                                Text("0%")
                                Spacer(minLength: 0)
                                Text("100%")
                            }
                            Text("50%")
                        }
                        Color.clear.frame(width: valueWidth, height: 1)
                    }
                    .font(.caption2)
                    .padding(.horizontal, 4)
                    .padding(.top, 8)
                    Text("准确率（%）").font(.caption).padding(.top, 4)
                }
                .frame(width: max(geometry.size.width, labelWidth + valueWidth + minimumPlotWidth + 28))
            }
        }
        .frame(height: max(44, rowHeight) * CGFloat(metrics.count) + axisHeight)
        .accessibilityIdentifier("stats.grammar.comparison")
    }
}

private struct StatisticsLineChart: View {
    enum ValueFormat: Equatable {
        case accuracy, diversity
        var axisTitle: String { self == .accuracy ? "准确率" : "MATTR" }
        func label(_ value: Double) -> String {
            self == .accuracy ? value.formatted(.percent.precision(.fractionLength(0)))
                : value.formatted(.number.precision(.fractionLength(2)))
        }
    }
    let points: [StatisticsTrendPoint]
    let dates: ClosedRange<Date>
    let format: ValueFormat
    let emptyMessage: String
    let identifier: String
    @ScaledMetric(relativeTo: .body) private var chartHeight: CGFloat = 235

    var body: some View {
        Chart(points) { point in
            LineMark(x: .value("日期", point.date), y: .value(format.axisTitle, point.value),
                     series: .value("连续记录", point.segment))
                .foregroundStyle(XiaoLiaoTheme.green)
                .lineStyle(StrokeStyle(lineWidth: 3))
                .interpolationMethod(.linear)
                .accessibilityHidden(true)
            PointMark(x: .value("日期", point.date), y: .value(format.axisTitle, point.value))
                .foregroundStyle(XiaoLiaoTheme.green)
                .symbolSize(40)
                .accessibilityLabel(Text(point.date, format: .dateTime.year().month().day()))
                .accessibilityValue(Text(format.label(point.value)))
        }
        .chartXScale(domain: dates)
        .chartYScale(domain: 0.0...1.0)
        .chartLegend(.hidden)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine().foregroundStyle(XiaoLiaoTheme.ink.opacity(0.12))
                AxisValueLabel(format: .dateTime.year(.twoDigits).month(.defaultDigits).day())
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: [0.0, 0.25, 0.5, 0.75, 1.0]) { value in
                AxisGridLine().foregroundStyle(XiaoLiaoTheme.ink.opacity(0.15))
                AxisValueLabel { Text(format.label(value.as(Double.self) ?? 0)).font(.caption2) }
            }
        }
        .chartXAxisLabel("日期")
        .chartYAxisLabel(format.axisTitle)
        .frame(height: chartHeight)
        .overlay { if points.isEmpty { chartEmptyMessage(emptyMessage) } }
        .accessibilityIdentifier(identifier)
    }
}

private struct StatisticsCard<Content: View>: View {
    let title: String
    var subtitle: String? = nil
    let content: Content

    init(title: String, subtitle: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.title2.bold()).accessibilityAddTraits(.isHeader)
                if let subtitle { Text(subtitle).font(.caption) }
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(XiaoLiaoTheme.paper.opacity(0.9), in: RoundedRectangle(cornerRadius: 20))
        .overlay { RoundedRectangle(cornerRadius: 20).strokeBorder(XiaoLiaoTheme.ink.opacity(0.7), lineWidth: 1.5) }
    }
}

private func chartEmptyMessage(_ text: String) -> some View {
    Text(text)
        .font(.callout)
        .multilineTextAlignment(.center)
        .padding(12)
        .background(XiaoLiaoTheme.paper.opacity(0.95), in: RoundedRectangle(cornerRadius: 10))
        .padding(24)
        .allowsHitTesting(false)
}
