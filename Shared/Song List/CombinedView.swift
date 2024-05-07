//
//  CombinedView.swift
//  KEXPPowerExampleSwiftUI (iOS)
//
//  Created by Justin Purnell on 5/7/24.
//  Copyright © 2024 KEXP. All rights reserved.
//

import SwiftUI

struct CombinedView: View {
	var play: Play
	
    var body: some View {
		play.isRequest ?? false ? 
		PlayView(play: play).tint(.red).frame(height: 100) :
		PlayView(play: play).tint(.green).frame(height: 300)
    }
}

#Preview {
	CombinedView(play: .fixture())
}
