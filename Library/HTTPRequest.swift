//
//  HTTPResourceRequest.swift
//  CoreHTTP
//
//  Created by Saul Mora on 6/25/16.
//  Copyright © 2016 Magical Panda Software. All rights reserved.
//

import Result

let defaultCachePolicy = URLRequest.CachePolicy.useProtocolCachePolicy
let defaultTimeout: TimeInterval = 30.seconds

private func requestFor<H: HTTPHostProtocol, R: HTTPResourceProtocol>(
    resource: R,
    host: H,
    cachePolicy: URLRequest.CachePolicy,
    requestTimeout: TimeInterval)
  -> Result<URLRequest, R.ErrorType>
    where R.ErrorType == HTTPResponseError
{
  let path = resource.path
  let requestedURL = host.baseURL.appendingPathComponent(path)
  guard var components = URLComponents(url: requestedURL, resolvingAgainstBaseURL: false)
    else { return Result(error: .hostBaseURLInvalid) }

  let authentication = host.authentication?()

  var queryItems: [URLQueryItem] = []
  if let authentication = authentication, case let .QueryParameters(key, value) = authentication
  {
    queryItems.append(URLQueryItem(name: key, value: value))
  }
  queryItems.append(contentsOf: convertToQueryItems(source: resource.queryParameters))
  components.queryItems = queryItems
  
  guard let requestURL = components.url else {
    return Result(error: .unableToBuildRequest(path: resource.path, queryParameters: resource.queryParameters))
  }
  
  var request = URLRequest(url: requestURL, cachePolicy: cachePolicy, timeoutInterval: requestTimeout)
  request.httpMethod = resource.method.value

  if let authentication = authentication, case let .Basic(token) = authentication
  {
    request.addValue("Basic \(token)", forHTTPHeaderField: "Authorization")
  }
  else if let auth = authentication, case let .OAuth(token) = auth
  {
    request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
  }
  return Result(request)
}

@discardableResult public func request<R>(
    resource: R,
    from host: HTTPHost? = nil,
    cacheWith cachePolicy: URLRequest.CachePolicy = defaultCachePolicy,
    timeoutAfter requestTimeout: TimeInterval = defaultTimeout,
    completion: @escaping (Result<R.ResourceType, R.ErrorType>) -> Void)
  -> URLSessionTask?
    where R: HostedResource, R: HTTPResourceProtocol, R.ErrorType == HTTPResponseError
{
  guard let hostToQuery = host ?? hostRegistry.hostFor(resource) else {
    completion(Result(error: .hostNotSpecified))
    return nil
  }
  
  let completionHandler = completionHandlerForRequest(resource: resource, validate: hostToQuery.validate, completion: completion)
  
  let sessionTask = requestFor(resource: resource, host: hostToQuery, cachePolicy: cachePolicy, requestTimeout: requestTimeout)
    >>- { Result(hostToQuery.session.dataTask(with: $0, completionHandler: completionHandler)) }
  
  let task = sessionTask.map { requestTask -> URLSessionTask in
    log(level: .Debug, message: "Sending Request: \(requestTask.currentRequest?.url)")
    requestTask.resume()
    return requestTask
  }
  
  return task.value
}

/// Utilities

fileprivate func convertToQueryItems(source: [String: String]) -> [URLQueryItem]
{
  guard !source.isEmpty else { return [] }
  
  return source.flatMap { URLQueryItem(name: $0, value: $1) }
}
