//
//  EventEmitter.swift
//  RNAudioRecorderPlayer
//
//  Created by 최은화 on 2023/09/25.
//

import Foundation
 
class EventEmitter {

    /// Shared Instance.
    public static var sharedInstance = EventEmitter()

    // ReactNativeEventEmitter is instantiated by React Native with the bridge.
    private static var eventEmitter : RNAudioRecorderPlayer!

    private init() {}

    // When React Native instantiates the emitter it is registered here.
    func registerEventEmitter(eventEmitter : RNAudioRecorderPlayer) {
        EventEmitter.eventEmitter = eventEmitter
    }

  
    func dispatch(name: String, body: Any?) {
      EventEmitter.eventEmitter.sendEvent(withName: name, body: body)
    }

    /// All Events which must be support by React Native.
    lazy var allEvents: [String] = {
        var allEventNames: [String] = []

        // Append all events here
        
        return allEventNames
    }()

}
