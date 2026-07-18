//
//  EmulatorRouterView.swift
//  romm
//
//  Created by Ilyas Hallak on 15.05.26.
//

import SwiftUI

struct EmulatorRouterView: View {
    let decision: LaunchDecision

    var body: some View {
        switch decision {
        case .web(let rom, let source):
            EmulatorView(rom: rom, launchSource: source)
        case .native(let rom, let gameType, let source):
            NativeEmulatorView(rom: rom, gameType: gameType, launchSource: source)
        case .libretro(let rom, let core, let source):
            LibretroEmulatorView(rom: rom, core: core, launchSource: source)
        }
    }
}
