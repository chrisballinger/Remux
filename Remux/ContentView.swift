//
//  ContentView.swift
//  Remux
//
//  Created by Chris Ballinger on 10/11/19.
//  Copyright © 2019 Chris Ballinger. All rights reserved.
//

import SwiftUI
import SwiftFFmpeg

struct FilePath: Identifiable {
    var id: URL { url }
    var url: URL

    func load() throws {

        let fileCoordinator = NSFileCoordinator()
        var error: NSError?
        fileCoordinator.coordinate(readingItemAt: url, error: &error) { (url) in
            do {
                defer {
                    url.stopAccessingSecurityScopedResource()
                }
                _ = url.startAccessingSecurityScopedResource()
                let fmtCtx = try AVFormatContext(url: url.path)
                try fmtCtx.findStreamInfo()

                fmtCtx.dumpFormat(isOutput: false)


                guard let stream = fmtCtx.videoStream else {
                    fatalError("No video stream.")
                }
                guard let codec = AVCodec.findDecoderById(stream.codecParameters.codecId) else {
                    fatalError("Codec not found.")
                }
                let codecCtx = AVCodecContext(codec: codec)
                codecCtx.setParameters(stream.codecParameters)
                try codecCtx.openCodec()

                let pkt = AVPacket()
                let frame = AVFrame()

                while let _ = try? fmtCtx.readFrame(into: pkt) {
                    defer { pkt.unref() }

                    if pkt.streamIndex != stream.index {
                        continue
                    }

                    try codecCtx.sendPacket(pkt)

                    while true {
                        do {
                            try codecCtx.receiveFrame(frame)
                        } catch let err as AVError where err == .tryAgain || err == .eof {
                            break
                        }

                        let str = String(
                            format: "Frame %3d (type=%@, size=%5d bytes) pts %4lld key_frame %d",
                            codecCtx.frameNumber,
                            frame.pictureType.description,
                            frame.pktSize,
                            frame.pts,
                            frame.isKeyFrame
                        )
                        print(str)

                        frame.unref()
                    }
                }

                print("Done.")
            } catch {
                print("Error \(error)")
            }

        }
        if let error = error {
            print("reading errror \(error)")
            return
        }

    }
}

struct ContentView: View {
    @State var filePaths: [FilePath] = []

    var body: some View {
        VStack {
            List(filePaths) { path in
                Text(path.url.path)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onDrop(of: [kUTTypeFileURL as String], isTargeted: nil) { (itemProviders) -> Bool in
            // only support dropping 1 file at a time for now
            guard let firstItem = itemProviders.first else { return false }
            firstItem.loadInPlaceFileRepresentation(forTypeIdentifier: kUTTypeFileURL as String) { (url, isInPlace, error) in
                guard let url = url else { return }
                self.filePaths = [FilePath(url: url)]

                self.filePaths.forEach { try? $0.load() }
            }
            return true
        }
    }
}


struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
