//
//  LocaleTypes.swift
//  JivoMobile
//
//  Created by Stan Potemkin on 02/06/2018.
//  Copyright © 2018 JivoSite. All rights reserved.
//

import Foundation

#if canImport(JivoSDK)
import JivoSDK
#endif

internal let loc = JVLocalizer.shared

extension Notification.Name {
    static let jvLocaleDidChange = Notification.Name("LocaleDidChange")
}

enum JVLocalizedMetaMode {
    case key(String)
    case format(String)
    case exact(String)
}

enum JVSearchingBehavior {
    case app
    case sdk
}

struct JVLocalizerSearchingRule<Location> {
    let location: Location
    let namespace: String
}

final class JVLocalizer {
    static let shared = JVLocalizer()
    
    var searchingRulesProvider: (_ lang: String) -> [JVLocalizerSearchingRule<String?>] = { _ in
        return [JVLocalizerSearchingRule(location: Bundle.main.bundlePath, namespace: .jv_empty)]
    }
    
    private var langToSearchingPathsCache = [String: [JVLocalizerSearchingRule<Bundle>]]()
    
    private init() {
    }
    
    public subscript(_ keys: String...) -> String {
        let langId = (JVLocaleProvider.activeLocale ?? Locale.current).jv_langId
        var result = String()
        
        let searchingRules: [JVLocalizerSearchingRule<Bundle>]
        if let rules = langToSearchingPathsCache[langId] {
            searchingRules = rules
        }
        else {
            let rules = searchingRulesProvider(langId)
                .compactMap { rule in
                    if let path = rule.location, let bundle = Bundle(path: path) {
                        return JVLocalizerSearchingRule(location: bundle, namespace: rule.namespace)
                    }
                    else {
                        return nil
                    }
                }
            
            langToSearchingPathsCache[langId] = rules
            searchingRules = rules
        }
        
        for key in keys {
            if let value = searchingRules.jv_findTranslation(key: key) {
                return value
            }
            else {
                result = key
            }
            
            if result != key {
                break
            }
        }
        
        return result
    }
    
    public subscript(key key: String) -> String {
        return self[key]
            .replacingOccurrences(of: "%s", with: "%@")
            .replacingOccurrences(of: "$s", with: "$@")
    }
    
    public subscript(format key: String, _ arguments: CVarArg...) -> String {
        let locale = JVLocaleProvider.activeLocale
        return String(format: self[key: key], locale: locale, arguments: arguments)
    }
}

func JVActiveLocale() -> Locale {
    return JVLocaleProvider.activeLocale
}

fileprivate extension Array where Element == JVLocalizerSearchingRule<Bundle> {
    func jv_findTranslation(key: String) -> String? {
        for rule in self {
            let searchingKey = rule.namespace + key
            let value = rule.location.localizedString(forKey: searchingKey, value: nil, table: nil)
            
            if value != searchingKey {
                return value
            }
        }
        
        return nil
    }
}
