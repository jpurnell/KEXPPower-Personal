//
//  Router.swift
//  KEXPPower
//
//  Created by Dustin Bergman on 7/8/19.
//  Copyright © 2019 KEXP. All rights reserved.
//

import Foundation
import OSLog

public enum Result<Value, Error: Swift.Error> {
    case success(Value)
    case failure(NSError)
}

typealias Completion = (_ result: Result<Data, Error>) -> Void

@MainActor
class Router {
    enum NetworkError: Error {
        case serverError(String)
    }
    
//    func get(url :URL, parameters: [URLQueryItem]? = nil, completion: @escaping Completion) {
//        var urlComponents = URLComponents(url: url, resolvingAgainstBaseURL: false)
//        urlComponents?.queryItems = parameters
//        
//        guard
//            let requestURL = urlComponents?.url
//        else {
//            let error = NSError(
//                domain: "com.kexppower.error",
//                code: 0,
//                userInfo: [NSLocalizedDescriptionKey: "Error building URL"]
//            )
//            
//            completion(.failure(error))
//            
//            return
//        }
//        
//        var request = URLRequest(url: requestURL)
//        request.cachePolicy = .reloadIgnoringLocalCacheData
//        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Accept")
//		
//        URLSession.shared.dataTask(with: request) { data, response, error in
//            do {
//                guard
//                    let data = data,
//                    let response = response as? HTTPURLResponse,
//                    (200 ..< 300) ~= response.statusCode,
//                    error == nil
//                    else {
//                        throw NetworkError.serverError("Platform server error")
//                }
//                
//                completion(.success(data))
//            } catch {
//                let error = NSError(
//                    domain: "com.kexppower.error",
//                    code: 0,
//                    userInfo: [NSLocalizedDescriptionKey: error.localizedDescription]
//                )
//                
//                completion(.failure(error))
//            }
//        }.resume()
//    }
	
	
	func get<T: Decodable>(url: URL, parameters: [URLQueryItem]? = nil, logged: Bool = false) async throws -> T {
		let logger = Logger(#function)
		var urlComponents = URLComponents(url: url, resolvingAgainstBaseURL: false)
		urlComponents?.queryItems = parameters
		
		guard
			let requestURL = urlComponents?.url
		else {
			let error = NSError(
				domain: "com.kexppower.error",
				code: 0,
				userInfo: [NSLocalizedDescriptionKey: "Error building URL"]
			)
			throw error
		}
		
		var request = URLRequest(url: requestURL)
		request.cachePolicy = .reloadIgnoringLocalCacheData
		request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Accept")
		let (data, response) = try await URLSession.shared.data(for: request)
		logged ? logger.debug("Got Response:\t\(response.description)") : nil
		let decodableResult = try JSONDecoder().decode(T.self, from: data)
		return decodableResult
	}
}
