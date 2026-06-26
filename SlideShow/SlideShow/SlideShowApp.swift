import SwiftUI
import Photos
import AVKit

@main
struct SlideShowApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

struct MediaItem: Identifiable, Hashable {
    let id = UUID()
    let type: MediaType
    let assetId: String
    let thumb: UIImage?
    enum MediaType { case photo, video }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: MediaItem, rhs: MediaItem) -> Bool { lhs.id == rhs.id }
}

struct Album: Identifiable, Hashable {
    let id: String
    let name: String
    let collection: PHAssetCollection?
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: Album, rhs: Album) -> Bool { lhs.id == rhs.id }
}

struct ContentView: View {
    @State private var mediaItems: [MediaItem] = []
    @State private var selectedItems: Set<UUID> = []
    @State private var playing = false
    @State private var duration: Double = 3
    @State private var playMode = 0
    @State private var loopMode = 0
    @State private var albums: [Album] = []
    @State private var selectedAlbum: Album?
    @State private var sortReversed = false
    @State private var loading = false

    var body: some View {
        ZStack {
            if playing {
                SlideShowPlayer(
                    items: mediaItems.filter { selectedItems.contains($0.id) },
                    duration: duration, playMode: playMode, loopMode: loopMode,
                    onExit: { playing = false }
                )
            } else {
                NavigationStack {
                    VStack(spacing: 0) {
                        if mediaItems.isEmpty { emptyView } else { gridView }
                        bottomBar
                    }
                    .navigationTitle("幻灯片播放器")
                    .toolbar {
                        ToolbarItem(placement: .primaryAction) {
                            Menu {
                                ForEach(albums) { album in
                                    Button(album.name) {
                                        selectedAlbum = album
                                        loadAssets()
                                    }
                                }
                            } label: {
                                Label(selectedAlbum?.name ?? "相簿", systemImage: "photo.on.rectangle.angled")
                            }
                        }
                    }
                }
            }
        }.task { loadAlbums() }
    }

