import SwiftUI

extension Binding {
    func containing<Element: Hashable>(_ element: Element) -> Binding<Bool> where Value == Set<Element> {
        Binding<Bool> {
            wrappedValue.contains(element)
        } set: { isMember in
            if isMember {
                wrappedValue.insert(element)
            } else {
                wrappedValue.remove(element)
            }
        }
    }
}
