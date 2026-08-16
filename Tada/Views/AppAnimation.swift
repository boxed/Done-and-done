//
//  AppAnimation.swift
//  Tada
//

import SwiftUI

extension Animation {
    /// SwiftUI's `.default` runs about 0.35s, which reads as sluggish for something as small as a
    /// row appearing. This is that, four times faster. Use it instead of `.default` everywhere, so
    /// the app has one pace rather than a mix.
    ///
    /// Note this cannot speed up the keyboard: its show/hide animation is owned by the system and
    /// has no public API to change. The only way to affect it is disabling UIKit animations
    /// process-wide, which breaks interactive navigation transitions.
    static let quick = Animation.easeInOut(duration: 0.0875)
}

/// Applies a change with no animation at all.
///
/// SwiftUI's `List` is backed by a UIKit collection view, and row insertions and removals are
/// animated by that collection view at a fixed ~0.25s. No `Animation` value shortens it —
/// measured at 0.247s whether the change went through `.animation(.quick,)`, an animated
/// `@FetchRequest`, or `withAnimation(.quick)`. Suppressing it is the only lever, and it makes
/// the row appear in a single frame.
func withoutAnimation(_ body: () -> Void) {
    var transaction = Transaction()
    transaction.disablesAnimations = true
    withTransaction(transaction, body)
}