    var emptyView: some View {
        VStack(spacing: 16) {
            Image(systemName: "photo.on.rectangle.angled").font(.system(size: 48)).foregroundColor(.secondary)
            Text("点右上角选择相簿").foregroundColor(.secondary)
            if loading {
                ProgressView().padding()
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    var gridView: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 4)], spacing: 4) {
                ForEach(mediaItems) { item in
                    ZStack(alignment: .topLeading) {
                        if let img = item.thumb {
                            Image(uiImage: img).resizable().aspectRatio(1, contentMode: .fill)
                        } else {
                            Color.gray.opacity(0.25)
                        }
                        if item.type == .video {
                            Image(systemName: "play.fill").font(.caption).padding(3)
                                .background(.ultraThinMaterial).clipShape(Circle()).padding(4)
                        }
                        if selectedItems.contains(item.id) {
                            Image(systemName: "checkmark.circle.fill").foregroundColor(.purple)
                                .font(.title3).background(Circle().fill(.white)).padding(5)
                        }
                    }.clipped().onTapGesture {
                        if selectedItems.contains(item.id) { selectedItems.remove(item.id) }
                        else { selectedItems.insert(item.id) }
                    }.overlay(RoundedRectangle(cornerRadius: 0).stroke(selectedItems.contains(item.id) ? Color.purple : Color.clear, lineWidth: 3))
                }
            }.padding(4)
        }
    }

    var bottomBar: some View {
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                Button("全选") { selectedItems = Set(mediaItems.map(\.id)) }.font(.caption)
                Button("取消全选") { selectedItems = [] }.font(.caption)
                Button(sortReversed ? "↑" : "↓") { sortReversed.toggle(); mediaItems.reverse() }.font(.caption)
            }.padding(.leading, 12).buttonStyle(.borderless)
            HStack(spacing: 12) {
                HStack(spacing: 4) {
                    Text("每张").font(.caption).foregroundColor(.secondary)
                    Button(action: { if duration > 1 { duration -= 1 } }) {
                        Image(systemName: "minus.circle.fill").font(.title3).foregroundColor(.secondary)
                    }.buttonStyle(.plain)
                    Slider(value: $duration, in: 1...30, step: 1).frame(width: 80)
                    Button(action: { if duration < 30 { duration += 1 } }) {
                        Image(systemName: "plus.circle.fill").font(.title3).foregroundColor(.secondary)
                    }.buttonStyle(.plain)
                    Text("\(Int(duration))s").font(.caption).foregroundColor(.secondary).frame(width: 24)
                }
                Picker("", selection: $playMode) { Text("顺序").tag(0); Text("随机").tag(1) }.pickerStyle(.segmented).frame(width: 80)
                Picker("", selection: $loopMode) { Text("循环").tag(0); Text("一次").tag(1) }.pickerStyle(.segmented).frame(width: 80)
            }.frame(maxWidth: .infinity)
            Button(action: { playing = true }) {
                Label("播放 (\(selectedItems.count))", systemImage: "play.fill")
                    .font(.system(size: 14, weight: .semibold)).frame(width: 120, height: 32)
                    .background(selectedItems.isEmpty ? Color.gray.opacity(0.3) : Color.purple)
                    .foregroundColor(.white).clipShape(RoundedRectangle(cornerRadius: 8))
            }.disabled(selectedItems.isEmpty).buttonStyle(.plain).padding(.trailing, 12)
        }.frame(height: 50).background(.bar)
    }

    func loadAlbums() {
        PHPhotoLibrary.requestAuthorization { status in
            guard status == .authorized || status == .limited else { return }
            var result: [Album] = [Album(id: "all", name: "全部", collection: nil)]
            // User albums
            let userAlbums = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: nil)
            userAlbums.enumerateObjects { c, _, _ in
                result.append(Album(id: c.localIdentifier, name: c.localizedTitle ?? "无名称", collection: c))
            }
            // Smart albums
            let smartAlbums = PHAssetCollection.fetchAssetCollections(with: .smartAlbum, subtype: .any, options: nil)
            smartAlbums.enumerateObjects { c, _, _ in
                let includeTypes: [PHAssetCollectionSubtype] = [
                    .smartAlbumUserLibrary, .smartAlbumFavorites, .smartAlbumRecentlyAdded,
                    .smartAlbumSelfPortraits, .smartAlbumScreenshots, .smartAlbumVideos,
                    .smartAlbumLivePhotos, .smartAlbumPanoramas, .smartAlbumBursts
                ]
                if includeTypes.contains(c.assetCollectionSubtype) {
                    result.append(Album(id: c.localIdentifier, name: c.localizedTitle ?? "智能相簿", collection: c))
                }
            }
            DispatchQueue.main.async {
                albums = result
                if selectedAlbum == nil { selectedAlbum = result.first; loadAssets() }
            }
        }
    }

    func loadAssets() {
        loading = true
        DispatchQueue.global(qos: .userInitiated).async {
            let opts = PHFetchOptions()
            opts.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: !sortReversed)]
            opts.predicate = NSPredicate(format: "mediaType == %d OR mediaType == %d",
                                         PHAssetMediaType.image.rawValue, PHAssetMediaType.video.rawValue)
            let result: PHFetchResult<PHAsset>
            if let album = selectedAlbum?.collection {
                result = PHAsset.fetchAssets(in: album, options: opts)
            } else {
                result = PHAsset.fetchAssets(with: opts)
            }

            var items: [MediaItem] = []
            let mgr = PHImageManager.default()
            let thumbOpts = PHImageRequestOptions()
            thumbOpts.isSynchronous = true
            thumbOpts.deliveryMode = .fastFormat
            thumbOpts.isNetworkAccessAllowed = true

            result.enumerateObjects { asset, _, _ in
                var thumb: UIImage?
                mgr.requestImage(for: asset, targetSize: CGSize(width: 300, height: 300),
                                 contentMode: .aspectFill, options: thumbOpts) { img, _ in thumb = img }
                let type: MediaItem.MediaType = asset.mediaType == .video ? .video : .photo
                items.append(MediaItem(type: type, assetId: asset.localIdentifier, thumb: thumb))
            }

            DispatchQueue.main.async {
                mediaItems = items
                selectedItems = Set(items.map(\.id))
                loading = false
            }
        }
    }
}

