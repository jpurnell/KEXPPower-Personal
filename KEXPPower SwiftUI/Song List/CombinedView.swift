//
//  CombinedView.swift
//  KEXPPowerExampleSwiftUI (iOS)
//
//  Created by Justin Purnell on 5/7/24.
//  Copyright © 2024 KEXP. All rights reserved.
//

import SwiftUI
import KEXPPower

/// One play: artwork, details, and a backdrop made from the artwork itself. Tapping expands it.
struct CombinedView: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var play: Play?
    var imageURL: String = "https://kexp.org/static/assets/img/kexp_logo.jpg"
    @State var small: Bool = true

    private let corner: CGFloat = 12

    /// How wide and tall the expanded details may grow: a Mac window has room for a comfortable line length, and its
    /// page scrolls, so the details are never cut short.
    #if os(macOS)
    private let detailWidth: CGFloat = 720
    private let detailHeight: CGFloat = .infinity
    #else
    private let detailWidth: CGFloat = 340
    private let detailHeight: CGFloat = 400
    #endif

    var body: some View {
        VStack {
            HStack {
                ImageView(play: play ?? .fixture())
                    .frame(
                        minWidth: small ? 120 : 200,
                        idealWidth: small ? 120 : 400,
                        maxWidth: small ? 120 : 400,
                        minHeight: 120,
                        idealHeight: small ? 120 : 400
                    )
                    .padding(small ? [.vertical] : [.all])
                (small ? CompactView(play: play ?? .fixture())
                    .frame(minWidth: 200, maxWidth: .infinity)
                    .padding(.leading)
                    .padding(.vertical) : nil)
            }
            (small ? nil : ExtendedView(play: play ?? .fixture()))
                .frame(
                    minWidth: 200,
                    idealWidth: 200,
                    maxWidth: detailWidth,
                    minHeight: 100,
                    idealHeight: 200,
                    maxHeight: detailHeight,
                    alignment: .center
                )
                .clipped()
                .padding(.bottom, 5).padding(.vertical)
        }
        // Fill the row, so an expanded one is as wide as a collapsed one.
        .frame(maxWidth: .infinity)
        .padding(8)
        .overlay(alignment: .topTrailing) {
            if AppSongSaver.canSaveToPlaylists, let play, SongSavingModel.canSave(play) {
                SaveButton(play: play).padding(4)
            }
        }
        .foregroundStyle(.primary)
        .background { backdrop }
        .clipShape(RoundedRectangle(cornerRadius: corner))
        // The tap goes on the finished row, background and all. Attached to the content before the background, a row
        // inside a Mac scroll view answered clicks only in its top half (measured: taps 31 and 63 pt down fired, 85 pt
        // and deeper did not); here it answers anywhere in the row. Links and buttons inside still take their own clicks.
        .contentShape(Rectangle())
        .onTapGesture { small.toggle() }
        .accessibilityAction(named: small ? "Show details" : "Hide details") { small.toggle() }
    }

    /// The artwork, blurred, under a material. Clipped to the row so it can never spill onto neighbouring views.
    private var backdrop: some View {
        ZStack {
            Color.clear
                .overlay {
                    ImageView(play: play ?? .fixture())
                        .scaledToFill()
                        .blur(radius: reduceTransparency ? 0 : 20)
                }
                .clipped()
            Rectangle()
                .fill(reduceTransparency ? AnyShapeStyle(.background) : AnyShapeStyle(.ultraThinMaterial))
        }
    }
}

#Preview(traits: .sizeThatFitsLayout) {
    CombinedView(play: .fixture())
        .environment(AppSongSaver.makeModel())
}
