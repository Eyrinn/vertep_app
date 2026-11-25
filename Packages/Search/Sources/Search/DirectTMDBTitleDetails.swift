// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Core
import Foundation

/// Gets title details directly from TMDB with a personal API key, for the Simulator and
/// for forks that run no proxy.
///
/// It asks TMDB for the movie or series details with credits, one request per title, and
/// returns the same details as the proxy. When a Ukrainian request finds no Ukrainian
/// overview, it asks for the English details of that title and uses the English overview,
/// marked as English. A title TMDB answers with 404 is reported as not found.
public struct DirectTMDBTitleDetails: TitleDetailsProvider {
    private let apiKey: String
    private let transport: any HTTPTransport

    /// `apiKey` is a personal TMDB API key from the local build configuration.
    public init(apiKey: String, transport: any HTTPTransport = URLSession.shared) {
        self.apiKey = apiKey
        self.transport = transport
    }

    /// What TMDB answered for one title.
    private enum Outcome: Sendable {
        case found(TitleDetails)
        case notFound
        case failure(TitleDetailsError)
    }

    /// Asks for every title at once. When any title fails, the whole request fails, as a
    /// proxy reports it.
    public func details(_ request: TitleDetailsRequest) async throws(TitleDetailsError) -> TitleDetailsResponse {
        let outcomes = await withTaskGroup(of: (Int, Outcome).self) { group in
            for (index, id) in request.ids.enumerated() {
                group.addTask { (index, await self.outcome(for: id, language: request.language)) }
            }
            var outcomes = [Outcome?](repeating: nil, count: request.ids.count)
            for await (index, outcome) in group {
                outcomes[index] = outcome
            }
            return outcomes
        }

        var response = TitleDetailsResponse(results: [], notFound: [])
        for (id, outcome) in zip(request.ids, outcomes) {
            switch outcome {
            case .found(let details): response.results.append(details)
            case .notFound: response.notFound.append(id)
            case .failure(let error): throw error
            case nil: throw .unavailable
            }
        }
        return response
    }

    private func outcome(for id: TitleID, language: SearchLanguage) async -> Outcome {
        do {
            guard let title = try await fetch(id, language: language, withCredits: true) else { return .notFound }
            guard var details = title.details(id: id) else { return .failure(.unavailable) }
            details.overviewLanguage = details.overview == nil ? nil : language
            if details.overview == nil, language == .uk,
               let english = try await fetch(id, language: .en, withCredits: false)?.overview.nonEmpty {
                details.overview = english
                details.overviewLanguage = .en
            }
            return .found(details)
        } catch {
            return .failure(error)
        }
    }

    /// The details of a title in `language`, or nil when TMDB answers that it does not
    /// know the title.
    private func fetch(_ id: TitleID, language: SearchLanguage, withCredits: Bool) async throws(TitleDetailsError) -> TMDBTitle? {
        var query = [("language", language.tmdbLanguage)]
        if withCredits { query.append(("append_to_response", "credits")) }
        query.append(("api_key", apiKey))
        guard let url = DirectTMDBTitleSearch.apiBaseURL.appendingRawPath(
            "/\(id.mediaType.rawValue)/\(id.tmdbID)", query: query
        ) else { throw .failed }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await transport.send(request)
        } catch {
            throw .unavailable
        }
        switch response.statusCode {
        case 200..<300:
            break
        case 404:
            return nil
        case 401:
            // TMDB refused the key. Sending the request again would not change that.
            throw .failed
        default:
            throw .unavailable
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let title = try? decoder.decode(TMDBTitle.self, from: data) else { throw .unavailable }
        return title
    }
}

/// The part of TMDB's movie or series details that the app needs. TMDB names the same
/// field differently for a movie and for a series.
private struct TMDBTitle: Decodable {
    struct Genre: Decodable {
        let id: Int
        let name: String
    }

    struct Person: Decodable {
        let name: String
    }

    struct CastMember: Decodable {
        let name: String
        let order: Int?
    }

    struct CrewMember: Decodable {
        let name: String
        let job: String?
    }

    struct Credits: Decodable {
        let cast: [CastMember]?
        let crew: [CrewMember]?
    }

    struct Episode: Decodable {
        let runtime: Int?
    }

    let title: String?
    let originalTitle: String?
    let name: String?
    let originalName: String?
    let releaseDate: String?
    let firstAirDate: String?
    let posterPath: String?
    let overview: String?
    let genres: [Genre]?
    let runtime: Int?
    let episodeRunTime: [Int]?
    let lastEpisodeToAir: Episode?
    let createdBy: [Person]?
    let credits: Credits?

    /// The details as Core declares them, without an overview language, or nil when TMDB
    /// gives the title no name in any language.
    func details(id: TitleID) -> TitleDetails? {
        let isMovie = id.mediaType == .movie
        let original = (isMovie ? originalTitle : originalName).nonEmpty
        guard let title = (isMovie ? title : name).nonEmpty ?? original else { return nil }
        let cast = (credits?.cast ?? [])
            .enumerated()
            .sorted { ($0.element.order ?? .max, $0.offset) < ($1.element.order ?? .max, $1.offset) }
            .prefix(TitleDetails.castCount)
            .map(\.element.name)
        let directors = (credits?.crew ?? []).filter { $0.job == "Director" }.map(\.name)
        let creators = (createdBy ?? []).map(\.name)
        let seriesRuntime = episodeRunTime?.first { $0 > 0 } ?? lastEpisodeToAir?.runtime
        return TitleDetails(
            id: id,
            title: title,
            originalTitle: original ?? title,
            year: TMDBDate.year(of: isMovie ? releaseDate : firstAirDate),
            posterPath: posterPath.nonEmpty,
            director: isMovie ? Self.names(directors) : nil,
            creator: isMovie ? nil : Self.names(creators),
            cast: cast,
            overview: overview.nonEmpty,
            overviewLanguage: nil,
            genres: (genres ?? []).map { TitleGenre(id: $0.id, name: $0.name) },
            runtime: (isMovie ? runtime : seriesRuntime).flatMap { $0 > 0 ? $0 : nil }
        )
    }

    /// The names, each once, separated by `, ` as the contract writes several names, or
    /// nil when there is none.
    private static func names(_ names: [String]) -> String? {
        var seen = Set<String>()
        let unique = names.filter { !$0.isEmpty && seen.insert($0).inserted }
        return unique.isEmpty ? nil : unique.joined(separator: ", ")
    }
}
