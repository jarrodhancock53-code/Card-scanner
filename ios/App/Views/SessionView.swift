import PhotosUI
import SwiftUI
import PackRipCore

struct SessionView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var data: DataStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var camera = CameraController()
    @State private var engine: ScanEngine?
    @State private var showSetPicker = false
    @State private var showRecap = false
    @State private var picking: PendingPick?
    @State private var editing: PulledCard?
    @State private var videoItem: PhotosPickerItem?

    var body: some View {
        Group {
            if let engine { content(engine) } else { ProgressView().task { setUp() } }
        }
        .navigationTitle("Session")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { Button("Recap") { showRecap = true } }
        }
        .sheet(isPresented: $showSetPicker) { SetPickerView { setId in startPack(setId) } }
        .sheet(isPresented: $showRecap) {
            NavigationStack {
                if let s = model.current { RecapView(session: s, isLive: true) { showRecap = false; if model.current == nil { dismiss() } } }
            }
        }
        .onDisappear { camera.stop() }
    }

    private func setUp() {
        let e = ScanEngine(model: model, data: data)
        camera.onFrame = { [weak e] f, t in e?.ingest(f, at: t) }
        engine = e
        camera.start()
        if let last = model.current?.packs.last { Task { await e.prepare(setId: last.setId) } } else { showSetPicker = true }
    }

    private func startPack(_ setId: String) {
        model.startPack(setId: setId)
        if let e = engine { Task { await e.prepare(setId: setId) } }
    }

    @ViewBuilder
    private func content(_ e: ScanEngine) -> some View {
        VStack(spacing: 0) {
            ZStack(alignment: .bottom) {
                if camera.authorized { CameraPreview(session: camera.session) }
                else { Color.black.overlay(Text("Camera access is off. Turn it on in Settings.").foregroundStyle(.white).padding()) }
                VStack(spacing: 6) {
                    if !e.index.isReady, e.index.setId != nil { ProgressView(value: e.index.progress).padding(.horizontal) }
                    Text(e.status).font(.footnote).padding(6).background(.ultraThinMaterial, in: Capsule())
                }.padding(8)
            }
            .frame(height: 300).clipped()

            controls(e)
            cardList(e)
        }
    }

    private func controls(_ e: ScanEngine) -> some View {
        VStack(spacing: 8) {
            Picker("Mode", selection: Binding(get: { e.mode }, set: { e.mode = $0 })) {
                ForEach(ScanEngine.Mode.allCases) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.segmented)
            HStack {
                switch e.mode {
                case .photo:
                    Button { e.shutter() } label: { Label("Scan card", systemImage: "camera.circle.fill").font(.title3) }
                        .buttonStyle(.borderedProminent)
                case .live:
                    Text("Flip cards one at a time into view.").font(.footnote).foregroundStyle(.secondary)
                case .video:
                    if let p = e.videoProgress { ProgressView(value: p) } else {
                        PhotosPicker(selection: $videoItem, matching: .videos) { Label("Choose a rip video", systemImage: "film") }
                            .buttonStyle(.borderedProminent)
                    }
                }
                Spacer()
                Button { camera.setFocusLocked(!camera.focusLocked) } label: { Image(systemName: camera.focusLocked ? "lock.fill" : "lock.open") }
                Button { camera.setTorch(!camera.torchOn) } label: { Image(systemName: camera.torchOn ? "flashlight.on.fill" : "flashlight.off.fill") }
            }
            HStack {
                Button("New pack") { showSetPicker = true }
                Button("Code card") { if let s = model.current?.packs.last?.setId { e.addCodeCard(setId: s) } }
                Spacer()
                if let i = model.currentPackIndex { Text("Pack \(i + 1) of \(model.current?.packCount ?? 0)").font(.footnote).foregroundStyle(.secondary) }
            }.buttonStyle(.bordered)
        }
        .padding(10)
        .onChange(of: videoItem) { _, item in
            guard let item else { return }
            Task {
                if let movie = try? await item.loadTransferable(type: VideoFile.self) { await e.processVideo(url: movie.url) }
                videoItem = nil
            }
        }
    }

    private func cardList(_ e: ScanEngine) -> some View {
        List {
            if !e.pending.isEmpty {
                Section("Needs your pick") {
                    ForEach(e.pending) { p in
                        Button { picking = p } label: {
                            HStack {
                                Image(decorative: p.crop, scale: 1).resizable().scaledToFit().frame(height: 56)
                                Text("Tap to choose the card").foregroundStyle(.orange)
                            }
                        }
                        .swipeActions { Button("Skip", role: .destructive) { e.dismissPending(p) } }
                    }
                }
            }
            Section("This pack") {
                let cards = model.current?.packs.last?.cards ?? []
                if cards.isEmpty { Text("No cards yet").foregroundStyle(.secondary) }
                ForEach(cards.reversed()) { c in
                    Button { editing = c } label: { CardRow(card: c) }.tint(.primary)
                        .swipeActions { Button("Delete", role: .destructive) { model.remove(cardID: c.id) } }
                }
            }
        }
        .sheet(item: $picking) { p in
            CorrectionSheet(setId: model.current?.packs.last?.setId ?? "", candidates: p.candidateIds, guess: p.guess) { id, printing in
                e.resolvePending(p, cardId: id, printing: printing)
            }
        }
        .sheet(item: $editing) { c in
            CorrectionSheet(setId: c.setId, candidates: [c.cardId], guess: c.printing) { id, printing in
                e.recorrect(c, cardId: id, printing: printing)
            }
        }
    }
}

struct VideoFile: Transferable {
    let url: URL
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { file in SentTransferredFile(file.url) } importing: { received in
            let dest = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mov")
            try FileManager.default.copyItem(at: received.file, to: dest)
            return VideoFile(url: dest)
        }
    }
}

struct CardRow: View {
    let card: PulledCard
    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(card.name).font(.body)
                Text([card.number, card.rarity, card.printing?.label ?? (card.valueHigh > card.value ? "printing unclear" : "")]
                    .filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if card.flagged { Image(systemName: "flag.fill").foregroundStyle(.orange) }
            VStack(alignment: .trailing) {
                Text(Recapper.money(card.value)).monospacedDigit()
                if card.valueHigh > card.value { Text("to \(Recapper.money(card.valueHigh))").font(.caption2).foregroundStyle(.secondary) }
            }
        }
    }
}
