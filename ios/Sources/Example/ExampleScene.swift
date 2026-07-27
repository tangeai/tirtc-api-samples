import SwiftUI

struct ExampleScene: View {
    @ObservedObject var session: ExampleSessionController

    var body: some View {
        Group {
            if session.isClientPlayerActive {
                ExampleClientPlayer(session: session)
            } else {
                ExampleClientConfigure(session: session)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ExampleColors.background)
    }
}
