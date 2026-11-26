// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Testing
@testable import Vertep

/// The folder summary line in the app's String Catalog: the plural forms of the number of
/// titles in English and Ukrainian.
@Suite struct FolderSummaryTextTests {
    private static let key = "%lld titles · %lld watched"

    @Test(arguments: [
        (1, 1, "1 title · 1 watched"),
        (3, 1, "3 titles · 1 watched"),
        (24, 9, "24 titles · 9 watched"),
    ])
    func english(titles: Int, watched: Int, expected: String) throws {
        #expect(try Self.summary(language: "en", titles: titles, watched: watched) == expected)
    }

    /// Ukrainian has three plural forms of the noun: one for 1, 21 and 31, one for 2 to
    /// 4 and 22 to 24, and one for 5 to 20 and 25 to 30. The test compares the forms with
    /// one another, so it holds no Ukrainian text.
    @Test func ukrainianUsesThreePluralFormsOfTheTitles() throws {
        func noun(_ titles: Int) throws -> String {
            let summary = try Self.summary(language: "uk", titles: titles, watched: 0)
            let titlesPart = try #require(summary.components(separatedBy: " · ").first)
            return String(titlesPart.drop(while: { $0.isNumber || $0 == " " }))
        }
        let one = try noun(1)
        let few = try noun(2)
        let many = try noun(5)
        #expect(Set([one, few, many]).count == 3)
        for count in [21, 31] { #expect(try noun(count) == one) }
        for count in [3, 4, 22, 24] { #expect(try noun(count) == few) }
        for count in [11, 12, 14, 20, 25, 30] { #expect(try noun(count) == many) }
        // The watched part keeps one form for every number.
        func watchedWord(_ watched: Int) throws -> String {
            let summary = try Self.summary(language: "uk", titles: 1, watched: watched)
            let watchedPart = try #require(summary.components(separatedBy: " · ").last)
            #expect(watchedPart.hasPrefix("\(watched) "))
            return String(watchedPart.drop(while: { $0.isNumber || $0 == " " }))
        }
        #expect(Set(try [1, 2, 5, 9, 21].map(watchedWord)).count == 1)
    }

    /// The summary as the app's bundle formats it in one language. The tests run hosted in
    /// the app, so the main bundle is the app's.
    private static func summary(language: String, titles: Int, watched: Int) throws -> String {
        let path = try #require(Bundle.main.path(forResource: language, ofType: "lproj"))
        let bundle = try #require(Bundle(path: path))
        let format = bundle.localizedString(forKey: key, value: nil, table: nil)
        return String(format: format, locale: Locale(identifier: language), titles, watched)
    }
}
