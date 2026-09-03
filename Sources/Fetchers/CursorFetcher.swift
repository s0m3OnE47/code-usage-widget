import Foundation

struct CursorFetcher: UsageFetcher {
    let providerID: ProviderID = .cursor

    private struct PeriodUsage: Decodable {
        struct PlanUsage: Decodable {
            let includedSpend: Int?
            let bonusSpend: Int?
            let remaining: Int?
            let limit: Int?
            let totalPercentUsed: Double?
            let autoPercentUsed: Double?
            let apiPercentUsed: Double?
        }
        let billingCycleStart: String?
        let billingCycleEnd: String?
        let planUsage: PlanUsage?
        let displayMessage: String?
        let autoModelSelectedDisplayMessage: String?
        let namedModelSelectedDisplayMessage: String?
    }

    private struct PlanInfoResp: Decodable {
        struct Info: Decodable {
            let planName: String?
        }
        let planInfo: Info?
    }

    func fetch(config: WidgetConfig) async -> ProviderUsage {
        guard let token = await CursorTokenReader.extractAccessToken() else {
            return .error(.cursor, message: "Open Cursor and sign in")
        }

        do {
            let usage: PeriodUsage = try await HTTPClient.postJSON(
                url: "https://api2.cursor.sh/aiserver.v1.DashboardService/GetCurrentPeriodUsage",
                headers: ["Authorization": "Bearer \(token)"]
            )

            var planName = "Cursor"
            if let info: PlanInfoResp = try? await HTTPClient.postJSON(
                url: "https://api2.cursor.sh/aiserver.v1.DashboardService/GetPlanInfo",
                headers: ["Authorization": "Bearer \(token)"]
            ), let name = info.planInfo?.planName {
                planName = name
            }

            let pu = usage.planUsage
            let includedCents = Double(pu?.includedSpend ?? 0)
            let limitCents = Double(pu?.limit ?? 0)
            let bonusCents = Double(pu?.bonusSpend ?? 0)
            let remainingCents = pu?.remaining.map(Double.init)

            let includedUSD = includedCents / 100
            let limitUSD = max(limitCents / 100, 0.01)
            let remainingUSD = remainingCents.map { $0 / 100 }
            let computedRemaining = max(limitUSD - includedUSD, 0)

            // Use numeric API fields — displayMessage can be stale/wrong (e.g. shows 80%
            // while totalPercentUsed is ~4%, which matches cursor.com dashboard).
            let totalPercent = pu?.totalPercentUsed ?? 0
            let autoPercent = pu?.autoPercentUsed ?? totalPercent
            let otherPercent = pu?.apiPercentUsed ?? 0

            var status: UsageStatus = .ok
            if totalPercent >= 100 { status = .limited }
            else if totalPercent >= 80 { status = .nearLimit }

            let cycleEnd = HTTPClient.parseUnixMs(usage.billingCycleEnd)
            let daysLeft = cycleEnd.map { max(0, Int(ceil($0.timeIntervalSinceNow / 86400))) }

            var subtitleParts: [String] = [planName]
            if let daysLeft {
                subtitleParts.append("\(daysLeft)d left in cycle")
            } else if let reset = cycleEnd {
                subtitleParts.append(HTTPClient.formatReset(reset))
            }
            if bonusCents > 0 {
                subtitleParts.append("\(HTTPClient.formatUSD(bonusCents / 100)) bonus")
            }

            let metricLabel: String
            if let remainingUSD, remainingUSD > 0, limitCents > 0 {
                metricLabel = "\(HTTPClient.formatUSD(remainingUSD)) left · \(Int(totalPercent))%"
            } else if computedRemaining > 0, limitCents > 0 {
                metricLabel = "\(HTTPClient.formatUSD(computedRemaining)) left · \(Int(totalPercent))%"
            } else {
                metricLabel = "\(Int(totalPercent))% used · \(HTTPClient.formatUSD(includedUSD)) / \(HTTPClient.formatUSD(limitUSD))"
            }

            let subMetrics: [UsageSubMetric] = [
                UsageSubMetric(id: "auto", label: "Auto / Cursor Models", percent: autoPercent),
                UsageSubMetric(id: "other", label: "Other Models", percent: otherPercent),
            ]

            return ProviderUsage(
                id: .cursor,
                status: status,
                used: totalPercent,
                limit: 100,
                unit: "%",
                subtitle: subtitleParts.joined(separator: " · "),
                metricLabel: metricLabel,
                resetsAt: cycleEnd,
                errorMessage: nil,
                isRefreshing: false,
                subMetrics: subMetrics
            )
        } catch {
            return .error(.cursor, message: "Cursor API error")
        }
    }
}
