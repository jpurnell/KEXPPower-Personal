//
//  ShowView.swift
//  KEXPPowerExampleSwiftUI (iOS)
//
//  Created by Justin Purnell on 2/8/22.
//  Copyright © 2022 KEXP. All rights reserved.
//

import SwiftUI
import KEXPPower

struct ShowView: View {
    var show: Show?
    
    var body: some View {
        ProgramView(imageURL: show?.imageURI ?? "", programName: show?.programName ?? "", hostName: show?.hostNames ?? [""], tagline: show?.tagline ?? "", small: true).padding()
    }
}

struct ShowView_Previews: PreviewProvider {
    static var previews: some View {
        ShowView(show: Show.fixture())
            .previewLayout(.sizeThatFits)
    }
}
