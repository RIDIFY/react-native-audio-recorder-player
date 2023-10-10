//
//  RNAudioRecorderPlayer.swift
//  RNAudioRecorderPlayer
//
//  Created by hyochan on 2021/05/05.
//

import Foundation
import AVFoundation


@objc(RNAudioRecorderPlayer)
class RNAudioRecorderPlayer: RCTEventEmitter, AVAudioRecorderDelegate {
    var subscriptionDuration: Double = 1
    var audioFileURL: URL?

    // Recorder
    var audioRecorder: AVAudioRecorder!
    var audioSession: AVAudioSession!
    var recordTimer: Timer?
    var _meteringEnabled: Bool = false

    // Player
    var pausedPlayTime: CMTime?
    var audioPlayerAsset: AVURLAsset!
    var audioPlayerItem: AVPlayerItem!
    var audioPlayer: AVPlayer!
    var playTimer: Timer?
    var timeObserverToken: Any?
    
    var saveTimeCycleSecond = 120; //120초 (2분)
    var saveMaxTimeSecond = 86400;//24시간 //28800; //8시간
    var currentTime_now = 0
    var div_id : String?
    var recordDate : String?
    
    
    override init() {
      super.init()
      EventEmitter.sharedInstance.registerEventEmitter(eventEmitter: self)
    }

    
    func uploadAudioFile(_ audioFileName : String) {
        // 서버 엔드포인트 URL 설정
        let serverURL = URL(string: "http://121.172.214.28/test/api/test")!
        
        do {
            
            let directoryURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            let chunkFileURL = directoryURL.appendingPathComponent("\(audioFileName)")
            
            if let audioFilePath = URL(string: chunkFileURL.absoluteString) {

                // 파일 데이터 생성
                print("audioFilePath : \(chunkFileURL.absoluteString)")
                
                if let audioData = try? Data(contentsOf: chunkFileURL) {
                    // 고유한 Boundary 생성
                    let boundary = "Boundary-\(UUID().uuidString)"
                    
                    // HTTP Request 생성
                    var request = URLRequest(url: serverURL)
                    request.httpMethod = "POST"
                    
                    // HTTP Header 설정 (multipart/form-data)
                    request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
                    
                    // HTTP Body 설정
                    var bodyData = Data()
                    bodyData.append("--\(boundary)\r\n".data(using: .utf8)!)
                    bodyData.append("Content-Disposition: form-data; name=\"files\"; filename=\"\(audioFileName)\"\r\n".data(using: .utf8)!)
                    bodyData.append("Content-Type: audio/wav\r\n\r\n".data(using: .utf8)!)
                    bodyData.append(audioData)
                    bodyData.append("\r\n".data(using: .utf8)!)
                    bodyData.append("--\(boundary)--\r\n".data(using: .utf8)!)
                    
                    request.httpBody = bodyData
                    
                    // URLSession을 사용하여 업로드 요청 보내기
                    let task = URLSession.shared.dataTask(with: request) { (data, response, error) in
                        if let error = error {
                            print("Error: \(error)")
                            return
                        }
                        
                        if let httpResponse = response as? HTTPURLResponse {
                            print("Status Code: \(httpResponse.statusCode)")
                            
                            if let responseData = data, let responseString = String(data: responseData, encoding: .utf8) {
                                print("Response Data: \(responseString)")
                            }
                        }
                    }
                    task.resume()
                } else {
                    print("Failed to load audio file")
                }
            }
                
            
        } catch {
            print("Error loading audio file: \(error)")
        }
    }
    
    
    
    override static func requiresMainQueueSetup() -> Bool {
      return true
    }

    override func supportedEvents() -> [String]! {
        return ["rn-playback", "rn-recordback", "saveFileUrl"]
    }

    func setAudioFileURL(path: String) {
        if (path == "DEFAULT") {
            let documentDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            audioFileURL = documentDirectory.appendingPathComponent("sound.wav")
        } else if (path.hasPrefix("http://") || path.hasPrefix("https://") || path.hasPrefix("file://")) {
            audioFileURL = URL(string: path)
        } else {
            let documentDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            audioFileURL = documentDirectory.appendingPathComponent(path)
        }
    }

