//
//  ProgramView.swift
//  KEXPPower
//
//  Created by Justin Purnell on 2/8/22.
//  Copyright © 2022 KEXP. All rights reserved.
//

import SwiftUI

struct ProgramView: View {
    var imageURL: String = "https://www.kexp.org/filer/canonical/1614617435/24778/"
    var programName: String = "The Morning Show"
    var hostName: [String] = ["John Richards"]
    var tagline: String = "International Clash Day"
    var small: Bool = true
    
    var body: some View {
        HStack(alignment: .top) {
            AsyncImage(url: URL(string: imageURL), scale: 1) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } placeholder: {
                if imageURL == "" {
                    Image(systemName: "person.fill").font(.system(size: 75)) }
                else {
                    ProgressView().progressViewStyle(.circular)
                }
            }
            .frame(minWidth: 20, idealWidth: 120, maxWidth: 120, minHeight: 20, idealHeight: 120, maxHeight: 120, alignment: .center)
			.clipShape(RoundedRectangle(cornerRadius: 5.0))
            .shadow(radius: 10)
			.overlay(RoundedRectangle(cornerRadius: 5.0)
                        .stroke(Color.gray, lineWidth: 0.25)
            )
            VStack(alignment: .leading) {
				Text(programName)
					.font(.title2)
					.fontWeight(.bold)
					.lineLimit(nil)
                Text(hostName.map({$0}).joined(separator: ", "))
					.font(.caption)
					.textCase(.uppercase)
					.fontWeight(.semibold)
                Spacer()
                Text(tagline).font(.caption).italic()
                Spacer()
            }.frame(minHeight: 120, idealHeight: 120, maxHeight: 160, alignment: .center)
        }
    }
}

struct ProgramView_Previews: PreviewProvider {
    static var previews: some View {
        ProgramView().previewLayout(.sizeThatFits)
    }
}