// MARK: - Player
struct SlideShowPlayer: View {
    let items: [MediaItem]; let duration: Double; let playMode: Int; let loopMode: Int
    let onExit: () -> Void
    @State private var idx = 0; @State private var order: [Int] = []
    @State private var paused = false; @State private var progress: Double = 0
    @State private var elapsed: Double = 0; @State private var showUI = true
    @State private var player: AVPlayer?
    @State private var dragOffset: CGFloat = 0
    let timer = Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            contentView.id(idx)
            // Thin top bar (always visible on tap)
            if showUI {
                topBar
                bottomBar
            }
            // Brief overlay on index change
        }
        .gesture(
            DragGesture().onChanged { v in dragOffset = v.translation.width }
            .onEnded { v in
                if abs(v.translation.width) > 80 {
                    if v.translation.width < 0 { next() } else { prev() }
                }
                dragOffset = 0
            }
        )
        .onTapGesture { showUI.toggle() }
        .onAppear { start() }
        .onReceive(timer) { _ in tick() }
        .onDisappear { player?.pause() }
        .onChange(of: idx) { _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { if !paused { showUI = false } }
        }
    }

    @ViewBuilder var contentView: some View {
        if !order.isEmpty, idx < order.count, order[idx] < items.count {
            let item = items[order[idx]]
            if item.type == .video {
                VideoPlayerView(assetId: item.assetId, player: $player, onEnd: next)
            } else {
                PhotoView(assetId: item.assetId)
            }
        }
    }

    var topBar: some View {
        VStack { HStack {
            Text("\(idx+1) / \(order.count)").foregroundColor(.white).font(.system(size: 15, weight: .medium))
            Spacer()
            Button(action: onExit) {
                Image(systemName: "xmark.circle.fill").font(.title3).foregroundColor(.white.opacity(0.8))
            }.buttonStyle(.plain)
        }.padding(.horizontal, 16).padding(.top, 8).background(.ultraThinMaterial.opacity(0.3)); Spacer() }
    }

    var bottomBar: some View {
        VStack { Spacer()
            HStack {
                Spacer()
                if !order.isEmpty, idx < order.count, order[idx] < items.count,
                   items[order[idx]].type == .photo {
                    Button(action: { paused.toggle() }) {
                        Image(systemName: paused ? "play.fill" : "pause.fill").font(.title2)
                    }.buttonStyle(.plain)
                }
                Spacer()
            }
            .foregroundColor(.white)
            .padding(.bottom, 12)
            GeometryReader { g in
                Rectangle().fill(Color.purple.opacity(0.6)).frame(width: g.size.width * progress)
            }.frame(height: 3)
        }
    }

    func tick() {
        guard !paused, !order.isEmpty, idx < order.count, order[idx] < items.count else { return }
        if items[order[idx]].type == .video { return }
        elapsed += 0.05; progress = min(1, elapsed / duration)
        if elapsed >= duration { next() }
    }

    func start() { order = Array(0..<items.count); if playMode == 1 { order.shuffle() }; idx=0; elapsed=0; progress=0 }
    func next() { go(idx+1) }
    func prev() { go(idx > 0 ? idx-1 : (loopMode == 0 ? order.count-1 : idx)) }
    func go(_ i: Int) {
        player?.pause(); player = nil
        var target = i
        if target >= order.count {
            if loopMode == 0 { if playMode == 1 { order.shuffle() }; target = 0 }
            else { onExit(); return }
        }
        idx = target; elapsed = 0; progress = 0
    }
    func timeStr(_ t: Double) -> String { String(format: "%d:%02d", Int(t)/60, Int(t)%60) }
}

// MARK: - Lazy Photo Loader
struct PhotoView: View {
    let assetId: String
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let img = image {
                Image(uiImage: img).resizable().aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Color.black.onAppear { load() }
            }
        }
    }

    func load() {
        let result = PHAsset.fetchAssets(withLocalIdentifiers: [assetId], options: nil)
        guard let asset = result.firstObject else { return }
        let opts = PHImageRequestOptions()
        opts.isNetworkAccessAllowed = true
        opts.deliveryMode = .highQualityFormat
        opts.isSynchronous = false
        let screenW = UIScreen.main.bounds.width * UIScreen.main.scale * 2
        PHImageManager.default().requestImage(for: asset, targetSize: CGSize(width: screenW, height: screenW),
                                               contentMode: .aspectFit, options: opts) { img, _ in
            DispatchQueue.main.async { self.image = img }
        }
    }
}

// MARK: - Video Player (iCloud streaming)
struct VideoPlayerView: View {
    let assetId: String
    @Binding var player: AVPlayer?
    let onEnd: () -> Void
    @State private var showExit = false

    var body: some View {
        ZStack {
            VideoPlayer(player: player)
            if showExit {
                VStack { HStack {
                    Spacer()
                    Button(action: onEnd) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2).foregroundColor(.white.opacity(0.8))
                            .padding(8).background(Circle().fill(.black.opacity(0.4)))
                    }.buttonStyle(.plain).padding(.trailing, 16).padding(.top, 8)
                }; Spacer() }
            }
        }
        .onTapGesture { showExit.toggle() }
        .onAppear { load() }
        .onDisappear { player?.pause(); showExit = false }
    }

    func load() {
        let result = PHAsset.fetchAssets(withLocalIdentifiers: [assetId], options: nil)
        guard let asset = result.firstObject else { return }
        let opts = PHVideoRequestOptions()
        opts.isNetworkAccessAllowed = true
        opts.deliveryMode = .automatic
        PHImageManager.default().requestPlayerItem(forVideo: asset, options: opts) { playerItem, _ in
            DispatchQueue.main.async {
                guard let pi = playerItem else { self.onEnd(); return }
                let p = AVPlayer(playerItem: pi)
                self.player = p
                NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: pi, queue: .main) { _ in onEnd() }
                NotificationCenter.default.addObserver(forName: .AVPlayerItemFailedToPlayToEndTime, object: pi, queue: .main) { _ in onEnd() }
                p.play()
            }
        }
        // Safety timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) {
            if player == nil { onEnd() }
        }
    }
}