    /**********               Recorder               **********/
    @objc(updateRecorderProgress:)
    public func updateRecorderProgress(timer: Timer) -> Void {
        if (audioRecorder != nil) {
            var currentMetering: Float = 0

            if (_meteringEnabled) {
                audioRecorder.updateMeters()
                currentMetering = audioRecorder.averagePower(forChannel: 0)
            }

            let status = [
                "isRecording": audioRecorder.isRecording,
                "currentPosition": audioRecorder.currentTime * 1000,
                "currentMetering": currentMetering,
            ] as [String : Any];
            
            
            currentTime_now+=1
            
            print("audioRecorder.currentTime : \(audioRecorder.currentTime))")
            print("currentTime_now : \(currentTime_now))")
                
            do{
                
                if(currentTime_now % saveTimeCycleSecond == 0) {
                    
                    // 파일 읽기
                    if let originalAudioData = try? Data(contentsOf: audioFileURL!) {
                        do {
                            audioRecorder.stop()
                            
                            let asset: AVAsset = AVAsset(url: audioFileURL!)
                            let duration = CMTimeGetSeconds(asset.duration)
                            
                            print("audioFileURL.url duration : \(duration)")
                            
                            let dateFormatter = DateFormatter()
                            dateFormatter.dateFormat = "yyyyMMdd"
                            let dateString = dateFormatter.string(from:Date())
                            
                            
                            let directoryURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
                                                    
                            let chunkFileName = "\(div_id ?? "temp")_\(recordDate ?? dateString)_\(currentTime_now/saveTimeCycleSecond < 10 ? "0" : "")\(currentTime_now/saveTimeCycleSecond).wav"
                            
                            let chunkFileURL = directoryURL.appendingPathComponent("\(chunkFileName)")
                            
                        
                            try originalAudioData.write(to: chunkFileURL)
                        
                        
//                           self.uploadAudioFile(chunkFileName)
                            

                            sendEvent(withName: "saveFileUrl", body: ["url": chunkFileURL.absoluteString]);
                            
                        } catch {
                            print("Error saving chunk: \(error)")
                        }
                        
                    } else {
                        print("Failed to load original audio file")
                    }
                    
                    
                    if(currentTime_now > saveMaxTimeSecond) {
                       
                        audioRecorder.stop()

                        if (recordTimer != nil) {
                            recordTimer!.invalidate()
                            recordTimer = nil
                        }
                        
                    }else {
                        audioRecorder.record()
                    }
                    
                }
            
            } catch {
                print("Error playing received audio: \(error)")
            }
            
            sendEvent(withName: "rn-recordback", body: status)
        }
    }

    @objc(startRecorderTimer)
    func startRecorderTimer() -> Void {
        DispatchQueue.main.async {
            self.recordTimer = Timer.scheduledTimer(
                timeInterval: self.subscriptionDuration,
                target: self,
                selector: #selector(self.updateRecorderProgress),
                userInfo: nil,
                repeats: true
            )
        }
    }

    @objc(pauseRecorder:rejecter:)
    public func pauseRecorder(
        resolve: @escaping RCTPromiseResolveBlock,
        rejecter reject: @escaping RCTPromiseRejectBlock
    ) -> Void {
        if (audioRecorder == nil) {
            return reject("RNAudioPlayerRecorder", "Recorder is not recording", nil)
        }

        recordTimer?.invalidate()
        recordTimer = nil;

        audioRecorder.pause()
        resolve("Recorder paused!")
    }

    @objc(resumeRecorder:rejecter:)
    public func resumeRecorder(
        resolve: @escaping RCTPromiseResolveBlock,
        rejecter reject: @escaping RCTPromiseRejectBlock
    ) -> Void {
        if (audioRecorder == nil) {
            return reject("RNAudioPlayerRecorder", "Recorder is nil", nil)
        }

        audioRecorder.record()

        if (recordTimer == nil) {
            startRecorderTimer()
        }

        resolve("Recorder paused!")
    }

    @objc
    func construct() {
        self.subscriptionDuration = 0.1
    }

    @objc(audioPlayerDidFinishPlaying:)
    public static func audioPlayerDidFinishPlaying(player: AVAudioRecorder) -> Bool {
        return true
    }

