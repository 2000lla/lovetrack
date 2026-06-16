import Foundation
import CoreLocation
import SwiftUI

/// 轨迹回放视图。
///
/// 数据流：ViewModel 拉取当天 `TrackSegment` → 显示折线 + 时间轴拖动。
public struct TrackPlaybackView: View {
    @ObservedObject var viewModel: TrackPlaybackViewModel

    public init(viewModel: TrackPlaybackViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(spacing: 0) {
            dateBar
            Divider()
            mapArea
            Divider()
            timelineArea
        }
        .task {
            await viewModel.load()
        }
    }

    // MARK: - 横向日期选择

    private var dateBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(viewModel.availableDates, id: \.self) { date in
                    dateChip(date)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }

    private func dateChip(_ date: Date) -> some View {
        let isSelected = Calendar.current.isDate(date, inSameDayAs: viewModel.selectedDate)
        return Button {
            Task { await viewModel.selectDate(date) }
        } label: {
            VStack(spacing: 2) {
                Text(date, format: .dateTime.day())
                    .font(.headline)
                Text(date, format: .dateTime.weekday(.short))
                    .font(.caption2)
            }
            .frame(width: 44, height: 48)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? Color.purple.opacity(0.15) : Color.gray.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.purple : Color.clear, lineWidth: 1.5)
            )
            .foregroundStyle(isSelected ? Color.purple : Color.primary)
        }
    }

    // MARK: - 地图区

    private var mapArea: some View {
        MapView(
            center: viewModel.currentCoordinate ?? CLLocationCoordinate2D(latitude: 36.6512, longitude: 117.1201),
            annotations: viewModel.annotations,
            polyline: viewModel.polyline,
            showsUserLocation: false
        )
        .frame(maxWidth: .infinity)
    }

    // MARK: - 时间轴

    private var timelineArea: some View {
        VStack(spacing: 8) {
            HStack {
                Text(viewModel.currentTime, style: .time)
                    .font(.headline.monospacedDigit())
                Spacer()
                Text(String(format: "%.1f km", viewModel.totalDistanceKm))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Slider(
                value: Binding(
                    get: { viewModel.playheadFraction },
                    set: { fraction in
                        Task { await viewModel.setPlayhead(fraction: fraction) }
                    }
                ),
                in: 0...1
            )
            .tint(.purple)
        }
        .padding(16)
    }
}

@MainActor
public final class TrackPlaybackViewModel: ObservableObject {
    @Published public private(set) var availableDates: [Date] = []
    @Published public var selectedDate: Date = Calendar.current.startOfDay(for: Date())
    @Published public private(set) var currentTime: Date = Date()
    @Published public private(set) var polyline: [CLLocationCoordinate2D] = []
    @Published public private(set) var annotations: [MapView.Annotation] = []
    @Published public private(set) var totalDistanceKm: Double = 0
    @Published public private(set) var playheadFraction: Double = 0
    @Published public private(set) var currentCoordinate: CLLocationCoordinate2D? = nil

    private let sync: RealtimeSyncServiceProtocol
    private var currentSegment: TrackSegment?

    public init(sync: RealtimeSyncServiceProtocol) {
        self.sync = sync
    }

    public func load() async {
        // 简化：列出最近 7 天
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        availableDates = (0..<7).compactMap { offset -> Date? in
            cal.date(byAdding: .day, value: -offset, to: today)
        }
        await selectDate(selectedDate)
    }

    public func selectDate(_ date: Date) async {
        selectedDate = Calendar.current.startOfDay(for: date)
        let seg = try? await sync.fetchTrackSegment(userId: "me", date: selectedDate)
        currentSegment = seg
        polyline = seg?.points.map {
            CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon)
        } ?? []
        annotations = (seg?.points.first.map { p in
            MapView.Annotation(
                id: "start",
                coordinate: .init(latitude: p.lat, longitude: p.lon),
                title: "起点",
                iconSystemName: "flag.circle.fill"
            )
        }).map { [$0] } ?? []
        totalDistanceKm = (seg?.summary.distanceMeters ?? 0) / 1000
        playheadFraction = 0
        currentTime = seg?.startedAt ?? selectedDate
    }

    public func setPlayhead(fraction: Double) async {
        playheadFraction = max(0, min(1, fraction))
        guard let seg = currentSegment, !seg.points.isEmpty else { return }
        let idx = Int(Double(seg.points.count - 1) * playheadFraction)
        let p = seg.points[idx]
        currentTime = p.timestamp
    }
}
