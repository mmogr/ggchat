import SwiftUI

/// The two rows a composer ends in: the field across the top, and under it
/// a toolbar with the add-image control and Draw at the leading end and
/// Send alone at the trailing one. The field arrives styled, since the
/// local composer's is plain inside the app's glass and a Mac chat's is the
/// stock bordered one; the rows draw nothing of their own.
///
/// The field had shared a row with the controls, and on a phone four
/// circles left it a third of the width: a short sentence wrapped three
/// times. On its own row it is as wide as the composer, and the toolbar
/// is no narrower for the controls it holds.
struct ComposerRows<Field: View, Leading: View, Send: View>: View {
    @ViewBuilder let field: () -> Field
    @ViewBuilder let leading: () -> Leading
    @ViewBuilder let send: () -> Send

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            field()
                .padding(.horizontal, ComposerLayout.inset)
                .padding(.top, 6)
                .padding(.bottom, 2)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(alignment: .center, spacing: 8) {
                leading()
                Spacer(minLength: 0)
                send()
            }
        }
    }
}

/// What the rows share with the line drawn over them.
enum ComposerLayout {
    /// How far the text and the "Drawing with" line sit in from the
    /// toolbar's circles, so their leading edges read as one column.
    static let inset: CGFloat = 6
}