    @objc(audioPlayerDecodeErrorDidOccur:)
    public static func audioPlayerDecodeErrorDidOccur(error: Error?) -> Void {
        print("Playing failed with error")
        print(error ?? "")
        return
    }

    @objc(setSubscriptionDuration:)
    func setSubscriptionDuration(duration: Double) -> Void {
        subscriptionDuration = duration
    }

    /**********               Player               **********/
    @objc(startRecorder:audioSets:meteringEnabled:resolve:reject:)
    func startRecorder(saveSets: [String: Any], audioSets: [String: Any], meteringEnabled: Bool, resolve: @escaping RCTPromiseResolveBlock,
       rejecter reject: @escaping RCTPromiseRejectBlock) -> Void {

        _meteringEnabled = meteringEnabled;

        let encoding = audioSets["AVFormatIDKeyIOS"] as? String
        let mode = audioSets["AVModeIOS"] as? String
        let avLPCMBitDepth = audioSets["AVLinearPCMBitDepthKeyIOS"] as? Int
        let avLPCMIsBigEndian = audioSets["AVLinearPCMIsBigEndianKeyIOS"] as? Bool
        let avLPCMIsFloatKey = audioSets["AVLinearPCMIsFloatKeyIOS"] as? Bool
        let avLPCMIsNonInterleaved = audioSets["AVLinearPCMIsNonInterleavedIOS"] as? Bool

        var avFormat: Int? = nil
        var avMode: AVAudioSession.Mode = AVAudioSession.Mode.default
        var sampleRate = audioSets["AVSampleRateKeyIOS"] as? Int
        var numberOfChannel = audioSets["AVNumberOfChannelsKeyIOS"] as? Int
        var audioQuality = audioSets["AVEncoderAudioQualityKeyIOS"] as? Int
        var bitRate = audioSets["AVEncoderBitRateKeyIOS"] as? Int

        
        currentTime_now = 0
        saveTimeCycleSecond = saveSets["SaveTimeCycleSecond"] as? Int ?? 120; //120초 (2분)
        saveMaxTimeSecond = saveSets["SaveMaxTimeSecond"] as? Int ?? 86400;//24시간 //28800; //8시간
        div_id = saveSets["div_id"] as? String
        recordDate = saveSets["recordDate"] as? String
        
        let path = saveSets["path"] as? String ?? "audio.wav"
        setAudioFileURL(path: path)

        if (sampleRate == nil) {
            sampleRate = 44100;
        }

        if (encoding == nil) {
            avFormat = Int(kAudioFormatAppleLossless)
        } else {
            if (encoding == "lpcm") {
                avFormat = Int(kAudioFormatAppleIMA4)
            } else if (encoding == "ima4") {
                avFormat = Int(kAudioFormatAppleIMA4)
            } else if (encoding == "aac") {
                avFormat = Int(kAudioFormatMPEG4AAC)
            } else if (encoding == "MAC3") {
                avFormat = Int(kAudioFormatMACE3)
            } else if (encoding == "MAC6") {
                avFormat = Int(kAudioFormatMACE6)
            } else if (encoding == "ulaw") {
                avFormat = Int(kAudioFormatULaw)
            } else if (encoding == "alaw") {
                avFormat = Int(kAudioFormatALaw)
            } else if (encoding == "mp1") {
                avFormat = Int(kAudioFormatMPEGLayer1)
            } else if (encoding == "mp2") {
                avFormat = Int(kAudioFormatMPEGLayer2)
            } else if (encoding == "mp4") {
                avFormat = Int(kAudioFormatMPEG4AAC)
            } else if (encoding == "alac") {
                avFormat = Int(kAudioFormatAppleLossless)
            } else if (encoding == "amr") {
                avFormat = Int(kAudioFormatAMR)
            } else if (encoding == "flac") {
                if #available(iOS 11.0, *) {
                    avFormat = Int(kAudioFormatFLAC)
                }
            } else if (encoding == "opus") {
                avFormat = Int(kAudioFormatOpus)
            } else if(encoding == "wav") {
                avFormat = Int(kAudioFormatLinearPCM)
            }
        }

