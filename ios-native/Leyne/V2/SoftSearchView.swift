// SoftSearchView — Leyne 2.0 Search: pill input + filter chips + result rows.

import SwiftUI

enum SearchFilter: Hashable { case postal, stopID, busNo, place }

struct SoftSearchView: View {
    @EnvironmentObject var m: AppModel
    @EnvironmentObject var fb: Feedback
    @EnvironmentObject var ds: DataStore

    @State private var query = ""
    @State private var filter: SearchFilter = .stopID
    let onClose: () -> Void
    let onOpenStop: (String) -> Void

    @FocusState private var focused: Bool

    private var t: Theme { m.t }

    var body: some View {
        ZStack {
            t.bg.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 16) {
                searchBar
                SortChipRow(t: t, selection: $filter, options: [
                    (.postal, "Postal"),
                    (.stopID, "Stop ID"),
                    (.busNo, "Bus #"),
                    (.place, "Place"),
                ])

                if !query.isEmpty {
                    Text(detectedLine)
                        .font(t.mono(11))
                        .foregroundStyle(t.dim)
                }

                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(resolvedStops, id: \.BusStopCode) { stop in
                            resultRow(stop: stop)
                        }
                    }
                    .padding(.top, 4)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
        }
        .onAppear { focused = true }
    }

    private var searchBar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14))
                    .foregroundStyle(t.dim)
                TextField("Postal · Stop ID · Bus# · Place",
                          text: $query)
                    .font(t.mono(14))
                    .foregroundStyle(t.fg)
                    .focused($focused)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                if !query.isEmpty {
                    Button {
                        query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(t.dim)
                    }.buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(t.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            Button {
                fb.select()
                onClose()
            } label: {
                Text("Cancel")
                    .font(t.sans(14, weight: .medium))
                    .foregroundStyle(t.accent)
            }.buttonStyle(.plain)
        }
    }

    private var resolvedStops: [LTABusStop] {
        guard !query.isEmpty else { return [] }
        switch filter {
        case .stopID:
            // direct stop-code prefix match, then broader name search
            let exact = ds.searchStops(query)
            return exact
        case .postal:
            // For now fall back to name search; postal-code geocoding is in
            // SearchLogic.swift and is wired through AppModel's openFromSearch.
            return ds.searchStops(query)
        case .busNo:
            // Convert services → list of origin stops for now
            return ds.searchStops(query)
        case .place:
            return ds.searchStops(query)
        }
    }

    private var detectedLine: String {
        switch filter {
        case .postal: return "Postal · \(query)"
        case .stopID: return "Stop · \(query)"
        case .busNo:  return "Bus · \(query)"
        case .place:  return "Place · \(query)"
        }
    }

    private func resultRow(stop: LTABusStop) -> some View {
        Button {
            fb.select()
            m.addRecent(query)
            onOpenStop(stop.BusStopCode)
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(stop.Description)
                        .font(t.sans(14, weight: .semibold))
                        .foregroundStyle(t.fg)
                        .lineLimit(2)
                    Text("Stop \(stop.BusStopCode) · \(stop.RoadName)")
                        .font(t.mono(11))
                        .foregroundStyle(t.dim)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(t.dim)
            }
            .padding(14)
            .background(t.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .pressScale()
    }
}