        if (mode == "measurement") {
            avMode = AVAudioSession.Mode.measurement
        } else if (mode == "gamechat") {
            avMode = AVAudioSession.Mode.gameChat
        } else if (mode == "movieplayback") {
            avMode = AVAudioSession.Mode.moviePlayback
        } else if (mode == "spokenaudio") {
            avMode = AVAudioSession.Mode.spokenAudio
        } else if (mode == "videochat") {
            avMode = AVAudioSession.Mode.videoChat
        } else if (mode == "videorecording") {
            avMode = AVAudioSession.Mode.videoRecording
        } else if (mode == "voicechat") {
            avMode = AVAudioSession.Mode.voiceChat
        } else if (mode == "voiceprompt") {
            if #available(iOS 12.0, *) {
                avMode = AVAudioSession.Mode.voicePrompt
            } else {
                // Fallback on earlier versions
            }
        }


        if (numberOfChannel == nil) {
            numberOfChannel = 2
        }

        if (audioQuality == nil) {
            audioQuality = AVAudioQuality.medium.rawValue
        }

        if (bitRate == nil) {
            bitRate = 128000
        }

        func startRecording() {
            let settings = [
                AVSampleRateKey: sampleRate!,
                AVFormatIDKey: avFormat!,
                AVNumberOfChannelsKey: numberOfChannel!,
                AVEncoderAudioQualityKey: audioQuality!,
                AVLinearPCMBitDepthKey: avLPCMBitDepth ?? AVLinearPCMBitDepthKey.count,
                AVLinearPCMIsBigEndianKey: avLPCMIsBigEndian ?? true,
                AVLinearPCMIsFloatKey: avLPCMIsFloatKey ?? false,
                AVLinearPCMIsNonInterleaved: avLPCMIsNonInterleaved ?? false,
                AVEncoderBitRateKey: bitRate!
            ] as [String : Any]

            do {
                audioRecorder = try AVAudioRecorder(url: audioFileURL!, settings: settings)

                if (audioRecorder != nil) {
                    audioRecorder.prepareToRecord()
                    audioRecorder.delegate = self
                    audioRecorder.isMeteringEnabled = _meteringEnabled
                    let isRecordStarted = audioRecorder.record()

                    if !isRecordStarted {
                        reject("RNAudioPlayerRecorder", "Error occured during initiating recorder", nil)
                        return
                    }

                    startRecorderTimer()

                    resolve(audioFileURL?.absoluteString)
                    return
                }

                reject("RNAudioPlayerRecorder", "Error occured during initiating recorder", nil)
            } catch {
                reject("RNAudioPlayerRecorder", "Error occured during recording", nil)
            }
        }

        audioSession = AVAudioSession.sharedInstance()

        do {
            try audioSession.setCategory(.playAndRecord, mode: avMode, options: [AVAudioSession.CategoryOptions.defaultToSpeaker, AVAudioSession.CategoryOptions.allowBluetooth])
            try audioSession.setActive(true)

            audioSession.requestRecordPermission { granted in
                DispatchQueue.main.async {
                    if granted {
                        startRecording()
                    } else {
                        reject("RNAudioPlayerRecorder", "Record permission not granted", nil)
                    }
                }
            }
        } catch {
            reject("RNAudioPlayerRecorder", "Failed to record", nil)
        }
    }

    @objc(stopRecorder:rejecter:)
    public func stopRecorder(
        resolve: @escaping RCTPromiseResolveBlock,
        rejecter reject: @escaping RCTPromiseRejectBlock
    ) -> Void {
        
        
        if (audioRecorder == nil) {
            reject("RNAudioPlayerRecorder", "Failed to stop recorder. It is already nil.", nil)
            return
        }

        audioRecorder.stop()

        if (recordTimer != nil) {
            recordTimer!.invalidate()
            recordTimer = nil
        }
        
        
        resolve(audioFileURL?.absoluteString)
        
    }

    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        if !flag {
            print("Failed to stop recorder")
        }
    }

    /**********               Player               **********/
    func addPeriodicTimeObserver() {
        let timeScale = CMTimeScale(NSEC_PER_SEC)
        let time = CMTime(seconds: subscriptionDuration, preferredTimescale: timeScale)

        timeObserverToken = audioPlayer.addPeriodicTimeObserver(forInterval: time,
                                                                queue: .main) {_ in
            if (self.audioPlayer != nil) {
                self.sendEvent(withName: "rn-playback", body: [
                    "isMuted": self.audioPlayer.isMuted,
                    "currentPosition": self.audioPlayerItem.currentTime().seconds * 1000,
                    "duration": self.audioPlayerItem.asset.duration.seconds * 1000,
                ])
            }
        }
    }

    func removePeriodicTimeObserver() {
        if let timeObserverToken = timeObserverToken {
            audioPlayer.removeTimeObserver(timeObserverToken)
            self.timeObserverToken = nil
        }
    }


    @objc(startPlayer:httpHeaders:resolve:rejecter:)
    public func startPlayer(
        path: String,
        httpHeaders: [String: String],
        resolve: @escaping RCTPromiseResolveBlock,
        rejecter reject: @escaping RCTPromiseRejectBlock
    ) -> Void {
        audioSession = AVAudioSession.sharedInstance()

        do {
            try audioSession.setCategory(.playAndRecord, mode: .default, options: [AVAudioSession.CategoryOptions.defaultToSpeaker, AVAudioSession.CategoryOptions.allowBluetooth])
            try audioSession.setActive(true)
        } catch {
            reject("RNAudioPlayerRecorder", "Failed to play", nil)
        }
//        
        audioFileURL = URL(string: path)

        setAudioFileURL(path: audioFileURL!.absoluteString)
        audioPlayerAsset = AVURLAsset(url: audioFileURL!, options:["AVURLAssetHTTPHeaderFieldsKey": httpHeaders])
        audioPlayerItem = AVPlayerItem(asset: audioPlayerAsset!)

        if (audioPlayer == nil) {
            audioPlayer = AVPlayer(playerItem: audioPlayerItem)
        } else {
            audioPlayer.replaceCurrentItem(with: audioPlayerItem)
        }
        print("audioPlayer.currentItem : \(audioPlayer.currentTime())")
        
        addPeriodicTimeObserver()
        audioPlayer.play()
        resolve(audioFileURL?.absoluteString)
    }

    @objc(stopPlayer:rejecter:)
    public func stopPlayer(
        resolve: @escaping RCTPromiseResolveBlock,
        rejecter reject: @escaping RCTPromiseRejectBlock
    ) -> Void {
        if (audioPlayer == nil) {
            return reject("RNAudioPlayerRecorder", "Player has already stopped.", nil)
        }

        audioPlayer.pause()
        self.removePeriodicTimeObserver()
        self.audioPlayer = nil;

        resolve(audioFileURL?.absoluteString)
    }

    @objc(pausePlayer:rejecter:)
    public func pausePlayer(
        resolve: @escaping RCTPromiseResolveBlock,
        rejecter reject: @escaping RCTPromiseRejectBlock
    ) -> Void {
        if (audioPlayer == nil) {
            return reject("RNAudioPlayerRecorder", "Player is not playing", nil)
        }

        audioPlayer.pause()
        resolve("Player paused!")
    }

    @objc(resumePlayer:rejecter:)
    public func resumePlayer(
        resolve: @escaping RCTPromiseResolveBlock,
        rejecter reject: @escaping RCTPromiseRejectBlock
    ) -> Void {
        if (audioPlayer == nil) {
            return reject("RNAudioPlayerRecorder", "Player is null", nil)
        }

        audioPlayer.play()
        resolve("Resumed!")
    }

    @objc(seekToPlayer:resolve:rejecter:)
    public func seekToPlayer(
        time: Double,
        resolve: @escaping RCTPromiseResolveBlock,
        rejecter reject: @escaping RCTPromiseRejectBlock
    ) -> Void {
        if (audioPlayer == nil) {
            return reject("RNAudioPlayerRecorder", "Player is null", nil)
        }

        audioPlayer.seek(to: CMTime(seconds: time / 1000, preferredTimescale: CMTimeScale(NSEC_PER_SEC)))
        resolve("Resumed!")
    }

    @objc(setVolume:resolve:rejecter:)
    public func setVolume(
        volume: Float,
        resolve: @escaping RCTPromiseResolveBlock,
        rejecter reject: @escaping RCTPromiseRejectBlock
    ) -> Void {
        audioPlayer.volume = volume
        resolve(volume)
    }
}
extension RNAudioRecorderPlayer: URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64, totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        print("progress = ", Double(bytesSent) / Double(totalBytesSent))
    }
    
}
